#!/usr/bin/env python3
"""Broader analytic stress evidence; not a substitute for full-house/field gates.

Candidate processes cannot read the evaluator oracle. Protected configurations
are drawn after the candidate binary is built. Only replay records contain their
seeds; ordinary reports contain case identifiers and aggregate failure classes.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys


def summarize(cases):
    errors = sorted(e for case in cases for e in case['positionErrorsMetres'])
    positives = sum(c['positiveQueries'] for c in cases)
    accepted = sum(c['positiveAccepted'] for c in cases)
    negatives = sum(c['negativeQueries'] for c in cases)
    ambiguous = sum(c['executedPositiveQueries'] * 2 for c in cases)
    executed_negatives = sum(c['executedNegativeQueries'] for c in cases)
    wrong = sum(c['falseAccepts'] + c['ambiguityFalseAccepts'] for c in cases)
    report = dict(cases=len(cases), positiveQueries=positives, positiveAccepted=accepted,
                  availability=accepted / max(1, positives), unrelatedNegativeQueries=negatives,
                  repeatedRoomAndFloorChallenges=ambiguous, criticalChallenges=executed_negatives + ambiguous,
                  executedUnrelatedQueries=executed_negatives,
                  criticalFalseAccepts=wrong,
                  oracleControlFailures=sum(not c['oracleReadDenied'] for c in cases),
                  p50Metres=errors[len(errors)//2] if errors else None,
                  p95Metres=errors[max(0, math.ceil(len(errors)*.95)-1)] if errors else None,
                  worstMetres=max(errors, default=None))
    report['spatialTargetsPassed'] = (report['availability'] >= .9 and wrong == 0
        and report['oracleControlFailures'] == 0 and bool(errors)
        and report['p95Metres'] <= .010 and report['worstMetres'] <= .025)
    return report


def aggregate(folder):
    inputs = [json.loads(p.read_text()) for p in sorted(folder.glob('shard-*.json'))]
    cases = [case for report in inputs for case in report['cases']]
    summary = summarize(cases)
    summary.update(sourceRevisions=sorted(set(x['sourceRevision'] for x in inputs)),
                   development=summarize([c for c in cases if c['split']=='development']),
                   protected=summarize([c for c in cases if c['split']=='protected']))
    summary['passed'] = (len(inputs)==4 and len(cases)==70 and summary['positiveQueries']>=1000
        and summary['criticalChallenges']>=3000 and summary['spatialTargetsPassed']
        and summary['development']['spatialTargetsPassed'] and summary['protected']['spatialTargetsPassed'])
    summary['productionQualified'] = False
    summary['limitations'] = ['Analytic textured corners, not 70 complete house topologies',
        'Room geometry and texture vary; no calibrated iPhone sensor model',
        'Repeated-room and floor clones test conservative abstention',
        'Thin-service geometry, camera integration and physical uncertainty are separate gates']
    (folder/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2),flush=True)
    return summary['passed']


def run(args):
    from vision_fixture import make
    report_dir=args.output;report_dir.mkdir(parents=True,exist_ok=True)
    records=report_dir.parent/('replay-records-'+str(args.shard));records.mkdir(parents=True,exist_ok=True)
    cases=[]
    for index in range(args.shard,70,4):
        split='development' if index<50 else 'protected'
        seed=int.from_bytes(hashlib.sha256(f'house-xray-development-{index}'.encode()).digest()[:4],'big') if split=='development' else secrets.randbits(32)
        positive=12 if split=='development' else 20;negative=20
        label=f'{split}-{index:02d}';fixture=report_dir.parent/('temporary-'+label)
        record=dict(case=label,seed=seed,split=split,positiveQueries=positive,negativeQueries=negative,
                    sourceRevision=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256(args.executable.read_bytes()).hexdigest(),driftMetres=.03)
        (records/(label+'.json')).write_text(json.dumps(record,indent=2)+'\n')
        try:
            make(fixture,seed,drift=.03,query_counts=(positive,negative))
            destination=fixture/'evaluation.json'
            process=subprocess.run([sys.executable,str(Path(__file__).with_name('replay_fixture.py')),
                '--executable',str(args.executable),'--fixture',str(fixture),'--output',str(destination),'--refine','--bundle'],capture_output=True,text=True,timeout=240)
            data=json.loads(destination.read_text()) if destination.exists() else {}
            queries=data.get('queries',[])
            positives=[q for q in queries if 'evaluatorPositionErrorMetres' in q]
            case=dict(case=label,split=split,positiveQueries=positive,negativeQueries=negative,
                positiveAccepted=data.get('positiveAccepted',0),falseAccepts=data.get('falseAccepts',0),
                executedPositiveQueries=min(positive,len(queries)),executedNegativeQueries=min(negative,max(0,len(queries)-positive)),
                # If nominal localization abstains, the ambiguous counterpart
                # is hidden too; nominal availability is scored separately.
                ambiguityFalseAccepts=sum(2 for q in positives if not q.get('ambiguousRoomAndFloorRejected',False)),
                oracleReadDenied=data.get('oracleReadDenied',False),
                positionErrorsMetres=[q['evaluatorPositionErrorMetres'] for q in positives],
                candidateBinarySHA256=record['candidateSHA256'],
                candidateRejected=data.get('candidateRejected',False),
                errorClass='candidate_rejected' if data.get('candidateRejected') else 'none' if process.returncode==0 else 'spatial_gate')
        except Exception as error:
            case=dict(case=label,split=split,positiveQueries=positive,negativeQueries=negative,
                positiveAccepted=0,falseAccepts=0,ambiguityFalseAccepts=0,oracleReadDenied=False,
                executedPositiveQueries=0,executedNegativeQueries=0,
                positionErrorsMetres=[],candidateBinarySHA256=record['candidateSHA256'],candidateRejected=True,errorClass=type(error).__name__)
        finally:
            shutil.rmtree(fixture,ignore_errors=True)
        cases.append(case)
        report=dict(sourceRevision=os.environ.get('GITHUB_SHA','local'),shard=args.shard,cases=cases,summary=summarize(cases),productionQualified=False)
        (report_dir/f'shard-{args.shard}.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(case=label,accepted=case['positiveAccepted'],attempts=positive,errorClass=case['errorClass'])),flush=True)
    return True  # The aggregate, not partial shards, enforces the complete gates.


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--executable',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--shard',type=int,choices=range(4));p.add_argument('--aggregate',action='store_true');args=p.parse_args()
    passed=aggregate(args.output) if args.aggregate else run(args)
    raise SystemExit(0 if passed else 1)
