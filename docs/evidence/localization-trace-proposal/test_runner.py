"""Runner contract tests only. No build, subprocess, layout or replay is run."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run_diagnostic as runner


def report():
    value = {key:0 for key in runner.REPORT_FIELDS}
    value.update(passed=False,queries=[dict(image="private-query",accepted=True,inliers=40,
                                          worldFromARCamera=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])])
    return value


class RunnerTests(unittest.TestCase):
    def test_only_two_seeds_and_declared_three_cases(self):
        for seed in runner.SEEDS:
            cases = runner.declare(seed)
            self.assertEqual([(c["stage"],c["width"]) for c in cases],[("rough",384),("finished",384),("finished",768)])
            self.assertTrue(all(c["status"] == "not_started" and not c["diagnosticComplete"] for c in cases))
        with self.assertRaises(ValueError):runner.declare(999)

    def test_deadline_never_extends_or_retries(self):
        now = [0]
        deadline = runner.Deadline(clock=lambda:now[0])
        self.assertEqual(deadline.allowance(600),600)
        now[0] = runner.RUNNER_SECONDS-10
        self.assertEqual(deadline.allowance(600),10)
        now[0] += 10
        with self.assertRaises(TimeoutError):deadline.allowance(1)

    def test_exact_decisions_including_rejections_and_failed_gate(self):
        baseline = report();observed=copy.deepcopy(baseline)
        baseline["seconds"]=1;observed["seconds"]=2
        self.assertTrue(runner.equivalent(baseline,observed))
        for key,value in (("accepted",False),("inliers",39),("worldFromARCamera",[0]*16)):
            changed=copy.deepcopy(observed);changed["queries"][0][key]=value
            self.assertFalse(runner.equivalent(baseline,changed))
        observed["passed"]=True
        self.assertFalse(runner.equivalent(baseline,observed))

    def test_missing_duplicate_or_partial_reports_fail(self):
        baseline=report()
        for fault in ("field","duplicate","outcome"):
            changed=copy.deepcopy(baseline)
            if fault=="field":del changed["mapCount"]
            elif fault=="duplicate":changed["queries"]*=2
            else:del changed["queries"][0]["accepted"]
            with self.assertRaises(ValueError):runner.equivalent(baseline,changed)

    def test_incomplete_and_failed_gates_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"summary.json"
            summary=dict(cases=runner.declare(runner.SEEDS[0]))
            summary["cases"][0].update(diagnosticComplete=True,originalGatePassed=True)
            runner.write_summary(path,summary)
            self.assertFalse(json.loads(path.read_text())["diagnosticComplete"])
            for case in summary["cases"]:case["diagnosticComplete"]=True
            runner.write_summary(path,summary)
            result=json.loads(path.read_text())
            self.assertTrue(result["diagnosticComplete"])
            self.assertFalse(result["originalGatesPassed"])

    def test_rerun_rejected_before_any_checkout_or_process(self):
        with patch.dict(os.environ,{"GITHUB_RUN_ATTEMPT":"2"}),patch("sys.argv",["runner","--seed","905771"]),patch("subprocess.check_output") as process:
            with self.assertRaises(ValueError):runner.main()
            process.assert_not_called()

    def test_workflow_is_disabled_review_artifact_with_bounded_allowlist(self):
        path=Path(__file__).with_name("workflow.yml.txt")
        text=path.read_text()
        self.assertNotIn(".github/workflows",str(path))
        self.assertIn("if: ${{ false }}",text)
        self.assertIn("max-parallel: 1",text)
        self.assertIn("timeout-minutes: 40",text)
        self.assertIn("seed: [905771, 683431]",text)
        self.assertIn("path: build/pose-trace-aggregates/summary.json",text)
        self.assertNotIn("path: build/pose-trace-private",text)
        self.assertNotIn("push:",text)


if __name__ == "__main__":
    unittest.main()
