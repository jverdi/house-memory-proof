"""Review-only evaluator for sealed pose traces; never invoked by a candidate.

All output is aggregate. Raw source/query arrays and oracle poses remain local.
No replay or native compilation is performed by this module.
"""
import argparse
import base64
from collections import Counter, defaultdict
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
import zipfile

import numpy as np

import trace_contract as contract

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/simulation"))
from pose_metrics import distribution, pose_errors, rigid

spec = importlib.util.spec_from_file_location("retained_depth_geometry", ROOT / "experiments/localization-depth-audit/summarize.py")
geometry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geometry)

PUBLIC_KEYS = {"schema", "complete", "trace", "traceSHA256", "candidateBinarySHA256",
               "inputManifestSHA256", "oracleReadDenied", "queryLabelsExcluded",
               "originalGatePassed", "queryOutcomes", "solvesExcludedFromGeometry",
               "solveGroups", "sourceMetrics", "physicalQualification", "precisionEnabled",
               "limitations"}
MAX_METRIC_SAMPLES = 2_000_000


def load_json(path, limit=64*1024*1024):
    contract.require(path.stat().st_size <= limit, "Private input exceeds evaluator bound")
    def pairs(items):
        result = {}
        for key, value in items:
            contract.require(key not in result, "Duplicate JSON field")
            result[key] = value
        return result
    def invalid(_):
        raise ValueError("Nonfinite private JSON")
    return json.loads(path.read_bytes(), object_pairs_hook=pairs, parse_constant=invalid)


def unique(rows, key):
    result = {r[key]: r for r in rows}
    contract.require(len(result) == len(rows), "Duplicate private identity")
    return result


def observed_pose(state, offset):
    """Undo the solver's local centroid and OpenCV right/down/forward axes."""
    rotation = np.asarray(state[offset:offset+3], float)
    translation = np.asarray(state[offset+3:offset+6], float)
    angle = float(np.linalg.norm(rotation))
    if angle < 1e-12:
        r = np.eye(3)
    else:
        x, y, z = rotation/angle
        skew = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
        r = np.eye(3) + math.sin(angle)*skew + (1-math.cos(angle))*(skew@skew)
    output = np.eye(4)
    output[:3, :3] = r.T @ np.diag([1, -1, -1])
    output[:3, 3] = -r.T@translation + np.asarray(state[1:4])
    values = output.flatten().tolist()
    rigid(values)
    return values


class Metrics:
    def __init__(self, limit=MAX_METRIC_SAMPLES):
        self.limit, self.count = limit, 0
        self.values = defaultdict(list)

    def add(self, key, values):
        values = [float(x) for x in values]
        contract.require(all(math.isfinite(x) and x >= 0 for x in values), "Invalid residual")
        contract.require(self.count + len(values) <= self.limit, "Metric sample budget exhausted")
        self.values[key].extend(values)
        self.count += len(values)

    def report(self):
        return {key: distribution(values) for key, values in sorted(self.values.items())}


def solve_metrics(row, truth, query_surface, surface_valid, metrics):
    """Score actual inputs and selected indices, including rejected solves."""
    points = np.asarray(row["xyz"], float).reshape(-1, 3)
    pixels = np.asarray(row["xy"], float).reshape(-1, 2)
    camera = np.asarray(truth, float).reshape(4, 4)
    local = (points-camera[:3, 3])@camera[:3, :3]
    visible = -local[:, 2] > 1e-8
    projected = geometry.project(points, truth, row["intrinsics"])
    selected = np.asarray(row["inlierIndices"], int)
    counts = {}
    for label, indices in (("input", np.arange(len(points))), ("selected", selected)):
        seen = indices[visible[indices]]
        surface = indices[surface_valid[indices]]
        metrics.add(label+"QueryPixels", np.linalg.norm(projected[seen]-pixels[seen], axis=1))
        metrics.add(label+"QueryRayMetres", np.linalg.norm(points[surface]-query_surface[surface], axis=1))
        surface_local = (query_surface[surface]-camera[:3, 3])@camera[:3, :3]
        metrics.add(label+"QueryDepthMetres", np.abs(local[surface, 2]-surface_local[:, 2]))
        counts[label+"Correspondences"] = len(indices)
        counts[label+"BehindTruthCamera"] = len(indices)-len(seen)
        counts[label+"WithoutTruthSurface"] = len(indices)-len(surface)
    for name, flag, offset in (("ransac", 3, 4), ("refined", 7, 10)):
        if row["state"][0] >= flag:
            pose = observed_pose(row["state"], offset)
            error = pose_errors(pose, truth)
            metrics.add(name+"PositionMetres", [error["positionMetres"]])
            metrics.add(name+"RotationDegrees", [error["rotationDegrees"]])
            if name == "refined" and row["status"] == 1:
                contract.require(max(abs(a-b) for a, b in zip(pose, row["matrix"])) < 1e-7,
                                 "Observer pose differs from returned production pose")
    return counts


