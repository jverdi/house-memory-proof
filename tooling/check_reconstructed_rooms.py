#!/usr/bin/env python3
"""Independently score native transitions against registered reconstruction triangles.

The private source package is read locally; only aggregate results are emitted.
Registration and floor classification are deliberately supplied by this fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path
from check_reconstructed_navigation import Surface, point, require

OFFSETS = ((0, 0, 0), (1.2, 0, 0), (0, 0, 3.2))


def read_report(report, package_bytes):
    require(report.get('version') == 1 and report.get('profile') == 'registered-reconstructed-fragments-v1', 'Unknown registered-fragment profile')
    require(hashlib.sha256(package_bytes).hexdigest() == report.get('privatePackageSHA256'), 'Private package hash differs')
    for key in ('passed', 'registrationSupplied', 'floorClassificationSupplied', 'walkingEnabled', 'upperWalkingEnabled', 'sourceGeometryUnchanged', 'missingFloorRefused'):
        require(report.get(key) is True, 'Native registered navigation failed: '+key)
    for key in ('wholeHouseQualified', 'physicalQualification', 'protectedBenchmark', 'graphLimited'):
        require(report.get(key) is False, 'Incomplete graph or unjustified qualification: '+key)
    require(report.get('fragments') == 3 and report.get('capturedViewsPerFragment') == 9 and report.get('generatorMeshesSupplied') == 0, 'Fixture denominators changed')
    require(report.get('links') == [[0, 1]], 'Wrong-floor or unsupported connection')
    h = json.loads(package_bytes)
    rooms, segments, features, observations = (h.get(k, []) for k in ('rooms', 'segments', 'features', 'observations'))
    require(h.get('isDemo') is True and len(rooms) == len(segments) == len(features) == 3 and len(observations) == 27, 'Incomplete reconstructed fragments')
    for collection in (rooms, segments, features, observations):
        require(len({x['id'] for x in collection}) == len(collection), 'Duplicate source identity')
    counts = report.get('vertices', [])
    require(len(counts) == 3, 'Missing vertex inventory')
    surfaces = []
    for i, offset in enumerate(OFFSETS):
        room, segment, feature = rooms[i], segments[i], features[i]
        require(segment.get('roomID') == room['id'] and feature.get('roomID') == room['id'] and feature.get('segmentID') == segment['id'], 'Cross-room source link')
        require(room.get('level') == (1 if i == 2 else 0), 'Wrong floor metadata')
        matrix = [1,0,0,offset[0],0,1,0,offset[1],0,0,1,offset[2],0,0,0,1]
        require(segment.get('registration', {}).get('values') == matrix, 'Supplied registration changed')
        records = [o for o in observations if o.get('segmentID') == segment['id']]
        require(all(o.get('roomID') == room['id'] and o.get('stageID') == feature.get('stageID') == segment.get('stageID') for o in records), 'Mixed source frame')
        require(segment.get('stageID') == segments[0].get('stageID'), 'Mixed stage graph')
        surfaces.append(Surface(dict(isDemo=True, features=[feature], observations=records), counts[i]))

    def supported(x, y, z):
        # Evaluate actual local triangles in their supplied registration frame.
        return any(abs(z-offset[2]) < .003 and surface.supports(x-offset[0], y-offset[1])
                   for surface, offset in zip(surfaces, OFFSETS))

    def footprint(x, y, z):
        return all(supported(x+dx, y+dy, z) for dx in (-.2, 0, .2) for dy in (-.2, 0, .2))

    trace = report.get('trace', [])
    require(len(trace) == 16 and report.get('completedSteps') == 16, 'Incomplete seam traversal')
    previous = -.2
    for i, entry in enumerate(trace):
        x, y, z = point(entry)
        target = -.2+(i+1)*.2 if i < 8 else 1.4-(i-7)*.2
        require(abs(x-target) < .0001 and abs(y) < .0001 and abs(z-2) < .003, 'Unexpected native room-boundary movement')
        require(all(footprint(previous+(x-previous)*step/4, y, 0) for step in range(5)), 'Traversal crosses missing reconstructed floor')
        previous = x
    refusal = report.get('missingFloorTrace', [])
    require(len(refusal) == 3, 'Missing unsupported-room refusal attempts')
    require(surfaces[0].footprint(.4, 0) and not surfaces[0].footprint(.6, 0), 'Missing-floor case does not remove support')
    for entry in refusal:
        x, y, z = point(entry)
        require(abs(x-.4) < .0001 and abs(y) < .0001 and abs(z-2) < .003, 'Walking crossed the unsupported room seam')
    upper = point(report.get('upperFloorJump'))
    require(abs(upper[2]-5.2) < .003 and footprint(upper[0], upper[1], 3.2), 'Upper jump lacks reconstructed support')
    require(not supported(.6, 0, 1.6), 'Disconnected floors became a fabricated transition')
    return dict(passed=True, profile=report['profile'], privatePackageSHA256=report['privatePackageSHA256'],
                fragments=3, capturedViews=27, vertices=counts, tracedSteps=16, roomBoundaryCrossings=2,
                supportedRoomLinks=1, refusedSteps=3, disconnectedUpperFloor=True,
                registrationSupplied=True, floorClassificationSupplied=True, rawSourceRecordsPublished=False,
                wholeHouseQualified=False, physicalQualification=False, protectedBenchmark=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('package', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(args.report.stat().st_size < 100000 and args.package.stat().st_size < 64000000, 'Input exceeds fixture bounds')
    require(args.output.resolve() not in (args.report.resolve(), args.package.resolve()), 'Preserve native input evidence')
    result = read_report(json.loads(args.report.read_text()), args.package.read_bytes())
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
