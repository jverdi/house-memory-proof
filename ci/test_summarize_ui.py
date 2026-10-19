import unittest
from summarize_ui import summarize


class InterfaceEvidenceTests(unittest.TestCase):
    source = 'func testFirst() {}\n@MainActor func testSecond() throws {}'

    def line(self, name, status='passed'):
        return f"Test Case '-[App.Smoke {name}]' {status} (1.5 seconds).\n"

    def test_complete_success(self):
        result = summarize(self.source, self.line('testFirst') + self.line('testSecond'), 0)
        self.assertTrue(result['passed'])
        self.assertEqual(result['passedCases'], ['testFirst', 'testSecond'])

    def test_restarted_runner_does_not_erase_failure(self):
        log = self.line('testFirst', 'failed') + self.line('testSecond')
        log += 'Executed 1 test, with 0 failures\nExecuted 0 tests, with 0 failures\n'
        result = summarize(self.source, log, 65)
        self.assertFalse(result['passed'])
        self.assertEqual(result['failedCases'], ['testFirst'])
        self.assertEqual(result['passedCases'], ['testSecond'])

    def test_incomplete_with_success_exit_is_not_pass(self):
        result = summarize(self.source, self.line('testFirst'), 0)
        self.assertFalse(result['passed'])
        self.assertEqual(result['missingCases'], ['testSecond'])

    def test_retry_does_not_hide_failure(self):
        log = self.line('testFirst', 'failed') + self.line('testFirst') + self.line('testSecond')
        result = summarize(self.source, log, 0)
        self.assertFalse(result['passed'])
        self.assertEqual(result['repeatedCases'], ['testFirst'])
        self.assertEqual(result['failedCases'], ['testFirst'])

    def test_unexpected_and_skipped_cases_refused(self):
        log = self.line('testFirst') + self.line('testSecond', 'skipped') + self.line('testOther')
        result = summarize(self.source, log, 0)
        self.assertFalse(result['passed'])
        self.assertEqual(result['unexpectedCases'], ['testOther'])
        self.assertEqual(result['failedCases'], ['testSecond'])

    def test_process_failure_and_empty_suite_refused(self):
        log = self.line('testFirst') + self.line('testSecond')
        self.assertFalse(summarize(self.source, log, 124)['passed'])
        self.assertFalse(summarize('', '', 0)['passed'])


if __name__ == '__main__':
    unittest.main()
