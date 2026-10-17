#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/evidence
python3 - <<'PY'
import os, re
required = ['APPLE_TEAM_ID', 'APP_BUNDLE_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY_P8']
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit('Missing CI configuration: ' + ', '.join(missing))
bundle = os.environ['APP_BUNDLE_ID']
if bundle.startswith('com.example.') or not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
    raise SystemExit('APP_BUNDLE_ID must be the registered identifier for the personal Apple team.')
if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['APPLE_TEAM_ID']):
    raise SystemExit('APPLE_TEAM_ID must be the 10-character Apple team identifier.')
if '-----BEGIN PRIVATE KEY-----' not in os.environ['ASC_PRIVATE_KEY_P8']:
    raise SystemExit('ASC_PRIVATE_KEY_P8 must contain the complete multiline Apple .p8 key.')
PY

# Apple signing material remains outside the checkout and evidence artifacts.
key_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/house-proof.XXXXXX")"
trap 'rm -rf "$key_dir"' EXIT
key_path="$key_dir/AuthKey.p8"
umask 077
printf '%s\n' "$ASC_PRIVATE_KEY_P8" > "$key_path"
unset ASC_PRIVATE_KEY_P8
auth=( -allowProvisioningUpdates -authenticationKeyPath "$key_path" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" )
revision="$(git rev-parse --short=10 HEAD)"
build_number="${GITHUB_RUN_NUMBER:-1}.${GITHUB_RUN_ATTEMPT:-1}"
xcodebuild -version | tee build/evidence/xcode-version.txt

# Automatic provisioning requires an authorized team key and suitable Apple
# signing permissions. The first real run must verify those account capabilities.
xcodebuild archive \
  -project HouseMemoryProof.xcodeproj -scheme HouseMemoryProof \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/HouseMemoryProof.xcarchive \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$build_number" PROOF_SOURCE_REVISION="$revision" \
  CODE_SIGN_STYLE=Automatic "${auth[@]}" \
  2>&1 | tee build/evidence/archive.log

python3 - <<'PY'
import os, plistlib
with open('build/ExportOptions.plist', 'wb') as out:
    plistlib.dump({
        'method': 'app-store-connect', 'destination': 'upload',
        'signingStyle': 'automatic', 'teamID': os.environ['APPLE_TEAM_ID'],
        'testFlightInternalTestingOnly': True,
        'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True
    }, out)
PY
xcodebuild -exportArchive \
  -archivePath build/HouseMemoryProof.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist "${auth[@]}" \
  2>&1 | tee build/evidence/upload.log

python3 - "$revision" "$build_number" <<'PY'
import json, os, sys
from pathlib import Path
Path('build/evidence/upload-result.json').write_text(json.dumps({
    'status': 'xcode_upload_command_succeeded',
    'revision': sys.argv[1], 'build': sys.argv[2],
    'bundle_id': os.environ['APP_BUNDLE_ID'],
    'apple_processing_verified': False,
    'internal_tester_access_verified': False,
    'physical_iPhone_verified': False
}, indent=2) + '\n')
PY
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<'SUMMARY'
Apple upload command succeeded. Delivery is not yet proven.

Next verify in App Store Connect that this build finished processing, is
available to the owner's internal testing group, and appears in TestFlight.
Then verify the build number on the physical iPhone after installation.
SUMMARY
fi
