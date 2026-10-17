#!/usr/bin/env python3
"""Run exact Swift/C++ map/query code with the oracle denied by the OS sandbox."""
import argparse,hashlib,json,shutil,subprocess,tempfile,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--executable',type=Path,required=True);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--refine',action='store_true');a=p.parse_args()
exe=a.executable.resolve();fixture=a.fixture.resolve();oracle=json.loads((fixture/'vision-queries.json').read_text())
with tempfile.TemporaryDirectory(prefix='house-vision-evaluator-') as temporary:
 root=Path(temporary).resolve();candidate=root/'candidate';candidate.mkdir();(candidate/'temp').mkdir()
 with zipfile.ZipFile(fixture/'vision-map.hxray') as z:
  for item in z.infolist():
   path=Path(item.filename);assert not path.is_absolute() and '..' not in path.parts
  z.extractall(candidate)
 queries=[]
 for q in oracle['queries']:
  queries.append({key:q[key] for key in ('image','width','height','intrinsics')})
  shutil.copyfile(fixture/q['image'],candidate/q['image'])
 (candidate/'queries.json').write_text(json.dumps({'queries':queries}))
 denied=root/'oracle.json';denied.write_text(json.dumps(oracle))
 # System libraries / executables are readable. Only candidate data and the frozen
 # executable are admitted from the workspace. The evaluator's oracle is outside.
 profile='(version 1)\n(deny default)\n(allow process*)\n(allow sysctl-read)\n(allow mach-lookup)\n(allow file-read-metadata)\n'
 for directory in ['/System','/usr','/bin','/Library',str(candidate)]:profile+='(allow file-read* (subpath '+json.dumps(directory)+'))\n'
 profile+='(allow file-read* (literal '+json.dumps(str(exe))+'))\n'
 profile+='(allow file-write* (subpath '+json.dumps(str(candidate/'temp'))+'))\n(allow file-write* (literal "/dev/null"))\n'
 policy=root/'candidate.sb';policy.write_text(profile)
 sandbox=['/usr/bin/sandbox-exec','-f',str(policy)]
 positive=subprocess.run(sandbox+['/bin/cat',str(candidate/'house.json')],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 negative=subprocess.run(sandbox+['/bin/cat',str(denied)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 assert positive.returncode==0 and negative.returncode!=0, f'Oracle exclusion controls failed: permitted={positive.returncode} ({positive.stderr.decode()[-1000:]}), denied={negative.returncode} ({negative.stderr.decode()[-1000:]})'
 result=subprocess.run(sandbox+[str(exe),str(candidate),str(candidate/'queries.json')]+(['--refine'] if a.refine else []),capture_output=True,text=True,timeout=180)
 if result.returncode:raise RuntimeError(result.stderr[-5000:])
 report=json.loads(result.stdout);by_name={x['image']:x for x in report['queries']};positive_accepted=0;false_accepts=0;worst=0.
 for q in oracle['queries']:
  r=by_name[q['image']]
  if r['accepted'] and q['shouldMatch']:
   positive_accepted+=1;pose=r['worldFromARCamera'];truth=q['expectedCamera'];error=sum((pose[i]-truth[i])**2 for i in (3,7,11))**.5;r['evaluatorPositionErrorMetres']=error;worst=max(worst,error)
  elif r['accepted']:false_accepts+=1
 report.update(oracleReadDenied=True,candidateBinarySHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),positiveAccepted=positive_accepted,positiveQueries=3,falseAccepts=false_accepts,negativeQueries=1,worstAcceptedPositionErrorMetres=worst,passed=positive_accepted>=2 and false_accepts==0 and worst<.03,productionQualified=False,limitations=['One textured-corner fixture','Perfectly synchronized analytic rendering','Not an iPhone sensor model','Does not qualify wrong-room rejection or field accuracy'])
 if a.refine:
  errors=[]
  for identity,pose in report['optimizedCameras'].items():
   truth=oracle['mappingCameras'][identity];errors.append(sum((pose[i]-truth[i])**2 for i in (3,7,11))**.5)
  report['optimizedCameraCount']=len(errors);report['maximumOptimizedCameraPositionErrorMetres']=max(errors,default=float('inf'))
  report['injectedTranslationDriftMetres']=oracle['injectedTranslationDriftMetres']
  report['passed']=report['passed'] and len(errors)>=3 and max(errors,default=1)<.015
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))
 print(json.dumps({k:report[k] for k in ['passed','positiveAccepted','falseAccepts','worstAcceptedPositionErrorMetres','oracleReadDenied']}))
 if not report['passed']:raise SystemExit(1)
