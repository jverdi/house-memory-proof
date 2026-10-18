"""Frozen-candidate varied-house qualification, with evaluator-only seed plans.

Preparation follows binary freezing. Protected plans and individual replay data
stay in bounded job artifacts; only aggregate results are suitable for the public
ledger. A disclosed protected case must not be reused as a hidden case.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import secrets
import shutil
import subprocess
import sys
import time
import zipfile
from house_topology import generate,topology_signature

SHARDS=14
SOURCE=os.environ.get('GITHUB_SHA','local')


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        while block:=f.read(1048576):h.update(block)
    return h.hexdigest()


def prepare(executable,folder):
    """The protected draw happens after this exact executable is available."""
    binary=digest(executable);folder.mkdir(parents=True,exist_ok=True)
    signatures=set();seeds=set();plans=[[] for _ in range(SHARDS)]
    for index in range(70):
        split='development' if index<50 else 'protected';attempts=0
        while True:
            attempts+=1
            if attempts>1000:raise RuntimeError('Could not construct unique topology inventory')
            seed=70000+index*7919+(attempts-1)*10000019 if split=='development' else secrets.randbits(32)
            if seed in seeds:continue
            house=generate(seed);signature=topology_signature(house)
            if signature in signatures:continue
            signatures.add(signature);seeds.add(seed);break
        plans[index%SHARDS].append(dict(case=f'{split}-{index:02d}',split=split,seed=seed,topologySignature=signature,rooms=len(house['rooms']),levels=house['levels']))
    for shard,cases in enumerate(plans):
        document=dict(schema=1,source=SOURCE,candidateSHA256=binary,shard=shard,width=384,profile='nominal',stages=['rough','finished'],cases=cases)
        (folder/f'plan-{shard}.json').write_text(json.dumps(document,indent=2)+'\n')
    summary=dict(source=SOURCE,candidateSHA256=binary,developmentHouses=50,protectedHouses=20,distinctTopologies=len(signatures),shards=SHARDS,plansEvaluatorOnly=True,productionQualified=False)
    (folder/'inventory-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary),flush=True)
    return summary


def run(executable,plan_file,output):
    plan=json.loads(plan_file.read_text());binary=digest(executable)
    if plan['source']!=SOURCE or plan['candidateSHA256']!=binary:raise RuntimeError('Frozen binary or source identity changed')
    if plan['width']!=384 or plan['profile']!='nominal' or plan['stages']!=['rough','finished'] or not 0<=plan['shard']<SHARDS:raise RuntimeError('Unexpected qualification contract')
    output.mkdir(parents=True,exist_ok=True);records=output.parent/'replay-records';records.mkdir(parents=True,exist_ok=True);cases=[]
    for spec in plan['cases']:
        for stage in plan['stages']:
            name=spec['case']+'-'+stage;fixture=output.parent/('temporary-'+name);started=time.monotonic()
            case=dict(case=spec['case'],split=spec['split'],stage=stage,topologySignature=spec['topologySignature'],rooms=spec['rooms'],levels=spec['levels'],
                positiveQueries=4*spec['rooms'],negativeQueries=8*spec['rooms'],positiveAccepted=0,criticalFalseAccepts=0,executedQueries=0,positionErrorsMetres=[],oracleReadDenied=False,passed=False,errorClass='incomplete')
            record=dict(**spec,stage=stage,source=SOURCE,candidateSHA256=binary,width=plan['width'],profile=plan['profile'])
            try:
                generated=subprocess.run([sys.executable,str(Path(__file__).with_name('whole_house_fixture.py')),str(fixture),'--seed',str(spec['seed']),'--width',str(plan['width']),'--stage',stage,'--profile',plan['profile']],capture_output=True,text=True,timeout=600)
                if generated.returncode:raise RuntimeError('generator_failed')
                checked=subprocess.run([sys.executable,str(Path(__file__).with_name('check_whole_house_bundle.py')),str(fixture)],capture_output=True,text=True,timeout=60)
                if checked.returncode:raise RuntimeError('bundle_contract_failed')
                with zipfile.ZipFile(fixture/'vision-map.hxray') as z:record['inputManifestSHA256']=hashlib.sha256(z.read('manifest.json')).hexdigest()
                actual=json.loads((fixture/'generator-summary.json').read_text())
                if actual['topologySignature']!=spec['topologySignature'] or actual['rooms']!=spec['rooms']:raise RuntimeError('topology_changed_after_freeze')
                result=output/(name+'-replay.json')
                process=subprocess.run([sys.executable,str(Path(__file__).with_name('replay_fixture.py')),'--executable',str(executable),'--fixture',str(fixture),'--output',str(result),'--refine','--bundle','--house'],capture_output=True,text=True,timeout=660)
                report=json.loads(result.read_text()) if result.exists() else {}
                queries=report.get('queries',[])
                case.update(positiveAccepted=report.get('positiveAccepted',0),criticalFalseAccepts=report.get('falseAccepts',0),executedQueries=len(queries),
                    positionErrorsMetres=[q['evaluatorPositionErrorMetres'] for q in queries if 'evaluatorPositionErrorMetres' in q],oracleReadDenied=report.get('oracleReadDenied',False),
                    queryLabelsExcluded=report.get('queryLabelsExcluded',False),mapCount=report.get('mapCount',0),expectedMapCount=report.get('expectedMapCount',0),
                    optimizedCameraCount=report.get('optimizedCameraCount',0),maximumSourcePositionErrorMetres=report.get('maximumOptimizedCameraPositionErrorMetres'),
                    passed=process.returncode==0 and report.get('passed') is True,errorClass='none' if process.returncode==0 else 'candidate_or_spatial_gate')
                if report.get('positiveQueries')!=case['positiveQueries'] or report.get('negativeQueries')!=case['negativeQueries'] or len(queries)!=case['positiveQueries']+case['negativeQueries']:
                    case.update(passed=False,errorClass='incomplete_query_denominator')
                if report.get('candidateBinarySHA256')!=binary:case.update(passed=False,errorClass='candidate_identity_changed')
            except Exception as error:
                # Exception strings can contain subprocess arguments and hidden
                # seeds. Publish only a controlled class, never the message.
                case.update(passed=False,errorClass=type(error).__name__)
            finally:
                case['seconds']=time.monotonic()-started
                (records/(name+'.json')).write_text(json.dumps(record,indent=2)+'\n')
                shutil.rmtree(fixture,ignore_errors=True)
            cases.append(case)
            (output/f'shard-{plan["shard"]}.json').write_text(json.dumps(dict(schema=1,source=SOURCE,candidateSHA256=binary,shard=plan['shard'],cases=cases),indent=2)+'\n')
            print(json.dumps({k:case[k] for k in ['case','stage','positiveQueries','positiveAccepted','criticalFalseAccepts','passed','errorClass','seconds']}),flush=True)
    return True  # The aggregate enforces complete denominators and every gate.


def quantile(values,fraction):
    if not values:return None
    values=sorted(values);return values[max(0,math.ceil(len(values)*fraction)-1)]


def summarize(cases):
    errors=[e for c in cases for e in c['positionErrorsMetres']];positive=sum(c['positiveQueries'] for c in cases);accepted=sum(c['positiveAccepted'] for c in cases)
    return dict(stageCases=len(cases),houses=len({c['case'] for c in cases}),positiveQueries=positive,positiveAccepted=accepted,availability=accepted/max(1,positive),
        criticalQueries=sum(c['negativeQueries'] for c in cases),criticalFalseAccepts=sum(c['criticalFalseAccepts'] for c in cases),executedQueries=sum(c['executedQueries'] for c in cases),
        oracleControlFailures=sum(not c['oracleReadDenied'] for c in cases),failedStageCases=sum(not c['passed'] for c in cases),p50Metres=quantile(errors,.5),p95Metres=quantile(errors,.95),worstMetres=max(errors,default=None))


def cluster_intervals(cases,draws=1000):
    grouped={}
    for c in cases:grouped.setdefault(c['case'],[]).append(c)
    groups=list(grouped.values());rng=random.Random(59273);availability=[];tails=[]
    for _ in range(draws):
        sample=[c for _ in groups for c in rng.choice(groups)];r=summarize(sample);availability.append(r['availability'])
        if r['p95Metres'] is not None:tails.append(r['p95Metres'])
    return dict(method='Whole-house paired-stage cluster bootstrap, percentile interval',draws=draws,confidence=.95,
        availability=[quantile(availability,.025),quantile(availability,.975)],p95Metres=[quantile(tails,.025),quantile(tails,.975)])


def valid_case(c):
    """Recheck denominators and gates instead of trusting an upstream pass bit."""
    counts=['rooms','levels','positiveQueries','negativeQueries','positiveAccepted','criticalFalseAccepts','executedQueries']
    if any(type(c.get(k)) is not int or c[k]<0 for k in counts):return False
    if not 1<=c['rooms']<=24 or not 1<=c['levels']<=4:return False
    if c['positiveQueries']!=4*c['rooms'] or c['negativeQueries']!=8*c['rooms']:return False
    if c['positiveAccepted']>c['positiveQueries'] or c['criticalFalseAccepts']>c['negativeQueries']:return False
    if c['executedQueries']!=c['positiveQueries']+c['negativeQueries']:return False
    if c.get('stage') not in ['rough','finished'] or c.get('split') not in ['development','protected']:return False
    if not re.fullmatch(c['split']+r'-\d{2}',c.get('case','')):return False
    if not re.fullmatch(r'[a-f0-9]{64}',c.get('topologySignature','')):return False
    errors=c.get('positionErrorsMetres')
    if not isinstance(errors,list) or len(errors)!=c['positiveAccepted']:return False
    if any(type(e) not in [int,float] or not math.isfinite(e) or e<0 for e in errors):return False
    if c.get('passed') is True:
        source_error=c.get('maximumSourcePositionErrorMetres')
        if c.get('oracleReadDenied') is not True or c.get('queryLabelsExcluded') is not True:return False
        if c.get('mapCount')!=c['rooms'] or c.get('expectedMapCount')!=c['rooms']:return False
        if type(c.get('optimizedCameraCount')) is not int or c['optimizedCameraCount']<3:return False
        if type(source_error) not in [int,float] or not math.isfinite(source_error) or not 0<=source_error<.015:return False
        if c['positiveAccepted']/c['positiveQueries']<.9 or c['criticalFalseAccepts']!=0:return False
        if not errors or quantile(errors,.95)>.010 or max(errors)>.025:return False
    return True


def aggregate(folder):
    shards=[json.loads(p.read_text()) for p in sorted(folder.glob('shard-*.json'))];cases=[c for s in shards for c in s['cases']]
    keys={(c['case'],c['stage']) for c in cases};house_signatures={}
    for c in cases:house_signatures.setdefault(c['case'],set()).add(c['topologySignature'])
    identities={(s['source'],s['candidateSHA256']) for s in shards}
    integrity_failures=sum(not valid_case(c) for c in cases)
    # Malformed numeric fields must not poison JSON or manufacture a pass. Keep
    # the complete case count in the status while scoring only valid records.
    scored=[c for c in cases if valid_case(c)];report=summarize(scored)
    report.update(development=summarize([c for c in scored if c['split']=='development']),protected=summarize([c for c in scored if c['split']=='protected']),
        sourceIdentities=[dict(source=s,binarySHA256=b) for s,b in sorted(identities)],distinctTopologies=len({c['topologySignature'] for c in cases}),productionQualified=False)
    expected_cases={f'development-{i:02d}' for i in range(50)}|{f'protected-{i:02d}' for i in range(50,70)}
    complete=(integrity_failures==0 and len(shards)==SHARDS and {s['shard'] for s in shards}==set(range(SHARDS))
        and all(s.get('schema')==1 and len(s['cases'])==10 for s in shards)
        and len(identities)==1 and all(re.fullmatch(r'[a-f0-9]{40}',s) and re.fullmatch(r'[a-f0-9]{64}',b) for s,b in identities)
        and len(cases)==140 and len(keys)==140 and set(house_signatures)==expected_cases
        and report['development']['houses']==50 and report['protected']['houses']==20 and report['distinctTopologies']==70
        and all(len(v)==1 for v in house_signatures.values()) and all({c['stage'] for c in cases if c['case']==name}=={'rough','finished'} for name in house_signatures)
        and all(len({(c['split'],c['rooms'],c['levels']) for c in cases if c['case']==name})==1 for name in house_signatures)
        and report['positiveQueries']>=1000 and report['criticalQueries']>=3000 and report['executedQueries']==report['positiveQueries']+report['criticalQueries'])
    report['complete']=complete;report['receivedStageCases']=len(cases);report['reportIntegrityFailures']=integrity_failures
    report['declaredPositiveQueries']=sum(c.get('positiveQueries',0) for c in cases if type(c.get('positiveQueries')) is int and c['positiveQueries']>=0)
    report['declaredCriticalQueries']=sum(c.get('negativeQueries',0) for c in cases if type(c.get('negativeQueries')) is int and c['negativeQueries']>=0)
    def gates(r):return r['availability']>=.9 and r['criticalFalseAccepts']==0 and r['oracleControlFailures']==0 and r['failedStageCases']==0 and r['p95Metres'] is not None and r['p95Metres']<=.010 and r['worstMetres']<=.025
    report['passed']=complete and gates(report) and gates(report['development']) and gates(report['protected'])
    if scored:report['clusterUncertainty']=cluster_intervals(scored)
    report['limitations']=['Selected corners and upper-wall views, not complete house coverage','Nominal analytic sensor profile; degraded sensor sweeps remain separate','No cross-room registration, continuous navigation, closed-loop guidance or thin-service completeness score','No physical device or field qualification']
    (folder/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True);return report['passed']


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--executable',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--plan',type=Path);p.add_argument('--prepare',action='store_true');p.add_argument('--aggregate',action='store_true');a=p.parse_args()
    result=prepare(a.executable,a.output) if a.prepare else aggregate(a.output) if a.aggregate else run(a.executable,a.plan,a.output)
    raise SystemExit(0 if result else 1)
