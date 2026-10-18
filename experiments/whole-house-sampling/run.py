"""Compare higher image sampling on retained development layouts; gates unchanged."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

p=argparse.ArgumentParser();p.add_argument('--seed',type=int,required=True);p.add_argument('--executable',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True);private=a.output.parent/'sampling-private';cases=[]
keys=['passed','positiveQueries','positiveAccepted','negativeQueries','falseAccepts','p95Metres','worstAcceptedPositionErrorMetres','oracleReadDenied','queryLabelsExcluded','expectedMapCount','mapCount','mapViews','optimizedCameraCount','maximumOptimizedCameraPositionErrorMetres']
for stage in ['rough','finished']:
    fixture=private/stage;result=private/(stage+'-replay.json');case=dict(stage=stage,width=768,passed=False,complete=False)
    try:
        subprocess.run([sys.executable,'tooling/simulation/whole_house_fixture.py',str(fixture),'--seed',str(a.seed),'--width','768','--stage',stage],check=True,timeout=600,stdout=subprocess.DEVNULL)
        checked=subprocess.run([sys.executable,'tooling/simulation/check_whole_house_bundle.py',str(fixture)],check=True,capture_output=True,text=True,timeout=60)
        replay=subprocess.run([sys.executable,'tooling/simulation/replay_fixture.py','--executable',str(a.executable),'--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=660)
        report=json.loads(result.read_text());generated=json.loads((fixture/'generator-summary.json').read_text())
        case.update(complete=True,rooms=generated['rooms'],levels=generated['levels'],inputArchiveCheckPassed=json.loads(checked.stdout)['passed'],**{k:report[k] for k in keys if k in report})
        case['passed']=replay.returncode==0 and report.get('passed') is True
    except Exception as error:case['errorClass']=type(error).__name__
    cases.append(case)
    summary=dict(source=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256(a.executable.read_bytes()).hexdigest(),cases=cases,complete=len(cases)==2 and all(c['complete'] for c in cases),passed=len(cases)==2 and all(c['passed'] for c in cases),physicalQualification=False,
        limitations=['Additional development sampling condition; the original 384-pixel failures remain failures','Partial captures, not whole-house coverage or registration qualification','No supported physical precision envelope is established by this experiment'])
    (a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(case),flush=True)
raise SystemExit(0 if summary['passed'] else 1)
