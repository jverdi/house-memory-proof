import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import struct
import unittest
from unittest.mock import patch
from hm_commands import stage_scene, tour, reconstruct, doctor
from test_package_check import fixture, archive

ROOT=Path(__file__).resolve().parents[1]


class CommandContracts(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def cli(self,*arguments):
        return subprocess.run([sys.executable,str(ROOT/'tooling/hm'),*map(str,arguments)],capture_output=True,text=True)

    def test_doctor_never_provisions(self):
        result=self.cli('doctor');self.assertEqual(result.returncode,0)
        self.assertFalse(json.loads(result.stdout)['provisioningPerformed'])

    def test_live_doctor_requires_both_account_reads_without_provisioning(self):
        sys.path.insert(0,str(ROOT/'ci'))
        snapshot=dict(checkedUTC='2026-10-18T03:00:00+00:00',apple=dict(readAccessVerified=True,builds=[]),github=dict(readAccessVerified=True,runs=[]))
        with patch('release_health.collect_live',return_value=snapshot):
            result=doctor(live=True)
        self.assertTrue(result['passed']);self.assertTrue(result['accountAccessVerified'])
        self.assertFalse(result['provisioningPerformed'])
        snapshot['apple']=dict(readAccessVerified=False,error='Apple read unavailable: RuntimeError')
        with patch('release_health.collect_live',return_value=snapshot):
            result=doctor(live=True)
        self.assertFalse(result['passed']);self.assertFalse(result['accountAccessVerified'])
        snapshot['apple']['networkAttempted']=False
        snapshot['github']=dict(readAccessVerified=False,networkAttempted=False,runs=[])
        with patch('release_health.collect_live',return_value=snapshot):
            result=doctor(live=True)
        self.assertFalse(result['networkChecked']);self.assertTrue(result['networkChecksRequested'])

    def test_export_command_checks_real_package_and_reports_failure(self):
        house,parts=fixture();path=self.root/'house.hxray';archive(path,house,parts)
        result=self.cli('export-check','--package',path)
        self.assertEqual(result.returncode,0);self.assertTrue(json.loads(result.stdout)['jsonRoundTripPassed'])
        archive(path,house,parts,lambda p:p.__setitem__('house.json',b'{}'))
        result=self.cli('export-check','--package',path)
        self.assertEqual(result.returncode,1);self.assertFalse(json.loads(result.stdout)['passed'])

    def test_validation_report_cannot_overwrite_its_input(self):
        house,parts=fixture();path=self.root/'house.hxray';archive(path,house,parts)
        before=path.read_bytes()
        result=self.cli('export-check','--package',path,'--output',path)
        self.assertEqual(result.returncode,1);self.assertEqual(path.read_bytes(),before)
        path.write_bytes(b'broken package');report=self.root/'failure.json'
        result=self.cli('export-check','--package',path,'--output',report)
        self.assertEqual(result.returncode,1);self.assertFalse(json.loads(report.read_text())['passed'])

    def test_staging_preserves_metadata_and_every_original(self):
        house,parts=fixture();path=self.root/'house.hxray';archive(path,house,parts)
        original=path.read_bytes();destination=self.root/'staged'
        digest=stage_scene(path,destination)
        self.assertEqual(digest,hashlib.sha256((destination/'house.json').read_bytes()).hexdigest())
        self.assertEqual(json.loads((destination/'house.json').read_text()),house)
        self.assertEqual(path.read_bytes(),original)
        for name,raw in parts.items():self.assertEqual((destination/name).read_bytes(),raw)

    def test_existing_outputs_survive_failed_commands(self):
        target=self.root/'original.xyz';target.write_bytes(b'preserve this artifact')
        result=self.cli('reconstruct','--bundle',self.root/'missing','--output',target)
        self.assertEqual(result.returncode,1);self.assertEqual(target.read_bytes(),b'preserve this artifact')
        result=self.cli('simulate','--output',self.root)
        self.assertEqual(result.returncode,1);self.assertEqual(target.read_bytes(),b'preserve this artifact')

    def test_tour_refuses_missing_native_runtime_without_installing_anything(self):
        with patch('hm_commands.platform.system',return_value='Linux'),patch('hm_commands.subprocess.run') as process:
            with self.assertRaisesRegex(ValueError,'production app'):tour(self.root,'overview',20,'explicit-device','app',self.root/'out')
            process.assert_not_called()

    def test_unavailable_viewpoints_preserve_the_native_exclusion_report(self):
        house,parts=fixture();source=self.root/'source.hxray';archive(source,house,parts)
        container=self.root/'simulator';container.mkdir();output=self.root/'storyboard'
        def process(arguments,**_):
            if 'get_app_container' in arguments:
                return subprocess.CompletedProcess(arguments,0,stdout=str(container)+'\n')
            if 'launch' in arguments:
                folder=container/'Documents/HouseXray/developer-commands'/arguments[-1]
                digest=hashlib.sha256((folder/'input/house.json').read_bytes()).hexdigest()
                (folder/'output').mkdir()
                (folder/'output/tour.json').write_text(json.dumps(dict(shots=[],excluded=['No captured viewpoint'])))
                (folder/'result.json').write_text(json.dumps(dict(passed=False,houseSHA256=digest,excluded=['No captured viewpoint'],error='No supported tour viewpoint')))
            return subprocess.CompletedProcess(arguments,0,stdout='')
        with patch('hm_commands.platform.system',return_value='Darwin'),patch('hm_commands.shutil.which',return_value='/usr/bin/xcrun'),patch('hm_commands.subprocess.run',side_effect=process):
            result=tour(source,'overview',20,'chosen-simulator','app',output)
        self.assertFalse(result['passed'])
        self.assertEqual(json.loads((output/'tour.json').read_text())['excluded'],['No captured viewpoint'])
        self.assertEqual(list((container/'Documents/HouseXray/developer-commands').iterdir()),[])

    def test_partial_native_reconstruction_retains_package_and_failure(self):
        house,parts=fixture();source=self.root/'source.hxray';archive(source,house,parts)
        output=self.root/'reconstruction';native=self.root/'native-output';native.mkdir()
        archive(native/'reconstruction.hxray',house,parts)
        result=dict(passed=False,completed=True,archive='reconstruction.hxray',sessions=[dict(passed=False,error='Insufficient overlap')])
        from contextlib import contextmanager
        @contextmanager
        def response(*_):yield result,native,'digest'
        with patch('hm_commands.native_request',response):
            report=reconstruct(source,'complete',None,'selected','app',output)
        self.assertFalse(report['passed']);self.assertTrue(report['independentArchiveCheck']['passed'])
        self.assertTrue((output/'reconstruction.hxray').is_file())
        self.assertFalse(json.loads((output/'result.json').read_text())['passed'])

    def test_image_bundle_requires_explicit_native_runtime(self):
        result=self.cli('reconstruct','--bundle',self.root/'capture.hxray','--output',self.root/'output')
        self.assertEqual(result.returncode,1)
        self.assertIn('requires --simulator',json.loads(result.stdout)['error'])

    def test_glb_reader_refuses_bad_header_and_external_resources(self):
        path=self.root/'model.glb'
        path.write_bytes(b'not a model'*4)
        result=self.cli('export-check','--package',path)
        self.assertEqual(result.returncode,1)
        self.assertIn('Invalid GLB header',json.loads(result.stdout)['error'])
        for collection in ['buffers','images']:
            payload=json.dumps(dict(asset=dict(version='2.0'),**{collection:[dict(uri='https://example.invalid/private')]})).encode()
            payload+=b' '*((-len(payload))%4)
            raw=struct.pack('<IIIII',0x46546c67,2,20+len(payload),len(payload),0x4e4f534a)+payload
            path.write_bytes(raw)
            result=self.cli('export-check','--package',path)
            report=json.loads(result.stdout)
            self.assertEqual(result.returncode,1)
            self.assertFalse(report['externalResourcesLoaded'])
            self.assertIn('Self-contained GLB required',report['error'])
            self.assertEqual(path.read_bytes(),raw)


if __name__=='__main__':unittest.main()
