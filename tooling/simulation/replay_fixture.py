#!/usr/bin/env python3
"""Run exact Swift/C++ map/query code with the oracle denied by the OS sandbox."""
import argparse,hashlib,json,math,shutil,subprocess,tempfile,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--executable',type=Path,required=True);p.add_argument('--fixture',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--refine',action='store_true');p.add_argument('--bundle',action='store_true');p.add_argument('--house',action='store_true');a=p.parse_args()
exe=a.executable.resolve();fixture=a.fixture.resolve();oracle=json.loads((fixture/'vision-queries.json').read_text())
with tempfile.TemporaryDirectory(prefix='house-vision-evaluator-') as temporary:
 root=Path(temporary).resolve();candidate=root/'candidate';candidate.mkdir();(candidate/'temp').mkdir()
 with zipfile.ZipFile(fixture/'vision-map.hxray') as z:
  for item in z.infolist():
   path=Path(item.filename);assert not path.is_absolute() and '..' not in path.parts
  z.extractall(candidate)
 queries=[]
 for q in oracle['queries']:
  queries.append({key:q[key] for key in ('image','width','height','intrinsics','segmentID') if key in q})
  shutil.copyfile(fixture/q['image'],candidate/q['image'])
 (candidate/'queries.json').write_text(json.dumps({'queries':queries}))
 denied=root/'oracle.json';denied.write_text(json.dumps(oracle))
 # System libraries / executables are readable. Only candidate data and the frozen
 # executable are admitted from the workspace. The evaluator's oracle is outside.
 profile='(version 1)\n(deny default)\n(allow process*)\n(allow sysctl-read)\n(allow mach-lookup)\n(allow file-read-metadata)\n(allow file-read-data (literal "/"))\n'
 for directory in ['/System','/usr','/bin','/Library',str(candidate)]:profile+='(allow file-read* file-map-executable (subpath '+json.dumps(directory)+'))\n'
 profile+='(allow file-read* file-map-executable (literal '+json.dumps(str(exe))+'))\n'
 profile+='(allow file-write* (subpath '+json.dumps(str(candidate/'temp'))+'))\n(allow file-write* (literal "/dev/null"))\n'
 policy=root/'candidate.sb';policy.write_text(profile)
 sandbox=['/usr/bin/sandbox-exec','-f',str(policy)]
 positive=subprocess.run(sandbox+['/bin/cat',str(candidate/'house.json')],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd=candidate)
 negative=subprocess.run(sandbox+['/bin/cat',str(denied)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd=candidate)
 if positive.returncode!=0:
  diagnostics=subprocess.run(['/usr/bin/log','show','--last','1m','--style','compact','--predicate','process == "cat" OR eventMessage CONTAINS "Sandbox: cat(" OR eventMessage CONTAINS "Sandbox: vision-replay("'],capture_output=True,text=True,timeout=20)
  a.output.parent.mkdir(parents=True,exist_ok=True);a.output.with_suffix('.sandbox.log').write_text(diagnostics.stdout[-30000:]+diagnostics.stderr[-3000:])
 assert positive.returncode==0 and negative.returncode!=0, f'Oracle exclusion controls failed: permitted={positive.returncode} ({positive.stderr.decode()[-1000:]}), denied={negative.returncode} ({negative.stderr.decode()[-1000:]})'
 result=subprocess.run(sandbox+[str(exe),str(candidate),str(candidate/'queries.json')]+(['--refine'] if a.refine else [])+(['--bundle'] if a.bundle else [])+(['--house'] if a.house else []),capture_output=True,text=True,timeout=600 if a.house else 180,cwd=candidate)
 if result.returncode:
  a.output.parent.mkdir(parents=True,exist_ok=True)
  a.output.write_text(json.dumps(dict(passed=False,oracleReadDenied=True,candidateBinarySHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),candidateRejected=True,error=result.stderr[-5000:],productionQualified=False),indent=2))
  raise RuntimeError(result.stderr[-5000:])
 report=json.loads(result.stdout);by_name={x['image']:x for x in report['queries']};positive_accepted=0;false_accepts=0;worst=0.
 for q in oracle['queries']:
  r=by_name[q['image']]
  if q['shouldMatch'] is None:
   r['exploratoryScenario']=q.get('scenario','unscored query');continue
  if r['accepted'] and q['shouldMatch']:
   positive_accepted+=1;pose=r['worldFromARCamera'];truth=q['expectedCamera'];error=sum((pose[i]-truth[i])**2 for i in (3,7,11))**.5;r['evaluatorPositionErrorMetres']=error;worst=max(worst,error)
  elif r['accepted']:false_accepts+=1
 ambiguity_cases=sum(x.get('ambiguityCases',0) for x in report['queries']);ambiguity_rejected=a.house or all(x.get('ambiguousRoomAndFloorRejected',False) for x in report['queries'] if x['accepted'])
 report.update(ambiguityCases=ambiguity_cases,ambiguityRejected=ambiguity_rejected,oracleReadDenied=True,candidateBinarySHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),positiveAccepted=positive_accepted,positiveQueries=sum(q['shouldMatch'] is True for q in oracle['queries']),falseAccepts=false_accepts,negativeQueries=sum(q['shouldMatch'] is False for q in oracle['queries']),worstAcceptedPositionErrorMetres=worst,passed=positive_accepted>=2 and false_accepts==0 and worst<.03 and ambiguity_rejected,productionQualified=False,limitations=[oracle.get('renderer','Analytic textured-corner fixture'),'Perfectly synchronized analytic rendering','Not an iPhone sensor model','Does not qualify wrong-room rejection or field accuracy'])
 if a.house:
  accepted_errors=sorted(q['evaluatorPositionErrorMetres'] for q in report['queries'] if 'evaluatorPositionErrorMetres' in q)
  p95=accepted_errors[max(0,math.ceil(len(accepted_errors)*.95)-1)] if accepted_errors else None
  availability=positive_accepted/max(1,report['positiveQueries'])
  report.update(p95Metres=p95,availability=availability,passed=availability>=.9 and p95 is not None and p95<=.010 and worst<=.025 and false_accepts==0 and report['mapCount']==4)
  report['limitations']=['Four-room/two-level analytic construction layout','Incomplete corner coverage; no unseen cavity completeness claim','No calibrated phone sensor model','Finished-stage and full-house registration qualification remain separate']
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
