#!/usr/bin/env python3
"""Independently score the public connected-walk fixture's native trace."""
import argparse
import json
import math
from pathlib import Path


class InvalidNavigation(ValueError):
    pass


NAMES = [
    'six rooms and sixteen stair treads in both directions',
    'closed door preserves the observed corridor but refuses passage',
    'missing stair tread refuses unsupported continuation',
    'low stair headroom refuses passage',
    'unobserved doorway never invents a camera connection',
    'unregistered repeated room remains a separate frame',
    'stacked floors without observed connections remain unavailable',
    'hidden layers preserve all walking obstacles',
    'camera corridors without observed floor support cannot enable walking',
]
SUPPORT_VARIANTS = ['missing floor', 'floor points only', 'unclassified surface', 'planned floor', 'documentary floor']


def require(value, message):
    if not value:
        raise InvalidNavigation(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def support_height(front):
    # Evaluate the declared sixteen separate horizontal treads, independently
    # of Swift's floor picker and controller. Ground/landing extend the route.
    if front < 4:
        return 0.0
    if front >= 10.4:
        return 3.2
    for index in range(16):
        if front < 4 + (index+1)*0.4:
            return (index+1)*0.2
    raise InvalidNavigation('No declared stair support')


def read_report(report):
    require(report.get('version') == 2 and report.get('profile') == 'analytic-connected-walk-v2', 'Unknown fixture profile')
    require(report.get('passed') is True and report.get('sourceGeometryUnchanged') is True, 'Native movement or source preservation failed')
    for key in ('physicalQualification', 'reconstructionQualified', 'protectedBenchmark'):
        require(report.get(key) is False, 'Analytic evidence cannot grant qualification')
    for key, expected in dict(rooms=9, levels=2, routeSpaces=7, doorways=4, stairTreads=16, horizontalRouteLengthMetres=56.8).items():
        require(report.get(key) == expected, 'Fixture inventory changed: '+key)
    cases = report.get('cases', [])
    require(len(cases) == 9 and [c.get('name') for c in cases] == NAMES, 'Missing or reordered topology cases')
    require(all(c.get('passed') is True for c in cases), 'A required topology case failed')
    trace = report.get('trace', [])
    require(len(trace) == 284, 'Incomplete forward/backward route')
    worst = 0.0
    previous_x = -7.0
    for index, point in enumerate(trace):
        require(all(number(point.get(k)) for k in ('x', 'y', 'z', 'requestedX')), 'Invalid trace coordinate')
        direction = 1 if index < 142 else -1
        expected_x = -7 + (index+1)*0.2 if index < 142 else 21.4-(index-141)*0.2
        lower = 1.6+support_height(point['x']+0.2-0.0001)
        upper = 1.6+support_height(point['x']+0.2+0.0001)
        error = max(abs(point['x']-expected_x), abs(point['requestedX']-(previous_x+direction*0.2)),
                    abs(point['y']-2), max(0, lower-point['z'], point['z']-upper))
        require(error <= 0.0001, 'Native trace left the declared route/floor at step '+str(index))
        worst = max(worst, error)
        previous_x = point['x']
    require(cases[0].get('attemptedSteps') == 284 and cases[0].get('completedSteps') == 284, 'Native route counter differs')
    require(number(cases[0].get('maximumPositionErrorMetres')) and 0 <= cases[0]['maximumPositionErrorMetres'] < 0.0001, 'Native route error exceeds tolerance')
    for case, start, limit in zip(cases[1:5], (-1.4, 5.6, 4.6, -2), (-0.25, 6.6, 5.8, -0.2)):
        require(type(case.get('movedSteps')) is int and type(case.get('refusedSteps')) is int and
                0 < case['movedSteps'] < 16 and case['movedSteps']+case['refusedSteps'] == 16, 'Refusal must follow useful movement')
        require(case.get('maximumAllowedX') == limit and number(case.get('finalX')) and case['finalX'] <= limit, 'Refused route crossed its declared barrier')
        positions = case.get('positions', [])
        require(case.get('startX') == start and len(positions) == 16, 'Missing refusal trace')
        previous = start
        moved = 0
        for point in positions:
            require(all(number(point.get(k)) for k in ('x', 'y', 'z')), 'Invalid refusal trace')
            delta = point['x']-previous
            require(-0.00001 <= delta <= 0.2001 and abs(point['y']-2) < 0.0001 and point['x'] <= limit, 'Refusal trace crossed an obstacle or teleported')
            if delta > 0.00001:
                require(abs(delta-0.2) < 0.0001, 'Unexpected step length')
                moved += 1
            previous = point['x']
        require(moved == case['movedSteps'] and abs(previous-case['finalX']) < 0.00001, 'Refusal counters differ from trace')
    require(type(cases[5].get('visibleFeatures')) is int and cases[5]['visibleFeatures'] > 0 and
            type(cases[5].get('cameraPositions')) is int and cases[5]['cameraPositions'] > 0, 'Separate frame was not exercised')
    variants = cases[8].get('variants', [])
    require([v.get('variant') for v in variants] == SUPPORT_VARIANTS, 'Missing unsupported-floor variants')
    for variant in variants:
        require(variant.get('cameraPositions') == 149, 'Recorded camera corridor was not retained')
        for key in ('passed', 'initialFreeFly', 'returnToWalkRefused', 'globalAndIndexedSupportRefused',
                    'sourceGeometryUnchanged', 'restoredWalkEnabled'):
            require(variant.get(key) is True, 'Floor support or explicit Free fly failed: '+key)
        for key, expected_x in [('start', -7), ('afterRefusedWalk', -7), ('afterFreeFly', -6.8), ('afterRestoredWalk', -6.8)]:
            position = variant.get(key, {})
            require(all(number(position.get(axis)) for axis in ('x', 'y', 'z')), 'Invalid unsupported-floor trace')
            require(max(abs(position['x']-expected_x), abs(position['y']-2), abs(position['z']-1.6)) < 0.0001,
                    'Unsupported movement or working fallback differs: '+key)
    return dict(passed=True, reader='Independent Python connected-walk trace scorer', profile=report['profile'],
                cases=len(cases), unsupportedFloorVariants=len(variants), tracedSteps=len(trace), horizontalRouteMetres=56.8, maximumCoordinateErrorMetres=worst,
                physicalQualification=False, reconstructionQualified=False, protectedBenchmark=False,
                limitations='Analytic native-controller topology only; not reconstructed-house, field or sustained rendering qualification.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    require(args.input.stat().st_size <= 2_000_000, 'Report exceeds bounded trace size')
    result = read_report(json.loads(args.input.read_text()))
    data = json.dumps(result, indent=2, allow_nan=False)+'\n'
    if args.output:
        require(args.output.resolve() != args.input.resolve(), 'Output must preserve native evidence')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(data)
    print(data, end='')


if __name__ == '__main__':
    main()
