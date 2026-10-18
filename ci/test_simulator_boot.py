"""Exercise the startup-only shell path without an Apple runtime or app launch."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SimulatorBootTests(unittest.TestCase):
    def run_boot(self, already_booted=False, bootstatus_exit=0):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root/'ci').mkdir()
            (root/'bin').mkdir()
            source = Path(__file__).resolve().parent
            for name in ['simulator.sh', 'run_bounded.py']:
                shutil.copy(source/name, root/'ci'/name)
            # Fail on any compile, install, launch or test command. This tests
            # the shell's actual control flow, including error propagation.
            stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['BOOT_LOG'],'a') as f:f.write(json.dumps([name]+args)+'\\n')
if name=='git' and args==['rev-parse','--short=10','HEAD']:
 print('0123456789')
elif name=='xcodebuild' and args==['-version']:
 print('Test toolchain')
elif name=='xcrun' and args==['simctl','list','devices','available','--json']:
 print(json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-26-5':[{'name':'iPhone test','isAvailable':True,'udid':'TEST-PHONE'}]}}))
elif name=='xcrun' and args==['simctl','list','devices','booted']:
 print('TEST-PHONE' if os.environ['BOOT_READY']=='1' else 'No booted device')
elif name=='xcrun' and args==['simctl','boot','TEST-PHONE']:
 pass
elif name=='xcrun' and args==['simctl','bootstatus','TEST-PHONE','-b']:
 sys.exit(int(os.environ['BOOT_RESULT']))
else:
 print('Unexpected command:',name,args,file=sys.stderr)
 sys.exit(98)
'''
            for name in ['git', 'xcodebuild', 'xcrun']:
                path=root/'bin'/name
                path.write_text(stub)
                path.chmod(0o755)
            env=dict(os.environ, PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],
                     BOOT_LOG=str(root/'calls.jsonl'), BOOT_READY='1' if already_booted else '0',
                     BOOT_RESULT=str(bootstatus_exit))
            result=subprocess.run(['bash','ci/simulator.sh','boot'],cwd=root,env=env,
                                  capture_output=True,text=True,timeout=10)
            calls=[json.loads(line) for line in (root/'calls.jsonl').read_text().splitlines()]
            return result,calls

    def test_cold_start_never_compiles_or_launches_app(self):
        result,calls=self.run_boot()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(calls.count(['xcrun','simctl','boot','TEST-PHONE']),1)
        self.assertEqual(calls.count(['xcrun','simctl','bootstatus','TEST-PHONE','-b']),1)

    def test_existing_device_still_verifies_readiness(self):
        result,calls=self.run_boot(already_booted=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertNotIn(['xcrun','simctl','boot','TEST-PHONE'],calls)
        self.assertIn(['xcrun','simctl','bootstatus','TEST-PHONE','-b'],calls)

    def test_platform_startup_failure_is_not_a_pass(self):
        result,calls=self.run_boot(bootstatus_exit=7)
        self.assertEqual(result.returncode,7,result.stdout+result.stderr)
        self.assertEqual(calls[-1],['xcrun','simctl','bootstatus','TEST-PHONE','-b'])


if __name__=='__main__':
    unittest.main()
