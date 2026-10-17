"""Renew only a pinned accepted beta; never upload the moving development branch."""
import datetime as dt
import json
import os
from pathlib import Path
import urllib.parse
from apple_access import make_token, request

def decision(builds, now):
    def date(value):
        return dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    for build in builds:
        attrs = build['attributes']
        if attrs['processingState'] == 'PROCESSING' and now-date(attrs['uploadedDate']) < dt.timedelta(days=1):
            return False, 'A recent upload is still processing.'
    valid = [b['attributes'] for b in builds if b['attributes']['processingState']=='VALID' and not b['attributes']['expired'] and date(b['attributes']['expirationDate'])>now]
    if not valid:
        return True, 'No unexpired valid build is available.'
    newest=max(valid,key=lambda b:date(b['uploadedDate']))
    age=now-date(newest['uploadedDate'])
    remaining=date(newest['expirationDate'])-now
    return age>=dt.timedelta(days=45) or remaining<=dt.timedelta(days=30), f'Latest valid build is {age.total_seconds()/86400:.1f} days old and expires in {remaining.total_seconds()/86400:.1f} days.'

def warning_days(builds,now):
    valid=[b['attributes'] for b in builds if b['attributes']['processingState']=='VALID' and not b['attributes']['expired']]
    if not valid:return 0
    remaining=max(dt.datetime.fromisoformat(b['expirationDate'].replace('Z','+00:00')) for b in valid)-now
    return next((days for days in [7,14,30] if remaining<=dt.timedelta(days=days)),None)

def main():
    policy=json.loads(Path('ci/release-policy.json').read_text())
    token=make_token();bundle=os.environ['APP_BUNDLE_ID']
    apps=request(token,'/v1/apps?'+urllib.parse.urlencode({'filter[bundleId]':bundle}))['data']
    if len(apps)!=1:raise RuntimeError('Expected one personal app record.')
    builds=request(token,'/v1/builds?'+urllib.parse.urlencode({'filter[app]':apps[0]['id'],'sort':'-uploadedDate','limit':200}))['data']
    now=dt.datetime.now(dt.timezone.utc)
    due,reason=decision(builds,now);warning=warning_days(builds,now)
    needed=due and policy['automatic_renewal']
    if not policy['automatic_renewal']:reason+=' Automatic renewal remains disabled until a release is accepted.'
    report={'renewal_needed':needed,'refresh_due':due,'warning_days':warning,'reason':reason,'release_tag':policy['release_tag']}
    if warning is not None:print('::warning::Personal TestFlight expiry needs attention. '+reason)
    Path('build/evidence').mkdir(parents=True,exist_ok=True)
    Path('build/evidence/renewal.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
    with open(os.environ['GITHUB_OUTPUT'],'a') as output:output.write('needed='+str(needed).lower()+'\n')

if __name__=='__main__':main()
