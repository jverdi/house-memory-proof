import copy
import unittest
from check_navigation_benchmark import read_report, InvalidNavigation, NAMES


def fixture():
    trace = []
    # Enumerate tread intervals rather than using the reader's support helper.
    for index in range(284):
        x = -7+(index+1)*0.2 if index < 142 else 21.4-(index-141)*0.2
        heights = [0.0] + [step*0.2 for step in range(1,17) if x+0.2 >= 4+(step-1)*0.4]
        trace.append(dict(x=x, y=2.0, z=1.6+max(heights), requestedX=x))
    cases = [dict(name=name, passed=True) for name in NAMES]
    cases[0].update(attemptedSteps=284, completedSteps=284, maximumPositionErrorMetres=0.0)
    for case, limit in zip(cases[1:5], (-0.25, 6.6, 5.8, -0.2)):
        case.update(movedSteps=3, refusedSteps=13, finalX=limit-0.1, maximumAllowedX=limit)
    cases[5].update(visibleFeatures=4, cameraPositions=20)
    return dict(version=1, profile='analytic-connected-walk-v1', passed=True, sourceGeometryUnchanged=True,
                rooms=9, levels=2, routeSpaces=7, doorways=4, stairTreads=16, routeLengthMetres=56.8,
                cases=cases, trace=trace, physicalQualification=False, reconstructionQualified=False, protectedBenchmark=False)


class NavigationTraceReader(unittest.TestCase):
    def test_complete_trace_has_no_physical_or_reconstruction_claim(self):
        report=read_report(fixture())
        self.assertEqual(report['tracedSteps'],284)
        self.assertEqual(report['cases'],8)
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

    def test_qualification_or_changed_source_refused(self):
        for field,value in [('physicalQualification',True),('reconstructionQualified',True),('sourceGeometryUnchanged',False),('passed',False)]:
            report=fixture();report[field]=value
            with self.subTest(field=field),self.assertRaises(InvalidNavigation):read_report(report)


if __name__ == '__main__':
    unittest.main()
