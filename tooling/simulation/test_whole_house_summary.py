import json
from pathlib import Path
import tempfile
import unittest
from summarize_whole_house import summarize,COUNTS,SCALARS


class AggregatePublication(unittest.TestCase):
    def test_nested_source_payload_cannot_escape_the_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);sentinel='PRIVATE-POSE-IMAGE-OR-SEED'
            for stage in ['rough','finished']:
                report=dict(passed=True,oracleReadDenied=True,queryLabelsExcluded=True,queries=[sentinel],optimizedCameras={sentinel:[1,2,3]},geometry=sentinel,**{k:1 for k in COUNTS+SCALARS})
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

if __name__=='__main__':unittest.main()
