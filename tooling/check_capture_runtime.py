#!/usr/bin/env python3
"""Read bounded capture visit evidence; never grant device/precision qualification."""
import argparse
import json
import math
from pathlib import Path


class InvalidRuntime(ValueError):
    pass


def require(value, message):
    if not value:
        raise InvalidRuntime(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def read_reports(reports):
    require(isinstance(reports, list) and 1 <= len(reports) <= 100, 'Expected 1–100 session reports')
    summaries = []
    counters = ['deliveredCameraFrames', 'normalTrackingFrames', 'renderedCallbacks', 'savedImages', 'saveFailures', 'maximumPendingSaves', 'memoryWarnings']
    cumulative = counters + ['completedSaveSeconds', 'maximumSaveSeconds']
    for report in reports:
        require(report.get('version') == 1 and report.get('physicalQualification') is False, 'Unsupported or prequalified report')
        require(report.get('samplePeriodSeconds') == 10 and report.get('sampleLimit') == 721, 'Unexpected sampling policy')
        require(report.get('mode') in ('capture', 'reveal'), 'Unknown capture mode')
        for name in ['sourceRevision', 'build', 'hardware', 'systemVersion', 'platform', 'sessionID', 'projectID']:
            require(isinstance(report.get(name), str) and 0 < len(report[name]) <= 200, 'Missing source or device identity')
        require(number(report.get('startedUTC')), 'Invalid start date')
        samples = report.get('samples')
        require(isinstance(samples, list) and 1 <= len(samples) <= 721, 'Invalid sample count')
        previous = None
        intervals = []
        for sample in samples:
            require(number(sample.get('elapsedSeconds')) and sample['elapsedSeconds'] >= 0, 'Invalid elapsed time')
            for name in counters + ['pendingSaves', 'freeDiskBytes']:
                require(type(sample.get(name)) is int and sample[name] >= 0, 'Invalid counter: '+name)
            for name in ['completedSaveSeconds', 'maximumSaveSeconds']:
                require(number(sample.get(name)) and sample[name] >= 0, 'Invalid save timing')
            require(sample['normalTrackingFrames'] <= sample['deliveredCameraFrames'], 'Tracking count exceeds frames')
            require(sample['pendingSaves'] <= sample['maximumPendingSaves'], 'Invalid backlog maximum')
            require(sample['maximumSaveSeconds'] <= sample['completedSaveSeconds'], 'Invalid maximum save time')
            require(sample.get('thermalState') in ('nominal', 'fair', 'serious', 'critical', 'unknown'), 'Unknown thermal state')
            require(sample.get('batteryState') in ('unknown', 'unplugged', 'charging', 'full'), 'Unknown battery state')
            require(type(sample.get('lowPowerMode')) is bool, 'Missing power mode')
            battery = sample.get('batteryLevel')
            require(battery is None or (number(battery) and 0 <= battery <= 1), 'Invalid battery level')
            require(isinstance(sample.get('processMemory'), dict), 'Missing memory status')
            for name, value in sample['processMemory'].items():
                require(name in ('physicalFootprintBytes', 'residentBytes', 'lifetimeResidentPeakBytes') and type(value) is int and value >= 0, 'Invalid memory counter')
            if previous is not None:
                duration = sample['elapsedSeconds'] - previous['elapsedSeconds']
                require(duration > 0, 'Non-monotonic sample time')
                require(all(sample[k] >= previous[k] for k in cumulative), 'Counter decreased')
                intervals.append(dict(startSeconds=previous['elapsedSeconds'], endSeconds=sample['elapsedSeconds'], seconds=duration,
                    cameraCallbackHz=(sample['deliveredCameraFrames']-previous['deliveredCameraFrames'])/duration,
                    renderCallbackHz=(sample['renderedCallbacks']-previous['renderedCallbacks'])/duration,
                    savedImagesPerSecond=(sample['savedImages']-previous['savedImages'])/duration))
            previous = sample
        last = samples[-1]
        acquisition_end = report.get('acquisitionEndSeconds')
        require(acquisition_end is None or (number(acquisition_end) and 0 <= acquisition_end <= last['elapsedSeconds']), 'Invalid acquisition end')
        ended = report.get('endedUTC')
        require(ended is None or (number(ended) and ended >= report['startedUTC'] and acquisition_end is not None and isinstance(report.get('stopReason'), str)), 'Invalid finalized session')
        # Intervals after capture stops are retained as final-save latency, never pooled into camera rate.
        active = [i for i in intervals if acquisition_end is None or i['endSeconds'] <= acquisition_end]
        battery_samples = [s['batteryLevel'] for s in samples if s.get('batteryLevel') is not None]
        memory = [s['processMemory']['physicalFootprintBytes'] for s in samples if 'physicalFootprintBytes' in s['processMemory']]
        summaries.append(dict(sourceRevision=report['sourceRevision'], build=report['build'], platform=report['platform'], mode=report['mode'],
            finalized=ended is not None, stopReason=report.get('stopReason'), observedSeconds=last['elapsedSeconds'], acquisitionEndSeconds=acquisition_end,
            activeIntervals=active, largestSampleGapSeconds=max((i['seconds'] for i in intervals), default=None),
            deliveredCameraFrames=last['deliveredCameraFrames'], normalTrackingFrames=last['normalTrackingFrames'], savedImages=last['savedImages'], saveFailures=last['saveFailures'],
            maximumPendingSaves=last['maximumPendingSaves'], maximumSaveSeconds=last['maximumSaveSeconds'], memoryWarnings=last['memoryWarnings'],
            sampledPhysicalFootprintPeakBytes=max(memory, default=None), sampledThermalStates=sorted({s['thermalState'] for s in samples}),
            batteryChange=battery_samples[-1]-battery_samples[0] if len(battery_samples)>1 else None,
            volumeFreeBytesChange=last['freeDiskBytes']-samples[0]['freeDiskBytes']))
    return dict(passed=True, reader='Independent Python capture workload reader', sessions=summaries,
        physicalQualification=False, precisionEnabled=False, presentedFrameRateMeasured=False,
        limitations='Sampled resource evidence only; counters are callback rates. External disk activity, charging and sampling gaps need review. Incomplete sessions and missing battery/memory remain explicit. Neither duration nor successful decoding grants device acceptance.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    require(args.input.stat().st_size<=200_000_000,'Export exceeds bounded report size')
    report=read_reports(json.loads(args.input.read_text()))
    data=json.dumps(report,indent=2,allow_nan=False)+'\n'
    if args.output:
        require(args.output.resolve()!=args.input.resolve(),'Output must not replace evidence')
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(data)
    print(data,end='')


if __name__=='__main__':main()
