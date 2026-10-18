import json
from pathlib import Path
import tempfile
import unittest
from run import aggregate
from prepare import prepare


class FixedSamplingAudit(unittest.TestCase):
    def report(self):
        return dict(passed=True,positiveQueries=20,positiveAccepted=20,negativeQueries=20,falseAccepts=0,expectedMapCount=4,mapCount=4,mapViews=24,optimizedCameraCount=24,
            p95Metres=.009,worstAcceptedPositionErrorMetres=.012,maximumOptimizedCameraPositionErrorMetres=.004,oracleReadDenied=True,queryLabelsExcluded=True,queries=[{} for _ in range(40)])

    def test_complete_positive_control_and_original_denominators(self):
        report=self.report();self.assertTrue(aggregate(report,'finished',384,0)['passed'])
        report['queries'].pop();self.assertFalse(aggregate(report,'finished',384,0)['complete'])
        report=self.report();report['positiveQueries']=19;self.assertFalse(aggregate(report,'finished',384,0)['passed'])

    def test_forged_pass_cannot_override_accuracy_availability_or_rejection(self):
        for key,value in [('p95Metres',.011),('worstAcceptedPositionErrorMetres',.026),('positiveAccepted',17),('falseAccepts',1),('mapCount',3),('maximumOptimizedCameraPositionErrorMetres',.015),('oracleReadDenied',False),('queryLabelsExcluded',False)]:
            report=self.report();report[key]=value;self.assertFalse(aggregate(report,'finished',384,0)['passed'])
        self.assertFalse(aggregate(self.report(),'finished',384,1)['passed'])

    def test_private_payload_and_nonfinite_metrics_never_escape(self):
        report=self.report();sentinel='PRIVATE-SOURCE-POSE-ORACLE'
        report['queries']=[dict(source=sentinel) for _ in range(40)];report['geometry']=sentinel;report['p95Metres']=float('nan')
        result=aggregate(report,'finished',384,0);self.assertFalse(result['passed']);self.assertNotIn(sentinel,json.dumps(result,allow_nan=False))
        self.assertIsNone(result['p95Metres'])

    def test_complete_refusal_is_not_a_nominal_pass(self):
        report=self.report();report.update(passed=False,positiveAccepted=0,mapCount=0,optimizedCameraCount=0,p95Metres=None,maximumOptimizedCameraPositionErrorMetres=float('inf'))
        result=aggregate(report,'finished',384,1);self.assertTrue(result['complete']);self.assertFalse(result['passed'])
        json.dumps(result,allow_nan=False)

    def test_patch_is_bounded_and_leaves_production_source_untouched(self):
        original=Path('packages/visual-core/hx_vision.cpp');before=original.read_bytes()
        with tempfile.TemporaryDirectory() as folder:
            variant=Path(folder)/'candidate.cpp';variant.write_bytes(before);prepare(variant)
            result=variant.read_text();self.assertIn('std::min(2.0,1280.0/std::max(w,h))',result)
            self.assertIn('scale>1.0 ? cv::INTER_CUBIC:cv::INTER_AREA',result)
            with self.assertRaises(ValueError):prepare(variant)
        self.assertEqual(original.read_bytes(),before)


if __name__=='__main__':unittest.main()
