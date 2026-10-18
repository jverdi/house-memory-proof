import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from package_check import check_package, InvalidPackage
from prepare_compatibility import materialize


class EarlierWriterCompatibility(unittest.TestCase):
    def test_genuine_archive_and_narrow_legacy_index_exception(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'old.hxray';evidence=materialize(path);before=path.read_bytes()
            report=check_package(path)
            self.assertTrue(report['passed']);self.assertTrue(report['legacyIndexCRCOnly'])
            self.assertEqual(report['semanticCounts']['features'],217)
            self.assertEqual(path.read_bytes(),before)
            with zipfile.ZipFile(io.BytesIO(before)) as archive:entries={name:archive.read(name) for name in archive.namelist()}
            for missing in ['viewer.html','house.json',next(n for n in entries if n.startswith('assets/'))]:
                bad=dict(entries);manifest=json.loads(bad['manifest.json']);manifest['sha256'].pop(missing)
                bad['manifest.json']=json.dumps(manifest).encode()
                with zipfile.ZipFile(path,'w') as archive:
                    for name,data in bad.items():archive.writestr(name,data)
                with self.assertRaises(InvalidPackage):check_package(path)
            self.assertFalse(evidence['physicalInstallationTest'])


if __name__=='__main__':unittest.main()
