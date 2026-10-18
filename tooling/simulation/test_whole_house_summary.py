import json
from pathlib import Path
import tempfile
import unittest
from summarize_whole_house import summarize,COUNTS,SCALARS,failure_categories


class AggregatePublication(unittest.TestCase):
    def test_failure_categories_never_publish_source_names_or_exception_text(self):
        result=failure_categories({'PRIVATE-UUID':'Pose graph rejected PRIVATE-POSE','ANOTHER-SOURCE':'PRIVATE-PATH'})
        self.assertEqual(result,{'pose-consistency':1,'unclassified':1})
        self.assertNotIn('PRIVATE',json.dumps(result))

    def test_nested_source_payload_cannot_escape_the_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);sentinel='PRIVATE-POSE-IMAGE-OR-SEED'
            for stage in ['rough','finished']:
                report=dict(passed=True,oracleReadDenied=True,queryLabelsExcluded=True,queries=[sentinel,sentinel],optimizedCameras={sentinel:[1,2,3]},geometry=sentinel,**{k:1 for k in COUNTS+SCALARS})
                report['rotationErrorDegrees']=dict(count=1,p50=.1,p95=.2,maximum=.3,private=sentinel)
                report['visibleSurfaceOverlay']=dict(samples=48,scoredAcceptedQueries=1,behindCamera=0,worldMetres={'count':48,'p50':.001,'p95':.002,'maximum':.003,'private':sentinel},private=sentinel)
                for suffix,data in [('replay',report),('generator',dict(rooms=4,levels=1,width=384,seed=sentinel)),('bundle-check',dict(passed=True,private=sentinel))]:
                    (root/f'{stage}-{suffix}.json').write_text(json.dumps(data))
            result=summarize(root);self.assertTrue(result['passed']);self.assertNotIn(sentinel,json.dumps(result));self.assertFalse(result['rawEvidencePublished'])

    def test_incomplete_and_nonfinite_results_cannot_publish_a_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);result=summarize(root);self.assertFalse(result['passed']);self.assertFalse(result['complete']);self.assertEqual(len(result['cases']),2)
            for stage in ['rough','finished']:
                report=dict(passed=True,**{k:1 for k in COUNTS+SCALARS});report['p95Metres']=float('nan')
                for suffix,data in [('replay',report),('generator',dict(rooms=4,levels=1,width=384)),('bundle-check',dict(passed=True))]:
                    (root/f'{stage}-{suffix}.json').write_text(json.dumps(data))
            result=summarize(root);self.assertFalse(result['passed']);self.assertFalse(result['complete'])
            self.assertNotIn('NaN',json.dumps(result,allow_nan=False))

    def test_complete_refusal_retains_denominators_and_null_error_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for stage in ['rough','finished']:
                report=dict(passed=False,positiveQueries=16,negativeQueries=32,positiveAccepted=0,falseAccepts=0,mapCount=0,expectedMapCount=4,mapViews=0,optimizedCameraCount=0,
                    p95Metres=None,worstAcceptedPositionErrorMetres=0,maximumOptimizedCameraPositionErrorMetres=float('inf'),queries=[dict(accepted=False)]*48)
                for suffix,data in [('replay',report),('generator',dict(rooms=4,levels=1,width=768)),('bundle-check',dict(passed=True))]:
                    (root/f'{stage}-{suffix}.json').write_text(json.dumps(data))
            result=summarize(root);self.assertTrue(result['complete']);self.assertFalse(result['passed'])
            self.assertEqual(result['cases'][0]['positiveQueries'],16);self.assertIsNone(result['cases'][0]['p95Metres'])
            json.dumps(result,allow_nan=False)

if __name__=='__main__':unittest.main()