def summarize(report_file, stage):
    contract.require(stage in ("rough", "finished"), "Undeclared source stage")
    audit = report_file.with_suffix(".audit")
    report = load_json(report_file)
    oracle = load_json(audit/"oracle.json")
    sealed = load_json(audit/"sealed-candidate.json")
    contract.require(sealed.get("oracleReadDenied") is True and sealed.get("queryLabelsExcluded") is True
                     and type(sealed.get("candidateBinarySHA256")) is str
                     and re.fullmatch("[0-9a-f]{64}",sealed["candidateBinarySHA256"])
                     and sealed.get("candidateBinarySHA256") == report.get("candidateBinarySHA256"), "Candidate was not sealed")
    contract.require(type(report.get("passed")) is bool, "Missing original gate outcome")
    images = load_json(audit/"images.json", 128*1024*1024)
    names = load_json(audit/"query-names.json")
    expected = unique(oracle["queries"], "image")
    outcomes = unique(report["queries"], "image")
    contract.require(all(type(q.get("accepted")) is bool for q in outcomes.values()), "Invalid query outcome")
    contract.require(set(outcomes) == set(expected) == set(names.values()) and len(names) == len(expected), "Missing query denominator")
    query_images = unique(images["queries"], "image")
    contract.require(set(query_images) == set(names), "Missing private query features")
    with zipfile.ZipFile(audit/"input.hxray") as archive:
        contract.require(archive.getinfo("house.json").file_size <= 64*1024*1024
                         and archive.getinfo("manifest.json").file_size <= 16*1024*1024, "Archive metadata exceeds bound")
        house = json.loads(archive.read("house.json"))
        manifest_hash = hashlib.sha256(archive.read("manifest.json")).hexdigest()
    observations = unique(house["observations"], "id")
    segments = unique(house["segments"], "id")
    sources = unique(images["sources"], "observationID")
    layouts = unique(oracle["completeLayout"], "room")
    source_geometry = oracle["oracleOnlyFinishedGeometry" if stage == "finished" else "oracleOnlyGeometry"]
    source_lookup = {}
    # Exact map coordinates and original descriptor identities only. Duplicate
    # source pixels or coordinates are explicitly unscored, never guessed.
    for path in sorted(audit.glob("map-*.json")):
        m = load_json(path)
        contract.require(m["frameID"] == m["segmentID"], "Evaluator requires declared unregistered source frames")
        descriptors = base64.b64decode(m["descriptors"], validate=True)
        contract.require(len(descriptors) == len(m["points"])*32, "Invalid map descriptors")
        for view in m["views"]:
            identity = view["observationID"]
            source = sources[identity]
            raw = base64.b64decode(source["descriptors"], validate=True)
            xy = np.asarray(source["xy"]).reshape(-1, 2)*[source["cameraWidth"], source["cameraHeight"]]
            contract.require(len(raw) == len(xy)*32 == source["count"]*32, "Invalid source features")
            descriptor_pixels = defaultdict(list)
            for i, pixel in enumerate(xy):
                descriptor_pixels[raw[i*32:(i+1)*32]].append(pixel)
            lookup = defaultdict(list)
            for i in range(view["start"], view["start"]+view["count"]):
                p = m["points"][i]
                lookup[(p["x"], p["y"], p["z"])].extend(descriptor_pixels[descriptors[i*32:(i+1)*32]])
            source_lookup[identity] = lookup
    group_counts = defaultdict(Counter)
    group_metrics = {}
    source_metrics = Metrics()
    source_counts = Counter()
    excluded = Counter()
    query_counts = Counter()
    sample_total = 0

    def visit(row):
        nonlocal sample_total
        if row["type"] not in ("begin", "end", "solve"):
            return
        q = expected[names[row["query"]]]
        outcome = outcomes[q["image"]]
        label = "accepted" if outcome["accepted"] else "abstained"
        if row["type"] == "begin":
            query_counts[("positive" if q["shouldMatch"] is True else "negative")+label.title()] += 1
            return
        if row["type"] == "end":
            contract.require(row["accepted"] == outcome["accepted"], "Trace outcome differs from sealed report")
            return
        # Wrong-room/floor and altered-scene probes retain outcome denominators;
        # their selected-map coordinate frame is not the query's truth frame.
        if q["shouldMatch"] is not True:
            excluded["negativeQuerySolves"] += 1
            excluded["negativeQueryCorrespondences"] += len(row["queryIndices"])
            return
        segment = segments[q["segmentID"]]
        contract.require(all(observations[s]["segmentID"] == segment["id"] for s in row["sourceIDs"]), "Mixed coordinate frames in pose input")
        contract.require(row["width"] == q["width"] and row["height"] == q["height"] and row["intrinsics"] == q["intrinsics"], "Query camera contract differs")
        rigid(q["expectedCamera"])
        pixels = np.asarray(row["xy"]).reshape(-1, 2)
        image = query_images[row["query"]]
        image_pixels = np.asarray(image["xy"]).reshape(-1, 2)*[q["width"], q["height"]]
        contract.require(max(row["queryIndices"]) < len(image_pixels) and
                         np.max(np.abs(image_pixels[row["queryIndices"]]-pixels)) < 1e-5, "Correspondences differ from observed query features")
        origin = layouts[segment["roomID"]]["origin"]
        query_geometry = oracle["oracleOnlyFinishedGeometry" if "finished" in q.get("scenario", "") else "oracleOnlyGeometry"]
        surface, valid = geometry.ray_points(pixels, q["intrinsics"], q["expectedCamera"], origin, query_geometry)
        key = row["kind"]+"/"+label+"/"+("returned" if row["status"] == 1 else "rejected")
        metrics = group_metrics.setdefault(key, Metrics())
        before = metrics.count
        group_counts[key].update(solve_metrics(row, q["expectedCamera"], surface, valid, metrics))
        group_counts[key]["solves"] += 1
        sample_total += metrics.count-before
        if row["kind"] == "individual":
            identity = row["sourceIDs"][0]
            source = observations[identity]
            truth = geometry.CANONICAL@np.asarray(oracle["mappingCameras"][identity]).reshape(4, 4)
            selected = set(row["inlierIndices"])
            for index, point in enumerate(np.asarray(row["xyz"]).reshape(-1, 3)):
                matches = source_lookup.get(identity, {}).get(tuple(point), [])
                for bucket in (["input", "selected"] if index in selected else ["input"]):
                    source_counts[bucket+"Correspondences"] += 1
                    if len(matches) != 1:
                        source_counts[bucket+"WithoutUniqueSourcePixel"] += 1
                        continue
                    pixel = np.asarray(matches[0]).reshape(1, 2)
                    ray, hit = geometry.ray_points(pixel, source["intrinsics"], truth, origin, source_geometry)
                    local = (point-truth[:3, 3])@truth[:3, :3]
                    if -local[2] > 1e-8:
                        residual = geometry.project(point.reshape(1, 3), truth, source["intrinsics"])-pixel
                        source_metrics.add(bucket+"SourcePixels", [np.linalg.norm(residual)])
                    else:
                        source_counts[bucket+"BehindTruthCamera"] += 1
                    if hit[0]:
                        source_metrics.add(bucket+"SourceRayMetres", [np.linalg.norm(point-ray[0])])
                        truth_depth = (ray[0]-truth[:3, 3])@truth[:3, :3]
                        source_metrics.add(bucket+"SourceDepthMetres", [abs(local[2]-truth_depth[2])])
                    else:
                        source_counts[bucket+"WithoutTruthSurface"] += 1
        contract.require(sample_total+source_metrics.count <= MAX_METRIC_SAMPLES, "Combined metric sample budget exhausted")

    trace_path = audit/"pose-trace/trace.jsonl"
    contract.require(trace_path.stat().st_size <= contract.MAX_BYTES, "Private trace exceeds bound")
    digest = hashlib.sha256()
    with trace_path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            digest.update(block)
        contract.require(digest.hexdigest() == sealed.get("traceSHA256"), "Trace differs from sealed candidate output")
        stream.seek(0)
        trace = contract.inspect(stream, len(expected), visit)
    result = dict(schema=1, complete=True, trace=trace, traceSHA256=digest.hexdigest(),
                  candidateBinarySHA256=sealed["candidateBinarySHA256"], inputManifestSHA256=manifest_hash,
                  oracleReadDenied=True, queryLabelsExcluded=True, originalGatePassed=report["passed"],
                  queryOutcomes=dict(query_counts), solvesExcludedFromGeometry=dict(excluded),
                  solveGroups={key: dict(counts=dict(group_counts[key]), metrics=group_metrics[key].report()) for key in sorted(group_counts)},
                  sourceMetrics=dict(counts=dict(source_counts), metrics=source_metrics.report()),
                  physicalQualification=False, precisionEnabled=False,
                  limitations=["Development diagnosis only; actual inputs and selected inliers, with accepted and abstained query denominators",
                               "Counts are solve-correspondence samples, not unique physical features; repeated solves count separately",
                               "Source-pixel metrics cover individual solves only; pooled/consensus inputs retain query-ray and pose metrics",
                               "Ambiguous source identities and missing oracle intersections remain explicit; no fabricated truth or alignment",
                               "No raw identities, images, poses, coordinates or oracle arrays are published; original gates unchanged"])
    contract.require(set(result) == PUBLIC_KEYS, "Aggregate allowlist changed")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--stage", choices=["rough", "finished"], required=True)
    args = parser.parse_args()
    contract.require(args.output.resolve() != args.report.resolve(), "Preserve sealed input")
    summary = summarize(args.report, args.stage)
    args.output.write_text(json.dumps(summary, indent=2, allow_nan=False)+"\n")
    print(json.dumps({"complete": summary["complete"], "originalGatePassed": summary["originalGatePassed"]}))
