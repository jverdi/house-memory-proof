"""Read Apple processing and TestFlight readiness without exposing credentials."""
import json
import os
from pathlib import Path
import time
import urllib.parse
from apple_access import make_token, request

bundle = os.environ.get('APP_BUNDLE_ID') or 'com.jverdi.housememoryproof'
version = os.environ.get('TARGET_BUILD', '')
wait_seconds = int(os.environ.get('WAIT_SECONDS', '0'))
deadline = time.monotonic() + wait_seconds
while True:
    token = make_token()
    apps = request(token, '/v1/apps?' + urllib.parse.urlencode({'filter[bundleId]': bundle}))['data']
    if len(apps) != 1:
        raise SystemExit('Expected exactly one App Store Connect app for this bundle.')
    app = apps[0]
    filters = {'filter[app]': app['id'], 'sort': '-uploadedDate', 'limit': 10}
    if version:
        filters['filter[version]'] = version
    builds = request(token, '/v1/builds?' + urllib.parse.urlencode(filters))['data']
    owners = request(token, '/v1/users?' + urllib.parse.urlencode({'filter[roles]': 'ACCOUNT_HOLDER'}))['data']
    owner_matches = [u for u in owners if u['attributes'].get('firstName', '').lower() == 'jared' and u['attributes'].get('lastName', '').lower() in ('verdi', 'testerverdi')]
    report = {'personal_account_holder_verified': len(owners) == 1 and len(owner_matches) == 1, 'app_id': app['id'], 'app_name': app['attributes']['name'],
              'bundle_id': bundle, 'target_build': version, 'builds': []}
    # Deliver only to the uniquely verified owner, never other team members.
    valid_builds = [b for b in builds if b['attributes']['processingState'] == 'VALID' and not b['attributes']['expired']]
    if valid_builds and len(owners) == 1 and len(owner_matches) == 1:
        owner = owner_matches[0]['attributes']
        groups = request(token, '/v1/apps/' + app['id'] + '/betaGroups')['data']
        personal = [g for g in groups if g['attributes']['name'] == 'Personal iPhone' and g['attributes']['isInternalGroup']]
        if len(personal) > 1:
            raise SystemExit('Ambiguous personal testing group.')
        if not personal:
            personal = [request(token, '/v1/betaGroups', {'data': {
                'type': 'betaGroups', 'attributes': {'name': 'Personal iPhone', 'isInternalGroup': True, 'hasAccessToAllBuilds': True},
                'relationships': {'app': {'data': {'type': 'apps', 'id': app['id']}}}}})['data']]
        group_id = personal[0]['id']
        testers = request(token, '/v1/betaTesters?' + urllib.parse.urlencode({'filter[email]': owner['username']}))['data']
        if len(testers) > 1:
            raise SystemExit('Ambiguous account holder tester record.')
        if not testers:
            testers = [request(token, '/v1/betaTesters', {'data': {'type': 'betaTesters',
                'attributes': {'email': owner['username'], 'firstName': owner['firstName'], 'lastName': owner['lastName']},
                'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group_id}]}}}})['data']]
        members = request(token, '/v1/betaGroups/' + group_id + '/relationships/betaTesters')['data']
        if not any(m['id'] == testers[0]['id'] for m in members):
            request(token, '/v1/betaGroups/' + group_id + '/relationships/betaTesters',
                    {'data': [{'type': 'betaTesters', 'id': testers[0]['id']}]})
        assigned = request(token, '/v1/betaGroups/' + group_id + '/relationships/builds')['data']
        missing = [b for b in valid_builds if not any(a['id'] == b['id'] for a in assigned)]
        if missing:
            request(token, '/v1/betaGroups/' + group_id + '/relationships/builds',
                    {'data': [{'type': 'builds', 'id': b['id']} for b in missing]})
        members = request(token, '/v1/betaGroups/' + group_id + '/relationships/betaTesters')['data']
        report['owner_has_testflight_access'] = any(m['id'] == testers[0]['id'] for m in members)
        tester = request(token, '/v1/betaTesters/' + testers[0]['id'])['data']
        report['owner_invitation_state'] = tester['attributes'].get('state')
    for build in builds:
        attrs = build['attributes']
        detail = request(token, '/v1/builds/' + build['id'] + '/buildBetaDetail')['data']
        groups = request(token, '/v1/builds/' + build['id'] + '/betaGroups')['data']
        report['builds'].append({'id': build['id'], 'version': attrs['version'],
            'processing_state': attrs['processingState'], 'expired': attrs['expired'],
            'beta_state': detail.get('attributes', {}),
            'groups': [{'id': g['id'], 'name': g['attributes']['name'],
                        'internal': g['attributes']['isInternalGroup']} for g in groups]})
    Path('build/evidence').mkdir(parents=True, exist_ok=True)
    Path('build/evidence/testflight-status.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report), flush=True)
    if builds and all(b['attributes']['processingState'] != 'PROCESSING' for b in builds):
        break
    if time.monotonic() >= deadline:
        break
    time.sleep(30)
