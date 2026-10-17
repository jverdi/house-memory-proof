#!/usr/bin/env python3
"""Development diversity sweep; never presented as protected holdout qualification."""
import argparse, json, subprocess, sys
from pathlib import Path
from vision_fixture import make
p=argparse.ArgumentParser();p.add_argument('--executable',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=a.output;root.mkdir(parents=True,exist_ok=True);cases=[]
for seed in [19043,47891,83117,109313,142697]:
 fixture=root/str(seed);make(fixture,seed,drift=.03)
 result=fixture/'replay.json'
 completed=subprocess.run([sys.executable,str(Path(__file__).with_name('replay_fixture.py')),'--executable',str(a.executable),'--fixture',str(fixture),'--output',str(result),'--refine'],capture_output=True,text=True)
 if result.exists():
  data=json.loads(result.read_text());cases.append(dict(seed=seed,report=str(result),**{k:data[k] for k in ('passed','positiveAccepted','positiveQueries','falseAccepts','negativeQueries','worstAcceptedPositionErrorMetres','oracleReadDenied','candidateBinarySHA256','optimizedCameraCount','maximumOptimizedCameraPositionErrorMetres','injectedTranslationDriftMetres')}))
 else:cases.append(dict(seed=seed,passed=False,error=completed.stderr[-3000:]))
 # Raw generated captures are reproducible; retain diagnostic reports and parameters.
 import shutil
 shutil.rmtree(fixture/'base',ignore_errors=True)
 for f in fixture.glob('*.jpg'):f.unlink()
 (fixture/'vision-map.hxray').unlink(missing_ok=True)
report=dict(developmentOnly=True,protectedHoldout=False,productionQualified=False,cases=cases,allDiagnosticCasesPassed=all(x['passed'] for x in cases),limitations=['Five analytic textured corners only','No full-house ambiguity suite','No sensor or physical calibration'])
(root/'matrix.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
if not report['allDiagnosticCasesPassed']:raise SystemExit(1)
