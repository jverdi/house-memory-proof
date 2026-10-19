"""Strict bounded reader for private pose traces; exports aggregate counts only.

This validates completeness, not localization accuracy. The future separate
oracle evaluator must consume validated records without broadening this output.
"""
import json
import math
import re
from collections import Counter

MAX_LINE = 8_388_608
MAX_BYTES = 1_073_741_824
MAX_SOLVES = 8192
MAX_QUERIES = 512
UUID = re.compile(r"^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")
PUBLIC_KEYS = {"schema", "complete", "queries", "acceptedQueries", "abstainedQueries",
               "solves", "solveKinds", "solveStatus", "inputCorrespondences", "selectedInliers"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, low, high):
    return type(value) is int and low <= value <= high


def finite(values, count):
    return (type(values) is list and len(values) == count and
            all(type(x) in (int, float) and math.isfinite(x) for x in values))


def identity(value):
    return (type(value) is str and 0 < len(value) <= 128 and
            not any(x in value for x in ("/", "\\", "..")) and
            all(32 <= ord(x) < 127 for x in value))


def solve(row, current):
    require(set(row) == {"type", "sequence", "query", "kind", "sourceIDs", "queryIndices",
                         "xyz", "xy", "width", "height", "intrinsics", "status", "matrix",
                         "rejection", "inlierCount", "inlierIndices", "observerReadSucceeded", "state"},
            "Unexpected solve fields")
    require(row["query"] == current and current is not None, "Solve outside query")
    require(row["kind"] in ("individual", "pooled", "consensus"), "Unknown solve kind")
    sources = row["sourceIDs"]
    require(type(sources) is list and 1 <= len(sources) <= 120 and
            all(type(x) is str and UUID.fullmatch(x) for x in sources) and len(set(sources)) == len(sources), "Invalid source identities")
    require(row["kind"] != "individual" or len(sources) == 1, "Individual solve source count")
    query = row["queryIndices"]
    require(type(query) is list and 30 <= len(query) <= 2400 and
            all(integer(x, 0, 2399) for x in query) and len(set(query)) == len(query), "Invalid correspondence identities")
    n = len(query)
    require(finite(row["xyz"], n*3) and finite(row["xy"], n*2), "Invalid correspondence coordinates")
    require(integer(row["width"], 64, 4096) and integer(row["height"], 64, 4096), "Invalid image dimensions")
    require(finite(row["intrinsics"], 9), "Invalid intrinsics")
    require(integer(row["status"], -2, 1) and integer(row["rejection"], 0, 7), "Invalid solver outcome")
    require(row["observerReadSucceeded"] is True, "Incomplete observer read")
    indices = row["inlierIndices"]
    require(type(indices) is list and len(indices) <= n and all(integer(i, 0, n-1) for i in indices)
            and len(set(indices)) == len(indices), "Invalid selected indices")
    require(integer(row["inlierCount"], 0, n) and row["inlierCount"] == len(indices), "Inlier count mismatch")
    require(finite(row["state"], 16) and row["state"][0] in (0, 1, 3, 7), "Invalid observer state")
    require(row["state"][0] >= 3 or len(indices) == 0, "Inliers without RANSAC")
    if row["status"] == 1:
        require(row["state"][0] == 7 and row["rejection"] == 0 and len(indices) >= 30 and
                finite(row["matrix"], 16), "Incomplete accepted pose")
    else:
        require(row["matrix"] == [], "Rejected solve has returned pose")
    return n, len(indices)


def inspect(stream, expected_queries, on_record=None):
    require(integer(expected_queries, 1, MAX_QUERIES), "Expected denominator outside bound")
    sequence = byte_count = solves = accepted = inputs = selected = ended = 0
    current = None
    seen = set()
    kinds, statuses = Counter(), Counter()
    footer = False
    while True:
        raw = stream.readline(MAX_LINE + 1)
        if not raw:
            break
        byte_count += len(raw)
        require(not footer and len(raw) <= MAX_LINE and raw.endswith(b"\n") and byte_count <= MAX_BYTES,
                "Trace is truncated, trailing, or oversized")
        def reject_constant(_):
            raise ValueError("Nonfinite JSON value")
        def unique_pairs(pairs):
            values = {}
            for key, value in pairs:
                require(key not in values, "Duplicate JSON field")
                values[key] = value
            return values
        row = json.loads(raw, parse_constant=reject_constant, object_pairs_hook=unique_pairs)
        require(type(row) is dict and row.get("sequence") == sequence and type(row.get("sequence")) is int,
                "Missing or reordered record")
        kind = row.get("type")
        if sequence == 0:
            require(row == {"sequence": 0, "type": "header", "schema": 1,
                           "coordinateFrame": "centroid-local-opencv", "limitBytes": MAX_BYTES,
                           "limitSolves": MAX_SOLVES}, "Unexpected header")
        elif kind == "begin":
            require(set(row) == {"sequence", "type", "query"} and current is None and
                    identity(row.get("query")) and row["query"] not in seen and len(seen) < MAX_QUERIES,
                    "Duplicate or invalid query start")
            current = row["query"]; seen.add(current)
        elif kind == "solve":
            require(solves < MAX_SOLVES, "Solve count exceeds bound")
            n, m = solve(row, current)
            solves += 1; inputs += n; selected += m
            kinds[row["kind"]] += 1; statuses[str(row["status"])] += 1
        elif kind == "end":
            require(set(row) == {"sequence", "type", "query", "accepted", "reason"} and
                    current is not None and row["query"] == current and type(row["accepted"]) is bool and
                    row["reason"] in ("no-map", "ambiguous", "evaluated"), "Invalid query end")
            require(row["reason"] == "evaluated" or not row["accepted"], "Accepted absent/ambiguous map")
            accepted += int(row["accepted"]); ended += 1; current = None
        elif kind == "footer":
            require(row == {"sequence": sequence, "type": "footer", "queries": expected_queries,
                           "solves": solves, "complete": True} and current is None and
                    ended == expected_queries == len(seen), "Incomplete trace denominator")
            footer = True
        else:
            raise ValueError("Unknown record")
        if on_record is not None:
            on_record(row)
        sequence += 1
    require(footer, "Missing completion record")
    public = dict(schema=1, complete=True, queries=ended, acceptedQueries=accepted,
                  abstainedQueries=ended-accepted, solves=solves, solveKinds=dict(kinds),
                  solveStatus=dict(statuses), inputCorrespondences=inputs, selectedInliers=selected)
    require(set(public) == PUBLIC_KEYS, "Public aggregate allowlist changed")
    return public
