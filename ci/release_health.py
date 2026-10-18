"""Read-only release/account/CI health. Never creates Apple or GitHub records."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request
from apple_access import make_token, request
from renewal import decision, warning_days

ROOT=Path(__file__).resolve().parents[1]


def github(path, method='GET', body=None):
    token=os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:raise RuntimeError('GitHub credential unavailable')
    repository=os.environ.get('GITHUB_REPOSITORY','jverdi/house-memory-proof')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository):raise RuntimeError('Invalid repository identity')
    req=urllib.request.Request('https://api.github.com/repos/'+repository+path,
        method=method,data=json.dumps(body).encode() if body is not None else None,
        headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':'application/json','User-Agent':'House-Xray-release-health'})
    try:
        with urllib.request.urlopen(req,timeout=30) as response:
            raw=response.read();return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise RuntimeError('GitHub API HTTP '+str(error.code)) from None


def timestamp(value):
    parsed=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    if parsed.tzinfo is None:raise ValueError('Timestamp must identify a timezone')
    return parsed


def summarize(snapshot,policy,now=None):
    now=now or dt.datetime.now(dt.timezone.utc)
    checked=timestamp(snapshot['checkedUTC'])
    age=(now-checked).total_seconds()
    fresh=0 <= age <= 86400
    apple=snapshot.get('apple',{})
    builds=apple.get('builds',[])
    due=warning=reason=None
    if apple.get('readAccessVerified') is True:
        due,reason=decision(builds,now);warning=warning_days(builds,now)
    valid=[b for b in builds if b['attributes'].get('processingState')=='VALID'
           and b['attributes'].get('expired') is False and timestamp(b['attributes']['expirationDate'])>now]
    newest=max(valid,key=lambda b:timestamp(b['attributes']['uploadedDate']),default=None)
    ci=snapshot.get('github',{})
    runs=ci.get('runs',[])
    # Preserve failures in any evaluated workflow and absence of exact-source CI.
    latest={}
    for run in sorted(runs,key=lambda r:r['id'],reverse=True):
        if run.get('head_sha')==ci.get('source') and run['name'] not in latest:latest[run['name']]=run
    # A monitor must not wait for its own completion or treat a skipped
    # delivery-inspection workflow as a failed candidate build.
    monitors={'Inspect release health','Inspect TestFlight readiness'}
    gates=[r for r in latest.values() if r['name'] not in monitors]
    native=[r for r in gates if r['name']=='Build and deliver House Proof']
    ci_pass=bool(native) and all(r.get('status')=='completed' and r.get('conclusion')=='success' for r in gates)
    return dict(checkedUTC=snapshot['checkedUTC'],readOnly=True,fresh=fresh,
        passed=fresh and apple.get('readAccessVerified') is True and bool(valid) and ci.get('readAccessVerified') is True and ci_pass,
        appleReadAccessVerified=apple.get('readAccessVerified') is True,
        githubReadAccessVerified=ci.get('readAccessVerified') is True,
        newestValidBuild=newest['attributes'].get('version') if newest else None,
        buildAgeDays=(now-timestamp(newest['attributes']['uploadedDate'])).total_seconds()/86400 if newest else None,
        daysUntilExpiry=(timestamp(newest['attributes']['expirationDate'])-now).total_seconds()/86400 if newest else None,
        refreshDue=due,expiryWarningDays=warning,renewalReason=reason,
        automaticRenewal=policy.get('automatic_renewal') is True,pinnedReleaseTag=policy.get('release_tag'),
        currentSource=ci.get('source'),exactSourceCIPassed=ci_pass,
        workflows=[dict(id=r['id'],name=r['name'],status=r['status'],conclusion=r.get('conclusion')) for r in latest.values()],
        signingCertificateInventory=apple.get('certificateInventory'),
        errors=[x['error'] for x in [apple,ci] if x.get('error')],
        unknown=['Current signing/export requires the separate signed archive audit.','Developer agreement and physical installation state are not inferred from API access.'],
        physicalInstallationVerified=False,releaseAccepted=None,releaseAcceptanceEvaluated=False)


def collect_live(now=None):
    now=now or dt.datetime.now(dt.timezone.utc)
    snapshot=dict(checkedUTC=now.isoformat(),apple={},github={})
    try:
        token=make_token();bundle=os.environ.get('APP_BUNDLE_ID','com.jverdi.housememoryproof')
        apps=request(token,'/v1/apps?'+urllib.parse.urlencode({'filter[bundleId]':bundle}))['data']
        if len(apps)!=1:raise RuntimeError('Expected one matching app')
        builds=request(token,'/v1/builds?'+urllib.parse.urlencode({'filter[app]':apps[0]['id'],'sort':'-uploadedDate','limit':200}))['data']
        # Never retain people, keys, certificate content or server descriptions.
        allowed=['version','processingState','expired','uploadedDate','expirationDate']
        snapshot['apple']=dict(readAccessVerified=True,builds=[dict(attributes={k:b['attributes'][k] for k in allowed}) for b in builds])
        try:
            certs=request(token,'/v1/certificates?limit=200')['data']
            dates=[timestamp(c['attributes']['expirationDate']) for c in certs if c['attributes'].get('expirationDate')]
            snapshot['apple']['certificateInventory']=dict(checked=True,active=sum(d>now for d in dates),expired=sum(d<=now for d in dates),signingTested=False)
        except Exception:
            snapshot['apple']['certificateInventory']=dict(checked=False,signingTested=False)
    except Exception as error:
        snapshot['apple']=dict(readAccessVerified=False,error='Apple read unavailable: '+type(error).__name__)
    try:
        source=github('/git/ref/heads/main')['object']['sha']
        runs=github('/actions/runs?'+urllib.parse.urlencode({'head_sha':source,'per_page':100}))['workflow_runs']
        keys=['id','name','head_sha','status','conclusion']
        snapshot['github']=dict(readAccessVerified=True,source=source,runs=[{k:r.get(k) for k in keys} for r in runs])
    except Exception as error:
        snapshot['github']=dict(readAccessVerified=False,error='GitHub read unavailable: '+type(error).__name__)
    return snapshot


def release(commit,ref='main',ship=False,dispatch=False):
    if not re.fullmatch('[0-9a-f]{40}',commit):raise ValueError('A full lowercase source commit is required')
    policy=json.loads((ROOT/'ci/release-policy.json').read_text())
    if ref not in ['main',policy['release_tag']]:raise ValueError('Use main for validation or the pinned personal release tag')
    if ship:
        qualification=json.loads((ROOT/'tasks/qualification.json').read_text())
        latest=qualification.get('latestIntegratedPass',{})
        if ref!=policy['release_tag'] or qualification.get('overall')!='accepted' or qualification.get('softwareAcceptanceOpen') or qualification.get('externalAcceptanceOpen') or latest.get('source')!=commit:
            raise ValueError('Final upload is blocked by the recorded acceptance gates or mismatched accepted source')
    resolved=github('/commits/'+urllib.parse.quote(ref,safe=''))['sha']
    if resolved!=commit:raise ValueError('Requested source does not match the dispatch reference; nothing was dispatched')
    result=dict(source=commit,ref=ref,shipRequested=ship,dispatched=False,appleProcessing='not checked',testflightDeliveryVerified=False)
    if dispatch:
        github('/actions/workflows/ios.yml/dispatches',method='POST',body=dict(ref=ref,inputs={'ship':str(ship).lower()}))
        result['dispatched']=True
        result['status']='CI request accepted; build and Apple processing remain pending'
    else:result['status']='Reference verified; use --dispatch to submit this exact request'
    return result


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    snapshot=json.loads(args.input.read_text()) if args.input else collect_live()
    report=summarize(snapshot,json.loads((ROOT/'ci/release-policy.json').read_text()))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    print(json.dumps(report))
    raise SystemExit(0 if report['passed'] else 1)
