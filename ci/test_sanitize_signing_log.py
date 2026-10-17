"""Run with: python3 -m unittest discover -s ci -p 'test_sanitize_signing_log.py'."""
import base64
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from sanitize_signing_log import load_values, sanitize


KEY = '-----BEGIN PRIVATE KEY-----\nFAKE_KEY_BODY_ALPHA\nFAKE_KEY_BODY_BETA\n-----END PRIVATE KEY-----\n'
ENV = {'ASC_KEY_ID': 'TESTKEY123', 'ASC_ISSUER_ID': 'test-issuer-identifier'}
SCRIPT = Path(__file__).with_name('sanitize_signing_log.py').resolve()


class SigningLogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.key = Path(self.temp.name) / 'AuthKey.p8'
        self.key.write_text(KEY)
        self.values = load_values(self.key, ENV)

    def redact(self, text):
        output = io.StringIO()
        sanitize(io.StringIO(text), output, self.values)
        return output.getvalue()

    def test_xcode_identifiers_and_diagnostic_text(self):
        text = 'xcodebuild -authenticationKeyID TESTKEY123 -authenticationKeyIssuerID test-issuer-identifier\nerror: build failed\n'
        self.assertEqual(self.redact(text), 'xcodebuild -authenticationKeyID [REDACTED] -authenticationKeyIssuerID [REDACTED]\nerror: build failed\n')

    def test_private_key_and_fragments(self):
        for value in (KEY, 'FAKE_KEY_BODY_ALPHA', 'FAKE_KEY_BODY_BETA',
                      'FAKE_KEY_BODY_ALPHAFAKE_KEY_BODY_BETA', KEY.strip().replace('\n', '\\n'),
                      base64.b64encode(KEY.encode()).decode()):
            with self.subTest(value=value):
                output = self.redact(value + '\nafter\n')
                self.assertNotIn('FAKE_KEY_BODY', output)
                self.assertNotIn(base64.b64encode(KEY.encode()).decode(), output)

    def test_unknown_private_key_blocks(self):
        output = self.redact('before\n-----BEGIN RSA PRIVATE KEY-----\nUNKNOWN_BODY\n-----END RSA PRIVATE KEY-----\nafter\n')
        self.assertNotIn('UNKNOWN_BODY', output)
        self.assertTrue(output.startswith('before\n'))
        self.assertTrue(output.endswith('after\n'))

    def test_unterminated_private_key_fails_closed(self):
        self.assertNotIn('UNKNOWN_BODY', self.redact('-----BEGIN PRIVATE KEY-----\nUNKNOWN_BODY\n'))

    def test_bearer_header(self):
        self.assertEqual(self.redact('Authorization: Bearer TEST_TOKEN\n'), 'Authorization: Bearer [REDACTED]\n')

    def test_invalid_configuration_produces_no_stdout(self):
        environment = dict(os.environ, **ENV)
        environment.pop('ASC_KEY_ID')
        result = subprocess.run(['python3', str(SCRIPT), str(self.key)], input='PRIVATE_INPUT\n',
                                text=True, capture_output=True, env=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertNotIn('PRIVATE_INPUT', result.stderr)

    def test_unreadable_key_produces_no_stdout(self):
        result = subprocess.run(['python3', str(SCRIPT), str(self.key) + '.missing'], input='PRIVATE_INPUT\n',
                                text=True, capture_output=True, env=dict(os.environ, **ENV))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_pipeline_redacts_artifact_and_preserves_exit_status(self):
        artifact = Path(self.temp.name) / 'archive.log'
        command = '(printf "TESTKEY123 test-issuer-identifier\\n"; exit "$4") 2>&1 | python3 "$1" "$2" | tee "$3"'
        for status in (0, 65):
            result = subprocess.run(['bash', '-o', 'pipefail', '-c', command, 'test',
                                     str(SCRIPT), str(self.key), str(artifact), str(status)],
                                    text=True, capture_output=True, env=dict(os.environ, **ENV))
            self.assertEqual(result.returncode, status)
            self.assertEqual(artifact.read_text(), '[REDACTED] [REDACTED]\n')
            self.assertEqual(result.stdout, artifact.read_text())

    def test_both_release_logs_are_filtered_before_tee(self):
        release = Path(__file__).with_name('testflight.sh').read_text()
        self.assertIn('set -euo pipefail', release)
        for name in ('archive', 'upload'):
            self.assertIn('2>&1 | python3 ci/sanitize_signing_log.py "$key_path" | tee build/evidence/' + name + '.log', release)


if __name__ == '__main__':
    unittest.main()
