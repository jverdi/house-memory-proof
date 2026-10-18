import unittest
from check_navigation_benchmark import read_report, InvalidNavigation, NAMES, SUPPORT_VARIANTS


def fixture():
    trace = []
    # Enumerate tread intervals rather than using the reader's support helper.
    for index in range(284):
        x = -7+(index+1)*0.2 if index < 142 else 21.4-(index-141)*0.2
        heights = [0.0] + [step*0.2 for step in range(1,17) if x+0.2 >= 4+(step-1)*0.4]
        trace.append(dict(x=x, y=2.0, z=1.6+max(heights), requestedX=x))
    cases = [dict(name=name, passed=True) for name in NAMES]
    cases[0].update(attemptedSteps=284, completedSteps=284, maximumPositionErrorMetres=0.0)
    for case, start, limit in zip(cases[1:5], (-1.4, 5.6, 4.6, -2), (-0.25, 6.6, 5.8, -0.2)):
        positions=[dict(x=start+min(index+1,3)*0.2,y=2,z=1.6) for index in range(16)]
        case.update(movedSteps=3, refusedSteps=13, startX=start,positions=positions,finalX=start+0.6, maximumAllowedX=limit)
    cases[5].update(visibleFeatures=4, cameraPositions=20)
    cases[8]['variants'] = [dict(variant=name, passed=True, cameraPositions=149, initialFreeFly=True,
        returnToWalkRefused=True, globalAndIndexedSupportRefused=True, sourceGeometryUnchanged=True,
        restoredWalkEnabled=True, start=dict(x=-7,y=2,z=1.6), afterRefusedWalk=dict(x=-7,y=2,z=1.6),
        afterFreeFly=dict(x=-6.8,y=2,z=1.6), afterRestoredWalk=dict(x=-6.8,y=2,z=1.6)) for name in SUPPORT_VARIANTS]
    return dict(version=2, profile='analytic-connected-walk-v2', passed=True, sourceGeometryUnchanged=True,
                rooms=9, levels=2, routeSpaces=7, doorways=4, stairTreads=16, horizontalRouteLengthMetres=56.8,
                cases=cases, trace=trace, physicalQualification=False, reconstructionQualified=False, protectedBenchmark=False)


class NavigationTraceReader(unittest.TestCase):
    def test_complete_trace_has_no_physical_or_reconstruction_claim(self):
        report=read_report(fixture())
        self.assertEqual(report['tracedSteps'],284)
        self.assertEqual(report['cases'],9)
        self.assertEqual(report['unsupportedFloorVariants'],5)
        self.assertFalse(report['physicalQualification'])
        self.assertFalse(report['reconstructionQualified'])

    def test_wrong_floor_skipped_step_and_nonfinite_trace_refused(self):
        for index, key, delta in [(10,'z',3.2),(100,'x',0.2),(150,'requestedX',-0.2),(20,'y',float('nan'))]:
            report=fixture();report['trace'][index][key]+=delta
            with self.subTest(index=index),self.assertRaises(InvalidNavigation):read_report(report)
        report=fixture();report['trace'].pop()
        with self.assertRaises(InvalidNavigation):read_report(report)

    def test_false_refusal_success_and_incomplete_inventory_refused(self):
        for field,value in [('finalX',0.1),('refusedSteps',0),('movedSteps',0),('maximumAllowedX',1)]:
            report=fixture();report['cases'][1][field]=value
            with self.subTest(field=field),self.assertRaises(InvalidNavigation):read_report(report)
        report=fixture();report['cases'].pop()
        with self.assertRaises(InvalidNavigation):read_report(report)
        report=fixture();report['cases'][1]['positions'][5]['x']=0.1
        with self.assertRaises(InvalidNavigation):read_report(report)

    def test_qualification_or_changed_source_refused(self):
        for field,value in [('physicalQualification',True),('reconstructionQualified',True),('sourceGeometryUnchanged',False),('passed',False)]:
            report=fixture();report[field]=value
            with self.subTest(field=field),self.assertRaises(InvalidNavigation):read_report(report)

    def test_missing_floor_walk_and_broken_free_fly_or_restoration_refused(self):
        for index in range(5):
            for field in ('afterRefusedWalk', 'afterFreeFly', 'afterRestoredWalk'):
                report=fixture();report['cases'][8]['variants'][index][field]['x']+=0.2
                with self.subTest(index=index,field=field),self.assertRaises(InvalidNavigation):read_report(report)
            for field in ('initialFreeFly', 'returnToWalkRefused', 'globalAndIndexedSupportRefused', 'sourceGeometryUnchanged', 'restoredWalkEnabled'):
                report=fixture();report['cases'][8]['variants'][index][field]=False
                with self.subTest(index=index,field=field),self.assertRaises(InvalidNavigation):read_report(report)
        report=fixture();report['cases'][8]['variants'].pop()
        with self.assertRaises(InvalidNavigation):read_report(report)
        report=fixture();report['cases'][8]['variants'][0]['cameraPositions']=0
        with self.assertRaises(InvalidNavigation):read_report(report)


if __name__ == '__main__':
    unittest.main()
