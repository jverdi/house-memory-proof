"""Compare one development candidate under dim/blur and nominal controls.

Only allowlisted aggregates are retained. Inputs, query poses, original maps and
evaluator truth stay in the ephemeral private job directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tooling/simulation'))
from summarize_whole_house import summarize

p=argparse.ArgumentParser();p.add_argument('--profile',choices=['dim-blurred','nominal'],required=True);a=p.parse_args()
private=ROOT/'build/low-light-private';public=ROOT/'build/low-light-aggregates'
private.mkdir(parents=True,exist_ok=True);public.mkdir(parents=True,exist_ok=True)
attempts=[]
for stage in ['rough','finished']:
    state=dict(stage=stage,complete=False,passed=False);fixture=private/stage
    try:
        subprocess.run([sys.executable,'tooling/simulation/whole_house_fixture.py',str(fixture),'--seed','85838','--width','768','--stage',stage,'--profile',a.profile],check=True,timeout=300,stdout=subprocess.DEVNULL)
        checked=subprocess.run([sys.executable,'tooling/simulation/check_whole_house_bundle.py',str(fixture)],check=True,capture_output=True,text=True,timeout=60)
        (private/(stage+'-bundle-check.json')).write_text(checked.stdout)
        (private/(stage+'-generator.json')).write_text((fixture/'generator-summary.json').read_text())
        result=private/(stage+'-replay.json')
        replay=subprocess.run([sys.executable,'tooling/simulation/replay_fixture.py','--executable','build/vision-replay','--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=420)
        report=json.loads(result.read_text())
        complete=report.get('oracleReadDenied') is True and report.get('queryLabelsExcluded') is True and report.get('positiveQueries')==16 and report.get('negativeQueries')==32 and len(report.get('queries',[]))==48
        state.update(complete=complete,passed=complete and replay.returncode==0 and report.get('passed') is True)
    except Exception as error:state['errorClass']=type(error).__name__
    attempts.append(state)
    summary=summarize(private)
    summary.update(source=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256((ROOT/'build/vision-replay').read_bytes()).hexdigest(),
        profile=a.profile,attempts=attempts,experimentAdopted=False,complete=len(attempts)==2 and all(s['complete'] for s in attempts),
        passed=len(attempts)==2 and all(s['passed'] for s in attempts),
        limitations=['One analytic development house, not protected qualification','Fixed candidate and original gates; no parameter search','Original 384-pixel accuracy and finished depth-edge failures remain open'])
    (public/'summary.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n');print(json.dumps(state),flush=True)
raise SystemExit(0 if summary['passed'] else 1)
