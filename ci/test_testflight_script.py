"""Exercise the actual release shell flow with isolated signing/API stand-ins."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ReleaseFlowTests(unittest.TestCase):
    def run_flow(self,mode,fail_distribution=False):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for path in ['ci','tooling/opencv','tooling/solver','tooling/references','build/opencv',
                         'build/ceres','build/apriltag','HouseMemoryProof/IFC','bin']:
                (root/path).mkdir(parents=True,exist_ok=True)
            for name in ['testflight.sh','sanitize_signing_log.py']:
                shutil.copy(Path(__file__).with_name(name),root/'ci'/name)
            (root/'tooling/project.py').write_text('')
            for name in ['prepare-ifc.sh','prepare-simulation.sh','opencv/build.sh','solver/build.sh','references/build.sh']:
                (root/'tooling'/name).write_text('exit 0\n')
            for name in ['opencv/LICENSE','ceres/CERES-LICENSE.txt','ceres/EIGEN-LICENSE.txt','apriltag/APRILTAG-LICENSE.txt']:
                (root/'build'/name).write_text('fixture')
            (root/'ci/upload_preflight.py').write_text("from pathlib import Path\nPath('build/evidence/upload-preflight.json').write_text('{\"upload_needed\":true}')\n")
            (root/'ci/apple_access.py').write_text("from pathlib import Path\nPath('build/evidence/apple-access.json').write_text('{\"app_record_exists\":true}')\n")
            (root/'ci/verify_archive.py').write_text('''import json,sys,os
from pathlib import Path
if '--export-directory' in sys.argv:
    if os.environ.get('FAIL_DISTRIBUTION')=='1':raise SystemExit(19)
    Path('build/evidence/signed-release-manifest.json').write_text(json.dumps(dict(
        releaseIdentityVerified=True,debuggerAttachmentAllowed=False,sourceRevision='abc01234567890',build='9.1')))
''')
            (root/'bin/git').write_text('#!/bin/bash\nif [ "$1" = rev-parse ]; then echo abc0123456; fi\n')
            (root/'bin/xcodebuild').write_text('#!'+sys.executable+'\n'+'''import json,sys,plistlib
from pathlib import Path
args=sys.argv[1:]
if args==['-version']:print('Xcode release-flow fixture');raise SystemExit(0)
event='archive'
if '-exportArchive' in args:
    event=plistlib.loads(Path(args[args.index('-exportOptionsPlist')+1]).read_bytes())['destination']
    if event=='upload' and not Path('build/evidence/signed-release-manifest.json').exists():raise SystemExit(23)
with Path('commands.jsonl').open('a') as output:output.write(json.dumps(event)+'\\n')
''')
            for name in ['git','xcodebuild']:(root/'bin'/name).chmod(0o755)
            environment=dict(os.environ,PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],
                APPLE_TEAM_ID='TESTTEAM01',APP_BUNDLE_ID='org.fixture.house',ASC_KEY_ID='TESTKEY001',
                ASC_ISSUER_ID='test-issuer',ASC_PRIVATE_KEY_P8='-----BEGIN PRIVATE KEY-----\nNOT_A_SIGNING_KEY\n-----END PRIVATE KEY-----',
                GITHUB_RUN_NUMBER='9',GITHUB_RUN_ATTEMPT='1',RUNNER_TEMP=str(root),FAIL_DISTRIBUTION='1' if fail_distribution else '0')
            environment.pop('GITHUB_STEP_SUMMARY',None)
            result=subprocess.run(['bash','ci/testflight.sh',mode],cwd=root,env=environment,capture_output=True,text=True,timeout=30)
            commands=[json.loads(line) for line in (root/'commands.jsonl').read_text().splitlines()] if (root/'commands.jsonl').exists() else []
            report=root/'build/evidence/signing-audit-result.json'
            return result,commands,json.loads(report.read_text()) if report.exists() else None,(root/'build/evidence/upload-preflight.json').exists()

    def test_audit_exports_and_verifies_without_upload_or_upload_preflight(self):
        result,commands,report,preflight=self.run_flow('audit')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(commands,['archive','export']);self.assertFalse(preflight)
        self.assertFalse(report['uploaded']);self.assertNotIn('NOT_A_SIGNING_KEY',result.stdout+result.stderr)

    def test_distribution_failure_prevents_upload(self):
        result,commands,report,preflight=self.run_flow('ship',fail_distribution=True)
        self.assertEqual(result.returncode,19);self.assertEqual(commands,['archive','export'])
        self.assertTrue(preflight);self.assertIsNone(report)

    def test_unknown_mode_stops_before_external_actions(self):
        result,commands,report,preflight=self.run_flow('unknown')
        self.assertEqual(result.returncode,2);self.assertEqual(commands,[])
        self.assertIsNone(report);self.assertFalse(preflight)


if __name__=='__main__':unittest.main()
