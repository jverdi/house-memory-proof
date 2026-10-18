"""Retain aggregate outcomes, including refusals, for one development variant."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

p=argparse.ArgumentParser();p.add_argument('--seed',type=int,required=True);a=p.parse_args()
output=Path('build/coordinate-reports');output.mkdir(parents=True,exist_ok=True)
keys=['passed','positiveQueries','positiveAccepted','negativeQueries','falseAccepts','p95Metres','worstAcceptedPositionErrorMetres','oracleReadDenied','queryLabelsExcluded','expectedMapCount','mapCount','mapViews','optimizedCameraCount','maximumOptimizedCameraPositionErrorMetres']
cases=[]
for name,width,flags in [('rough',384,[]),('finished',384,['--paired','--staggered','--finished-capture']),('finished',768,['--paired','--staggered','--finished-capture'])]:
    fixture=Path(f'build/coordinate-private/{name}-{width}');result=fixture.parent/(fixture.name+'.json')
    case=dict(stage=name,width=width,passed=False,complete=False)
    try:
        subprocess.run([sys.executable,'tooling/simulation/house_layout_fixture.py',str(fixture),'--seed',str(a.seed),'--width',str(width),*flags],check=True,timeout=600,stdout=subprocess.DEVNULL)
        replay=subprocess.run([sys.executable,'tooling/simulation/replay_fixture.py','--executable','build/vision-replay','--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=660)
        report=json.loads(result.read_text())
        case.update(complete=True,**{k:report[k] for k in keys if k in report})
        case['passed']=replay.returncode==0 and report.get('passed') is True
    except Exception as error:case['errorClass']=type(error).__name__
    cases.append(case)
    summary=dict(source=os.environ.get('GITHUB_SHA','local'),candidateSHA256=hashlib.sha256(Path('build/vision-replay').read_bytes()).hexdigest(),cases=cases,complete=len(cases)==3 and all(c['complete'] for c in cases),passed=len(cases)==3 and all(c['passed'] for c in cases),physicalQualification=False,
        limitations=['Development-only detector variant, not adopted into the app','Original failures are retained; unchanged availability, accuracy and ambiguity gates','Raw source evidence and oracle remain ephemeral in CI'])
    (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(case),flush=True)
raise SystemExit(0 if summary['passed'] else 1)
