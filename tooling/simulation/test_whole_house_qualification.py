"""A malformed/missing house, seed split or metric must never yield a pass."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import whole_house_qualification as qualification


def inventory():
    shards=[dict(schema=1,source='a'*40,candidateSHA256='b'*64,shard=i,cases=[]) for i in range(14)]
    for i in range(70):
        split='development' if i<50 else 'protected'
        for stage in ['rough','finished']:
            shards[i%14]['cases'].append(dict(case=f'{split}-{i:02d}',split=split,stage=stage,topologySignature=hashlib.sha256(str(i).encode()).hexdigest(),rooms=7,levels=2,
                positiveQueries=28,negativeQueries=56,positiveAccepted=28,criticalFalseAccepts=0,executedQueries=84,positionErrorsMetres=[.004]*28,
                oracleReadDenied=True,queryLabelsExcluded=True,mapCount=7,expectedMapCount=7,optimizedCameraCount=56,maximumSourcePositionErrorMetres=.003,passed=True))
    return shards


class QualificationIntegrity(unittest.TestCase):
    def aggregate(self,shards):
        with tempfile.TemporaryDirectory() as temporary,contextlib.redirect_stdout(io.StringIO()),patch.object(qualification,'cluster_intervals',return_value={'testOnly':True}):
            folder=Path(temporary)
            for i,s in enumerate(shards):(folder/f'shard-{i}.json').write_text(json.dumps(s))
            passed=qualification.aggregate(folder)
            return passed,json.loads((folder/'summary.json').read_text())

    def test_complete_inventory_preserves_all_house_and_query_counts(self):
        passed,r=self.aggregate(inventory())
        self.assertTrue(passed);self.assertTrue(r['complete']);self.assertEqual(r['houses'],70)
        self.assertEqual(r['positiveQueries'],3920);self.assertEqual(r['criticalQueries'],7840)
        self.assertEqual(r['protected']['houses'],20);self.assertEqual(r['development']['houses'],50)
        self.assertFalse(r['productionQualified'])

    def test_missing_duplicate_and_changed_candidate_are_not_complete(self):
        original=inventory();variants=[]
        variants.append(original[:-1])
        bad=copy.deepcopy(original);bad[0]['cases'][1]=bad[0]['cases'][0];variants.append(bad)
        bad=copy.deepcopy(original);bad[-1]['candidateSHA256']='c'*64;variants.append(bad)
        bad=copy.deepcopy(original);bad[-1]['shard']=14;variants.append(bad)
        bad=copy.deepcopy(original);bad[0]['cases'].pop();variants.append(bad)
        for bad in variants:
            passed,r=self.aggregate(bad);self.assertFalse(passed);self.assertFalse(r['complete'])

    def test_pass_flag_cannot_hide_failed_accuracy_or_missing_errors(self):
        for key,value in [('positionErrorsMetres',[.04]*28),('positionErrorsMetres',[.004]*27),('positionErrorsMetres',[float('nan')]*28),
            ('criticalFalseAccepts',1),('oracleReadDenied',False),('queryLabelsExcluded',False),('mapCount',6),('maximumSourcePositionErrorMetres',.02),('positiveAccepted',29),('positiveAccepted',True)]:
            bad=inventory();bad[0]['cases'][0][key]=value
            passed,r=self.aggregate(bad);self.assertFalse(passed);self.assertGreater(r['reportIntegrityFailures'],0)

    def test_relabelled_split_or_changed_stage_topology_is_rejected(self):
        for key,value in [('split','protected'),('topologySignature','c'*64),('stage','planned'),('case','protected-70')]:
            bad=inventory();bad[0]['cases'][0][key]=value
            passed,r=self.aggregate(bad);self.assertFalse(passed);self.assertFalse(r['complete'])

    def test_failure_is_retained_without_changing_declared_denominators(self):
        bad=inventory();bad[0]['cases'][0].update(passed=False,positiveAccepted=20,positionErrorsMetres=[.004]*20)
        passed,r=self.aggregate(bad)
        self.assertFalse(passed);self.assertTrue(r['complete']);self.assertEqual(r['positiveQueries'],3920)
        self.assertEqual(r['failedStageCases'],1);self.assertEqual(r['positiveAccepted'],3912)

    def test_cluster_bootstrap_resamples_whole_paired_houses(self):
        cases=inventory()[0]['cases'][:4]
        result=qualification.cluster_intervals(cases,100)
        self.assertEqual(result['availability'],[1.,1.]);self.assertEqual(result['p95Metres'],[.004,.004])

if __name__=='__main__':unittest.main()
