"""Observe production responses to four declared non-nominal sensor faults.

Clock-offset cases require abstention because no motion/time correction exists.
Other profiles retain the original spatial gate; their failures stay failures.
Source captures, oracle and individual poses never leave the ephemeral job.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tooling/simulation'))
from summarize_whole_house import summarize

p=argparse.ArgumentParser();p.add_argument('--profile',choices=['dim-blurred','depth-edges','calibration-drift','clock-interruptions'],required=True);a=p.parse_args()
private=ROOT/'build/sensor-private';public=ROOT/'build/sensor-aggregates';private.mkdir(parents=True,exist_ok=True);public.mkdir(parents=True,exist_ok=True)
states=[]
for stage in ['rough','finished']:
    fixture=private/stage;state=dict(stage=stage,complete=False,behaviorPassed=False)
    try:
        subprocess.run([sys.executable,'tooling/simulation/whole_house_fixture.py',str(fixture),'--seed','85838','--width','768','--stage',stage,'--profile',a.profile],check=True,timeout=600,stdout=subprocess.DEVNULL)
        checked=subprocess.run([sys.executable,'tooling/simulation/check_whole_house_bundle.py',str(fixture)],check=True,capture_output=True,text=True,timeout=60)
        (private/(stage+'-bundle-check.json')).write_text(checked.stdout)
        (private/(stage+'-generator.json')).write_text((fixture/'generator-summary.json').read_text())
        result=private/(stage+'-replay.json')
        replay=subprocess.run([sys.executable,'tooling/simulation/replay_fixture.py','--executable','build/vision-replay','--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=660)
        report=json.loads(result.read_text())
        complete=report.get('oracleReadDenied') is True and report.get('queryLabelsExcluded') is True and report.get('positiveQueries')==16 and report.get('negativeQueries')==32 and len(report.get('queries',[]))==48
        clock=a.profile=='clock-interruptions'
        behavior=(report.get('mapCount')==0 and report.get('positiveAccepted')==0 and report.get('falseAccepts')==0) if clock else (replay.returncode==0 and report.get('passed') is True)
        state.update(complete=complete,behaviorPassed=complete and behavior,originalSpatialGatePassed=report.get('passed') is True,
            expectedBehavior='Refuse depth maps with known asynchronous capture times' if clock else 'Preserve the original accuracy, availability and ambiguity gates')
    except Exception as error:state['errorClass']=type(error).__name__
    states.append(state)
    summary=summarize(private)
    summary.update(source=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256((ROOT/'build/vision-replay').read_bytes()).hexdigest(),profile=a.profile,behaviorCases=states,
        auditComplete=len(states)==2 and all(s['complete'] for s in states),auditPassed=len(states)==2 and all(s['behaviorPassed'] for s in states),
        limitations=['Declared non-nominal analytic fault conditions, not measured iPhone sensors','Clock mismatch is an intentional refusal test; no nominal gate is changed','Four-room partial capture only; no protected qualification or physical precision claim'])
    (public/'summary.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n');print(json.dumps(state),flush=True)
raise SystemExit(0 if summary['auditPassed'] else 1)
