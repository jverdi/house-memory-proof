"""Allowlisted failure metadata only; never publish candidate stderr or paths."""
import json

PREFIX = 'HX_POSE_OBSERVER_FAILURE '
PHASES = {'initialization', 'mapping', 'queries', 'trace-finalization', 'private-export', 'report'}
KINDS = {'unknown', 'directory', 'create', 'open', 'record-serialization', 'record-bounds', 'record-write', 'query-bound', 'query-denominator', 'synchronize', 'close'}
DOMAINS = {'NSCocoaErrorDomain', 'NSPOSIXErrorDomain', 'other'}
KEYS = {'schema', 'phase', 'kind', 'domain', 'code'}


def validate_failure(value):
    if not isinstance(value, dict) or set(value) != KEYS:
        return None
    if any(type(value[k]) is not str for k in ('phase', 'kind', 'domain')):
        return None
    if (type(value['schema']) is not int or value['schema'] != 1 or value['phase'] not in PHASES or
            value['kind'] not in KINDS or value['domain'] not in DOMAINS or
            type(value['code']) is not int or not -100000 <= value['code'] <= 100000):
        return None
    return dict(value)


def read_failure(stderr):
    if not isinstance(stderr, str) or len(stderr) > 1048576:
        return None
    found = []
    for line in stderr.splitlines():
        if not line.startswith(PREFIX):
            continue
        if len(line) > 1024:
            return None
        try:
            pairs = json.loads(line[len(PREFIX):], object_pairs_hook=list)
            if not isinstance(pairs, list) or any(not isinstance(x, tuple) or len(x) != 2 for x in pairs):
                return None
            value = dict(pairs)
            if len(value) != len(pairs):
                return None
            checked = validate_failure(value)
        except (ValueError, TypeError):
            return None
        if checked is None:
            return None
        found.append(checked)
    return found[0] if len(found) == 1 else None
