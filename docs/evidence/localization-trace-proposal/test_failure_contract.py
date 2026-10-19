import json
import unittest
from failure_contract import PREFIX, read_failure, validate_failure
import prepare
from pathlib import Path


def failure():
    return dict(schema=1, phase='trace-finalization', kind='record-serialization', domain='other', code=1)


class FailureContractTests(unittest.TestCase):
    def test_only_controlled_fields_survive_private_stderr(self):
        private='raw image path /private/secret.jpg and private pose [1,2,3]'
        result=read_failure(private+'\n'+PREFIX+json.dumps(failure())+'\n'+private)
        self.assertEqual(result,failure())
        self.assertNotIn('private',json.dumps(result))

    def test_unknown_duplicate_nonfinite_and_private_fields_are_not_republished(self):
        for key,value in [('phase','/private/file'),('kind',['unknown']),('domain',None),('code',True),('code',100001),('schema',False),('path','/private/file')]:
            row=failure();row[key]=value
            with self.subTest(key=key):
                self.assertIsNone(validate_failure(row))
                self.assertIsNone(read_failure(PREFIX+json.dumps(row)))
        for text in [PREFIX+'{}',PREFIX+'NaN',PREFIX+'[]',PREFIX+'7',PREFIX+'null',
                     PREFIX+json.dumps(failure())+'\n'+PREFIX+json.dumps(failure()),
                     PREFIX+json.dumps(failure()).replace('"schema": 1','"schema": 1, "schema": 1'),
                     PREFIX+' '*1024,'x'*1048577]:
            self.assertIsNone(read_failure(text))

    def test_no_marker_is_an_explicit_unknown(self):
        for text in ['',None,'fatal error: /private/path', 'prefix '+PREFIX+json.dumps(failure())]:
            self.assertIsNone(read_failure(text))

    def test_isolated_harness_parses_before_stderr_truncation(self):
        root=Path(__file__).resolve().parents[3]
        original,changed=prepare.prepare(root)
        wrapper=changed['tooling/simulation/replay_fixture.py']
        compile(wrapper,'instrumented-private-harness.py','exec')
        self.assertIn('observerFailure=read_failure(result.stderr),error=result.stderr[-5000:]',wrapper)
        native=changed['tooling/simulation/VisionReplay.swift']
        self.assertIn('PoseTraceFailure.emit(error)',native)
        self.assertIn('"kind":kind',native)
        self.assertNotIn('"message":error.localizedDescription',native)
        self.assertIn('failureKind=operation',native)
        self.assertEqual((root/'tooling/simulation/VisionReplay.swift').read_text(),original['tooling/simulation/VisionReplay.swift'])


if __name__ == '__main__':
    unittest.main()
