#!/usr/bin/env python3
"""Score native walking against its retained reconstructed floor triangles."""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path


class InvalidNavigation(ValueError):
    pass


def require(value, message):
    if not value:
        raise InvalidNavigation(message)


def point(value):
    require(isinstance(value, dict), 'Missing position')
    require(all(type(value.get(k)) in (int, float) and math.isfinite(value[k]) for k in ('x', 'y', 'z')), 'Invalid position')
    return tuple(value[k] for k in ('x', 'y', 'z'))


class Surface:
    def __init__(self, house, expected_vertices):
        require(house.get('isDemo') is True, 'Analytic fixture lost its explicit status')
        features = house.get('features', [])
        require(len(features) == 1, 'Navigation must receive only the reconstructed surface')
        feature = features[0]
        require(feature.get('geometrySource') == 'depthFusion' and feature.get('trade') == 'Floor' and
                feature.get('kind') == 'synthetic', 'Missing explicit reconstructed floor classification')
        observations = house.get('observations', [])
        require(len(observations) == 9 and len({o['id'] for o in observations}) == 9, 'Incomplete capture inputs')
        require(sorted(feature.get('sourceIDs', [])) == sorted(o['id'] for o in observations), 'Reconstruction source links differ')
        require(re.fullmatch('[0-9a-f]{64}', feature.get('sourceFingerprint', '')), 'Missing reconstruction input fingerprint')
        vertices = [point(v) for v in feature.get('mesh', {}).get('vertices', [])]
        indices = feature.get('mesh', {}).get('triangles', [])
        require(len(vertices) == expected_vertices and 3 <= len(vertices) < 400000, 'Unexpected reconstructed vertex inventory')
        require(0 < len(indices) <= 1200000 and len(indices) % 3 == 0, 'Invalid reconstructed faces')
        require(all(type(i) is int and 0 <= i < len(vertices) for i in indices), 'Face references absent vertex')
        require(all(abs(x) <= .81 and abs(y) <= .61 and abs(z) < .003 for x, y, z in vertices), 'Output left the bounded capture fragment')
        self.bins = {}
        self.triangles = []
        for offset in range(0, len(indices), 3):
            triangle = [vertices[i] for i in indices[offset:offset+3]]
            self.triangles.append(triangle)
            xs, ys = [p[0] for p in triangle], [p[1] for p in triangle]
            for x in range(math.floor((min(xs)-1e-8)*10), math.floor((max(xs)+1e-8)*10)+1):
                for y in range(math.floor((min(ys)-1e-8)*10), math.floor((max(ys)+1e-8)*10)+1):
                    self.bins.setdefault((x, y), []).append(triangle)

    def supports(self, x, y):
        for a, b, c in self.bins.get((math.floor(x*10), math.floor(y*10)), []):
            denominator = (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
            if abs(denominator) <= 1e-10:
                continue
            u = ((x-a[0])*(c[1]-a[1])-(y-a[1])*(c[0]-a[0]))/denominator
            v = ((b[0]-a[0])*(y-a[1])-(b[1]-a[1])*(x-a[0]))/denominator
            if u >= -1e-8 and v >= -1e-8 and u+v <= 1+1e-8:
                return True
        return False

    def footprint(self, x, y):
        return all(self.supports(x+dx, y+dy) for dx in (-.2, 0, .2) for dy in (-.2, 0, .2))


def read_report(report, package_bytes):
    require(report.get('version') == 1 and report.get('profile') == 'analytic-reconstructed-floor-v1', 'Unknown reconstruction navigation fixture')
    require(hashlib.sha256(package_bytes).hexdigest() == report.get('privatePackageSHA256'), 'Private source package hash differs')
    for key in ('passed', 'unclassifiedRefused', 'classifiedWalkEnabled', 'gapStartWalkEnabled', 'landedWalkEnabled', 'sourceGeometryUnchanged'):
        require(report.get(key) is True, 'Native reconstruction navigation failed: '+key)
    for key in ('wholeHouseQualified', 'physicalQualification', 'protectedBenchmark'):
        require(report.get(key) is False, 'Bounded analytic evidence cannot grant broader qualification')
    require(report.get('generatorMeshesSupplied') == 0 and report.get('capturedViewsPerFragment') == 9, 'Candidate input contract changed')
    package = json.loads(package_bytes)
    require(package.get('version') == 1, 'Unknown private package schema')
    flat = Surface(package['flat'], report.get('flatVertices'))
    gap = Surface(package['gap'], report.get('gapVertices'))
    trace = report.get('trace', [])
    require(len(trace) == 8 and report.get('completedSteps') == 8, 'Incomplete reconstructed-floor walk')
    previous = -.4
    for index, entry in enumerate(trace):
        x, y, z = point(entry)
        target = -.4+(index+1)*.2 if index < 4 else .4-(index-3)*.2
        require(abs(x-target) < .0001 and abs(y) < .0001 and abs(z-2) < .003, 'Walk left the expected captured corridor')
        # Score intervening body footprints against actual output triangles,
        # independently of Swift's swept-floor implementation and success flag.
        require(all(flat.footprint(previous+(x-previous)*step/4, y) for step in range(5)), 'Walk crosses unsupported reconstructed surface')
        previous = x
    require(gap.footprint(-.4, 0) and gap.footprint(.4, 0), 'Gap fixture has no supported starting/landing floor')
    require(not gap.supports(0, 0) and not gap.footprint(-.2, 0), 'Missing depth became a supported bridge')
    require(all(max(p[0] for p in t) < -.09 or min(p[0] for p in t) > .09 for t in gap.triangles), 'A reconstructed face bridges missing depth')
    gap_trace = report.get('gapTrace', [])
    require(len(gap_trace) == 3, 'Missing repeated refusal trace')
    for entry in gap_trace:
        x, y, z = point(entry)
        require(abs(x+.4) < .0001 and abs(y) < .0001 and abs(z-2) < .003, 'Walking crossed the reconstructed gap')
    x, y, z = point(report.get('afterExplicitFreeFly'))
    require(abs(x-.4) < .0001 and abs(y) < .0001 and abs(z-2) < .0001, 'Explicit inspection movement did not reach the supported landing')
    return dict(passed=True, reader='Independent reconstructed triangle and native movement scorer',
                profile=report['profile'], privatePackageSHA256=report['privatePackageSHA256'],
                flatVertices=report['flatVertices'], gapVertices=report['gapVertices'], tracedSteps=8,
                refusedSteps=3, unclassifiedRefused=True, explicitFreeFlyAndReturnVerified=True,
                rawSourceRecordsPublished=False, wholeHouseQualified=False, physicalQualification=False,
                limitations='Bounded synthetic reconstructed floor only; no whole-house, automatic floor recognition or physical acceptance.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('package', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    require(args.report.stat().st_size < 100000 and args.package.stat().st_size < 32000000, 'Input exceeds fixture bounds')
    require(args.output.resolve() not in (args.report.resolve(), args.package.resolve()), 'Output must preserve native evidence')
    result = read_report(json.loads(args.report.read_text()), args.package.read_bytes())
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
