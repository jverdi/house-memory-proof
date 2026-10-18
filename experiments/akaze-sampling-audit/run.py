"""Retain complete, finite aggregate outcomes for one isolated detector variant."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

COUNTS=['positiveQueries','positiveAccepted','negativeQueries','falseAccepts','expectedMapCount','mapCount','mapViews','optimizedCameraCount']
SCALARS=['p95Metres','worstAcceptedPositionErrorMetres','maximumOptimizedCameraPositionErrorMetres']


def aggregate(report,stage,width,exit_code):
    expected_positive,expected_negative=(12,8) if stage=='rough' else (20,20)
    case=dict(stage=stage,width=width,passed=False,complete=False)
    for key in COUNTS:
        value=report.get(key);case[key]=value if type(value) is int and value>=0 else None
    for key in SCALARS:
        value=report.get(key);case[key]=value if type(value) in [int,float] and math.isfinite(value) and value>=0 else None
    for key in ['oracleReadDenied','queryLabelsExcluded']:case[key]=report.get(key) is True
    case['complete']=(all(case[k] is not None for k in COUNTS) and case['positiveQueries']==expected_positive and case['negativeQueries']==expected_negative
        and isinstance(report.get('queries'),list) and len(report['queries'])==expected_positive+expected_negative
        and case['positiveAccepted']<=expected_positive and case['falseAccepts']<=expected_negative
        and case['expectedMapCount']==4)
    if case['complete'] and all(case[k] is not None for k in SCALARS):
        case['passed']=(exit_code==0 and report.get('passed') is True and case['oracleReadDenied'] and case['queryLabelsExcluded']
            and case['mapCount']==4 and case['positiveAccepted']/expected_positive>=.9 and case['falseAccepts']==0
            and case['p95Metres']<=.010 and case['worstAcceptedPositionErrorMetres']<=.025
            and case['optimizedCameraCount']>=3 and case['maximumOptimizedCameraPositionErrorMetres']<.015)
    return case


def main():
    p=argparse.ArgumentParser();p.add_argument('--seed',type=int,required=True);a=p.parse_args()
    output=Path('build/sampling-audit-reports');output.mkdir(parents=True,exist_ok=True)
    cases=[]
    for name,width,flags in [('rough',384,[]),('finished',384,['--paired','--staggered','--finished-capture']),('finished',768,['--paired','--staggered','--finished-capture'])]:
        fixture=Path(f'build/sampling-audit-private/{name}-{width}');result=fixture.parent/(fixture.name+'.json')
        case=dict(stage=name,width=width,passed=False,complete=False)
        try:
            subprocess.run([sys.executable,'tooling/simulation/house_layout_fixture.py',str(fixture),'--seed',str(a.seed),'--width',str(width),*flags],check=True,timeout=600,stdout=subprocess.DEVNULL)
            replay=subprocess.run([sys.executable,'tooling/simulation/replay_fixture.py','--executable','build/vision-replay','--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=660)
            case=aggregate(json.loads(result.read_text()),name,width,replay.returncode)
        except Exception as error:case['errorClass']=type(error).__name__
        cases.append(case)
        summary=dict(source=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256(Path('build/vision-replay').read_bytes()).hexdigest(),variant='fixed-2x-cubic-akaze-analysis',repairIteration=5,cases=cases,
            complete=len(cases)==3 and all(c['complete'] for c in cases),passed=len(cases)==3 and all(c['passed'] for c in cases),physicalQualification=False,
            limitations=['Development-only detector variant, not adopted into the app','Original failures are retained; unchanged availability, accuracy and ambiguity gates','Raw source evidence and oracle remain ephemeral in CI'])
        (output/'summary.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n');print(json.dumps(case,allow_nan=False),flush=True)
    return 0 if summary['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
