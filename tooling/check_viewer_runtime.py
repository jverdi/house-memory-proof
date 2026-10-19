#!/usr/bin/env python3
"""Validate viewer cadence and sampled resources without granting device acceptance."""
import argparse
import json
import math
from pathlib import Path
from check_capture_runtime import require, number, InvalidRuntime

BOUNDS = [1/120, 1/60, 1/30, .05, .1, .25, .5, 1]


def read_reports(reports):
    require(isinstance(reports, list) and 1 <= len(reports) <= 100, 'Expected 1–100 reports')
    summaries = []
    identities = set()
    for report in reports:
        require(report.get('version') == 1 and report.get('physicalQualification') is False, 'Unsupported or prequalified report')
        require(report.get('intervalUpperBoundsSeconds') == BOUNDS, 'Unknown histogram bounds')
        for key in ['sessionID', 'projectID', 'sourceRevision', 'build', 'hardware', 'systemVersion', 'platform']:
            require(isinstance(report.get(key), str) and 0 < len(report[key]) <= 200, 'Missing source/device identity')
        require(report['sessionID'] not in identities, 'Duplicate session')
        identities.add(report['sessionID'])
        require(type(report.get('projectRevision')) is int and report['projectRevision'] > 0, 'Invalid project revision')
        require(number(report.get('startedUTC')), 'Invalid start time')
        ended = report.get('endedUTC')
        if ended is None:
            require(report.get('stopReason') is None, 'Interrupted session has a stop reason')
        else:
            require(number(ended) and ended >= report['startedUTC'] and isinstance(report.get('stopReason'), str) and report['stopReason'], 'Invalid finalization')
        samples = report.get('samples')
        require(isinstance(samples, list) and 1 <= len(samples) <= 721, 'Invalid sample count')
        previous = None
        intervals = []
        for sample in samples:
            require(number(sample.get('elapsedSeconds')) and sample['elapsedSeconds'] >= 0, 'Invalid elapsed time')
            for key, limit in [('displayedVertices', 100_000_000), ('residentTiles', 512), ('decodedTextures', 24), ('memoryWarnings', 10_000_000)]:
                require(type(sample.get(key)) is int and 0 <= sample[key] <= limit, 'Invalid resource count: '+key)
            require(type(sample.get('navigationWaiting')) is bool and type(sample.get('lowPowerMode')) is bool, 'Missing viewer/power state')
            require(sample.get('thermalState') in ['nominal', 'fair', 'serious', 'critical', 'unknown'], 'Invalid thermal state')
            require(isinstance(sample.get('processMemory'), dict), 'Missing memory status')
            require(all(k in ['physicalFootprintBytes', 'residentBytes', 'lifetimeResidentPeakBytes'] and type(v) is int and 0 <= v < 2**64 for k, v in sample['processMemory'].items()), 'Invalid memory counter')
            r = sample.get('rendering', {})
            require(type(r.get('callbacks')) is int and 0 <= r['callbacks'] <= 10_000_000, 'Invalid callback count')
            require(type(r.get('intervals')) is int and r['intervals'] == max(0, r['callbacks']-1), 'Invalid interval count')
            require(number(r.get('seconds')) and number(r.get('maximumSeconds')) and 0 <= r['maximumSeconds'] <= r['seconds'], 'Invalid interval timing')
            bins = r.get('bins')
            require(isinstance(bins, list) and len(bins) == 9 and all(type(n) is int and 0 <= n <= 10_000_000 for n in bins) and sum(bins) == r['intervals'], 'Invalid histogram')
            if previous:
                p = previous['rendering']
                duration = sample['elapsedSeconds']-previous['elapsedSeconds']
                require(duration > 0 and sample['memoryWarnings'] >= previous['memoryWarnings'], 'Decreasing time or warning count')
                require(all(r[k] >= p[k] for k in ['callbacks', 'intervals', 'seconds', 'maximumSeconds']) and all(a >= b for a, b in zip(bins, p['bins'])), 'Decreasing renderer counters')
                intervals.append(dict(startSeconds=previous['elapsedSeconds'], endSeconds=sample['elapsedSeconds'], renderCallbackHz=(r['callbacks']-p['callbacks'])/duration))
            previous = sample
        r = samples[-1]['rendering']
        # This is an upper histogram bound, never an exact percentile. The
        # overflow bucket is unbounded and must remain unknown in the report.
        target = math.ceil(r['intervals']*.95)
        total = 0
        p95 = None
        if target:
            for index, count in enumerate(r['bins']):
                total += count
                if total >= target:
                    p95 = BOUNDS[index] if index < len(BOUNDS) else None
                    break
        summaries.append(dict(sourceRevision=report['sourceRevision'], build=report['build'], hardware=report['hardware'], platform=report['platform'],
            finalized=ended is not None, stopReason=report.get('stopReason'), observedSeconds=samples[-1]['elapsedSeconds'], intervals=intervals,
            renderCallbacks=r['callbacks'], renderIntervalP95UpperBoundSeconds=p95, renderIntervalMaximumSeconds=r['maximumSeconds'],
            intervalsOver100ms=sum(r['bins'][5:]), sampledPhysicalFootprintPeakBytes=max((s['processMemory']['physicalFootprintBytes'] for s in samples if 'physicalFootprintBytes' in s['processMemory']), default=None),
            sampledThermalStates=sorted({s['thermalState'] for s in samples}), memoryWarnings=samples[-1]['memoryWarnings']))
    return dict(passed=True, sessions=summaries, physicalQualification=False, presentedFrameRateMeasured=False,
        limitations='Renderer completion cadence and sampled resources only. Histogram percentile is an upper bound, or unknown for overflow/no intervals. Successful parsing, simulator output and duration do not qualify owner-device performance.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path);parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    require(args.input.stat().st_size <= 200_000_000, 'Export exceeds report bound')
    data = json.dumps(read_reports(json.loads(args.input.read_text())), indent=2, allow_nan=False)+'\n'
    if args.output:
        require(args.output.resolve() != args.input.resolve(), 'Output must not replace evidence')
        args.output.parent.mkdir(parents=True, exist_ok=True);args.output.write_text(data)
    print(data, end='')


if __name__ == '__main__':
    main()
