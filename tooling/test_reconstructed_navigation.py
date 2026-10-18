import hashlib
import json
import unittest
from check_reconstructed_navigation import read_report, InvalidNavigation


def fixture():
    def house(gap):
        vertices, indices = [], []
        for low, high in ([(-.75, -.13), (.13, .75)] if gap else [(-.75, .75)]):
            offset = len(vertices)
            vertices.extend(dict(x=x, y=y, z=0) for x, y in [(low, -.55), (high, -.55), (high, .55), (low, .55)])
            indices.extend(offset+i for i in (0, 1, 2, 0, 2, 3))
        return dict(isDemo=True, observations=[dict(id=str(i)) for i in range(9)],
            features=[dict(geometrySource='depthFusion', trade='Floor', kind='synthetic',
                sourceIDs=[str(i) for i in range(9)], sourceFingerprint='a'*64,
                mesh=dict(vertices=vertices, triangles=indices))])
    package=dict(version=1, flat=house(False), gap=house(True))
    report=dict(version=1, profile='analytic-reconstructed-floor-v1', passed=True,
        unclassifiedRefused=True, classifiedWalkEnabled=True, gapStartWalkEnabled=True,
        landedWalkEnabled=True, sourceGeometryUnchanged=True, wholeHouseQualified=False,
        physicalQualification=False, protectedBenchmark=False, generatorMeshesSupplied=0,
        capturedViewsPerFragment=9, flatVertices=4, gapVertices=8, completedSteps=8,
        trace=[dict(x=x,y=0,z=2) for x in (-.2,0,.2,.4,.2,0,-.2,-.4)],
        gapTrace=[dict(x=-.4,y=0,z=2) for _ in range(3)], afterExplicitFreeFly=dict(x=.4,y=0,z=2))
    return report, package


def encode(report, package):
    data=json.dumps(package).encode()
    report['privatePackageSHA256']=hashlib.sha256(data).hexdigest()
    return data


class ReconstructedNavigationReader(unittest.TestCase):
    def test_scores_native_trace_against_retained_output_triangles(self):
        report, package=fixture();result=read_report(report, encode(report, package))
        self.assertEqual(result['tracedSteps'],8)
        self.assertEqual(result['refusedSteps'],3)
        self.assertFalse(result['wholeHouseQualified'])
        self.assertFalse(result['physicalQualification'])

    def test_refuses_unsupported_walk_bridged_gap_and_lost_provenance(self):
        for fault in range(5):
            report, package=fixture()
            if fault==0:report['gapTrace'][1]['x']=-.2
            if fault==1:package['flat']['features'][0]['mesh']=package['gap']['features'][0]['mesh'];report['flatVertices']=8
            if fault==2:package['gap']['features'][0]['mesh']=package['flat']['features'][0]['mesh'];report['gapVertices']=4
            if fault==3:package['flat']['features'][0]['sourceIDs'].pop()
            if fault==4:package['flat']['features'][0]['geometrySource']='capturedMesh'
            with self.subTest(fault=fault), self.assertRaises(InvalidNavigation):read_report(report, encode(report, package))

    def test_refuses_changed_package_false_fallback_and_qualification(self):
        report, package=fixture();data=encode(report, package)+b' '
        with self.assertRaises(InvalidNavigation):read_report(report,data)
        for key in ('unclassifiedRefused', 'classifiedWalkEnabled', 'landedWalkEnabled', 'sourceGeometryUnchanged', 'wholeHouseQualified'):
            report, package=fixture();report[key]=not report[key]
            with self.subTest(key=key), self.assertRaises(InvalidNavigation):read_report(report,encode(report,package))


if __name__ == '__main__':
    unittest.main()
