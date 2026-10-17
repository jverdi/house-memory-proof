"""Verify Apple API access and register only this proof app's bundle ID.

Secrets and bearer tokens never appear in output or artifacts. Requires only
Python's standard library and OpenSSL, both supplied by the hosted runner.
"""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def b64(data):
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def jose_signature(der):
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError('Invalid ECDSA signature encoding')
    offset, values = 2, []
    for _ in range(2):
        if der[offset] != 2:
            raise ValueError('Invalid ECDSA integer')
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length]
        if not value or len(value) != length or value[0] & 0x80:
            raise ValueError('Invalid ECDSA integer length or sign')
        values.append(int.from_bytes(value, 'big').to_bytes(32, 'big'))
        offset += 2 + length
    if offset != len(der):
        raise ValueError('Unexpected ECDSA signature suffix')
    return b''.join(values)


def make_token():
    names = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_P8']
    missing = [name for name in names if not os.environ.get(name, '').strip()]
    if missing:
        raise RuntimeError('Missing GitHub secrets: ' + ', '.join(missing))
    header = {'alg': 'ES256', 'kid': os.environ['ASC_KEY_ID'].strip(), 'typ': 'JWT'}
    now = int(time.time())
    claims = {'iss': os.environ['ASC_ISSUER_ID'].strip(), 'iat': now,
              'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    payload = '.'.join(b64(json.dumps(x, separators=(',', ':')).encode())
                       for x in [header, claims]).encode()
    with tempfile.TemporaryDirectory(prefix='apple-auth-') as folder:
        key = Path(folder) / 'AuthKey.p8'
        key.write_text(os.environ['ASC_PRIVATE_KEY_P8'].strip() + '\n')
        key.chmod(0o600)
        signed = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(key)],
                                input=payload, capture_output=True)
        if signed.returncode:
            raise RuntimeError('Private key could not sign a request. Check the complete multiline .p8 secret.')
    return payload.decode() + '.' + b64(jose_signature(signed.stdout))


def request(token, path, body=None):
    url = 'https://api.appstoreconnect.apple.com' + path
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={'Authorization': 'Bearer ' + token,
                                          'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # Report only status and Apple's enum-style error codes, never request
        # headers, tokens, credentials, or arbitrary server response bodies.
        try:
            errors = json.loads(error.read()).get('errors', [])
            codes = [x.get('code', '') for x in errors]
            codes = [x for x in codes if re.fullmatch(r'[A-Z0-9_.-]+', x)]
        except (ValueError, AttributeError):
            codes = []
        raise RuntimeError(f'Apple API HTTP {error.code}: ' + ', '.join(codes)) from None


def main():
    token = make_token()
    bundle = os.environ.get('APP_BUNDLE_ID') or 'com.jverdi.housememoryproof'
    query = urllib.parse.urlencode({'filter[identifier]': bundle, 'limit': 2})
    bundles = request(token, '/v1/bundleIds?' + query)['data']
    created = False
    if not bundles:
        result = request(token, '/v1/bundleIds', {'data': {'type': 'bundleIds',
            'attributes': {'identifier': bundle, 'name': 'House Memory Proof', 'platform': 'IOS'}}})
        bundles = [result['data']]
        created = True
    if len(bundles) != 1:
        raise RuntimeError('Expected one matching bundle ID')
    certs = request(token, '/v1/certificates?limit=200')
    teams = set()
    for cert in certs['data']:
        content = cert.get('attributes', {}).get('certificateContent')
        if not content:
            continue
        parsed = subprocess.run(['openssl', 'x509', '-inform', 'DER', '-noout',
                                 '-subject', '-nameopt', 'RFC2253'],
                                input=base64.b64decode(content), capture_output=True)
        if parsed.returncode == 0:
            teams.update(re.findall(r'(?:^|,)OU=([A-Z0-9]{10})(?:,|$)', parsed.stdout.decode()))
    apps = request(token, '/v1/apps?' + urllib.parse.urlencode({'filter[bundleId]': bundle, 'limit': 2}))['data']
    configured_team = os.environ.get('APPLE_TEAM_ID', '').strip()
    team = configured_team or (next(iter(teams)) if len(teams) == 1 else None)
    if configured_team and teams and configured_team not in teams:
        raise RuntimeError('Configured Apple team does not match signing certificates')
    report = {'apple_api_authentication': 'passed', 'bundle_id': bundle,
              'bundle_registered': True, 'bundle_created_this_run': created,
              'apple_team_id': team, 'team_source': 'configured' if configured_team else 'certificate_subject',
              'app_record_exists': len(apps) == 1,
              'app_id': apps[0]['id'] if len(apps) == 1 else None,
              'signing_tested': False, 'testflight_uploaded': False}
    Path('build/evidence').mkdir(parents=True, exist_ok=True)
    Path('build/evidence/apple-access.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, urllib.error.URLError) as error:
        raise SystemExit(str(error)) from None
