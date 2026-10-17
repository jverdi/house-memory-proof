"""Avoid submitting the same app/build twice after an interrupted upload job."""
import json
import os
from pathlib import Path
import urllib.parse
from apple_access import make_token,request

def existing_state(builds,version):
    matching=[b for b in builds if b['attributes']['version']==version]
    if len(matching)>1:raise RuntimeError('More than one Apple record matches this build number; resolve the release ledger before uploading.')
    if not matching:return 'absent'
    state=matching[0]['attributes']['processingState']
    if state not in ('VALID','PROCESSING'):raise RuntimeError('This build number already exists in Apple with processing state '+state+'. Retain the failed record and use a new release attempt.')
    return state.lower()

def main():
    token=make_token();version=os.environ['HOUSE_RELEASE_BUILD'];bundle=os.environ['APP_BUNDLE_ID']
    apps=request(token,'/v1/apps?'+urllib.parse.urlencode({'filter[bundleId]':bundle}))['data']
    if len(apps)!=1:raise RuntimeError('Expected one App Store Connect app before release.')
    builds=request(token,'/v1/builds?'+urllib.parse.urlencode({'filter[app]':apps[0]['id'],'filter[version]':version,'limit':200}))['data']
    state=existing_state(builds,version)
    report=dict(build=version,revision=os.environ['HOUSE_RELEASE_REVISION'],existing_state=state,upload_needed=state=='absent')
    Path('build/evidence/upload-preflight.json').write_text(json.dumps(report,indent=2)+'\n')
    if state!='absent':
        Path('build/evidence/upload-result.json').write_text(json.dumps(dict(status='existing_apple_build_reused',**report,apple_processing_verified=state=='valid',internal_tester_access_verified=False,physical_iPhone_verified=False),indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()
