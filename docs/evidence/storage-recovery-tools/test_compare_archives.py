import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import zipfile
from compare_archives import compare
from package_check import InvalidPackage
from prepare_compatibility import materialize


class ArchiveRecoveryComparison(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.before = Path(self.folder.name) / 'before.hxray'
        self.after = Path(self.folder.name) / 'after.hxray'
        materialize(self.before)

    def rewritten(self, change):
        with zipfile.ZipFile(self.before) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        house = json.loads(entries['house.json'])
        change(house)
        entries['house.json'] = json.dumps(house).encode()
        manifest = json.loads(entries['manifest.json'])
        manifest['sha256']['house.json'] = hashlib.sha256(entries['house.json']).hexdigest()
        entries['manifest.json'] = json.dumps(manifest).encode()
        with zipfile.ZipFile(self.after, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)

    def test_identical_contents_not_archive_encoding_or_install_claim(self):
        self.rewritten(lambda h: None)
        report = compare(self.before, self.after)
        self.assertTrue(report['passed'])
        self.assertNotEqual(report['beforeSHA256'], report['afterSHA256'])
        self.assertFalse(report['actualSignedUpdateVerified'])
        self.assertFalse(report['actualProviderRecoveryVerified'])

    def test_notes_and_identity_changes_are_not_silent_update_success(self):
        for key, value in [('notes', 'Changed'), ('id', str(uuid.uuid4())), ('revision', 100)]:
            with self.subTest(key=key):
                self.rewritten(lambda h: h.update({key: value}))
                self.assertFalse(compare(self.before, self.after)['passed'])

    def test_restore_only_allows_deliberate_project_identity_changes(self):
        def restored(h):
            h.update(id=str(uuid.uuid4()), name=h['name'] + ' · restored', revision=0)
        self.rewritten(restored)
        self.assertTrue(compare(self.before, self.after, 'restore')['passed'])
        self.assertFalse(compare(self.before, self.after, 'update')['passed'])
        self.rewritten(lambda h: (restored(h), h.update(notes='Lost original notes')))
        self.assertFalse(compare(self.before, self.after, 'restore')['passed'])

    def test_corrupt_archives_and_unchanged_restore_identity_fail(self):
        self.rewritten(lambda h: None)
        self.assertFalse(compare(self.before, self.after, 'restore')['passed'])
        self.after.write_bytes(b'not an archive')
        with self.assertRaises((InvalidPackage, zipfile.BadZipFile)):
            compare(self.before, self.after)

    def test_comparison_does_not_modify_inputs_or_publish_names(self):
        self.rewritten(lambda h: None)
        before, after = self.before.read_bytes(), self.after.read_bytes()
        report = compare(self.before, self.after)
        self.assertEqual(self.before.read_bytes(), before)
        self.assertEqual(self.after.read_bytes(), after)
        self.assertNotIn('name', report)
        self.assertNotIn('id', report)
        self.assertNotIn('assets', report)


if __name__ == '__main__':
    unittest.main()
