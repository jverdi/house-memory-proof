"""Prepared serial diagnostic runner. Execution still needs the renewed budget.

This file is outside workflow-triggered paths. Preparation tests never call main.
The proposed workflow supplies the outer two-job/40-minute limits; this runner
adds a 2,100-second deadline without retries, parameter sweeps or case replacement.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

import pose_residuals
import prepare

SEEDS = (905771, 683431)
CASES = (("rough",384,()), ("finished",384,("--paired","--staggered","--finished-capture")),
         ("finished",768,("--paired","--staggered","--finished-capture")))
RUNNER_SECONDS = 2100
QUERY_FIELDS = ("accepted","reason","ambiguous","selectedRoomID","selectedSegmentID",
                "worldFromARCamera","inliers","rmsPixels","queryFeatures")
REPORT_FIELDS = ("mapCount","mapFeatures","mapViews","mappingFailures","positiveAccepted",
                 "positiveQueries","negativeQueries","falseAccepts","passed",
                 "candidateQuerySpecificationSHA256","optimizedCameras")


def equivalent(baseline, observed):
    """Exact decisions and numeric outputs; timings and binary hashes differ."""
    for report in (baseline,observed):
        if any(key not in report for key in REPORT_FIELDS) or type(report.get("passed")) is not bool:
            raise ValueError("Incomplete baseline/observer report")
        if not isinstance(report.get("queries"),list) or not report["queries"] or any(type(q.get("accepted")) is not bool for q in report["queries"]):
            raise ValueError("Incomplete query outcomes")
    a = pose_residuals.unique(baseline["queries"],"image")
    b = pose_residuals.unique(observed["queries"],"image")
    if set(a) != set(b):
        return False
    if any(baseline.get(key) != observed.get(key) for key in REPORT_FIELDS):
        return False
    return all({key:a[name].get(key) for key in QUERY_FIELDS} ==
               {key:b[name].get(key) for key in QUERY_FIELDS} for name in a)


def declare(seed):
    if seed not in SEEDS:
        raise ValueError("Only the two disclosed development layouts are allowed")
    return [dict(stage=stage,width=width,status="not_started",diagnosticComplete=False,
                 decisionEquivalent=False,originalGatePassed=False) for stage,width,_ in CASES]


class Deadline:
    def __init__(self, seconds=RUNNER_SECONDS, clock=time.monotonic):
        self.clock = clock
        self.end = clock()+seconds

    def allowance(self, maximum):
        remaining = self.end-self.clock()
        if remaining <= 0:
            raise TimeoutError("Declared diagnostic deadline exhausted")
        return min(maximum,remaining)

    def run(self, command, log, maximum):
        timeout = self.allowance(maximum)
        with log.open("wb") as output:
            process = subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
            try:
                return process.wait(timeout=timeout)
            except BaseException:
                try:
                    os.killpg(process.pid,signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()


def write_summary(path,summary):
    summary["diagnosticComplete"] = len(summary["cases"]) == 3 and all(c["diagnosticComplete"] for c in summary["cases"])
    summary["originalGatesPassed"] = summary["diagnosticComplete"] and all(c["originalGatePassed"] for c in summary["cases"])
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed",type=int,choices=SEEDS,required=True)
    args = parser.parse_args()
    if os.environ.get("GITHUB_RUN_ATTEMPT") != "1":
        raise ValueError("Automatic or manual reruns are outside this one-run budget")
    root = pose_residuals.ROOT
    os.chdir(root)
    source = subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()
    if not re.fullmatch("[0-9a-f]{40}",source) or source != os.environ.get("GITHUB_SHA"):
        raise ValueError("Runner source does not match the reviewed workflow source")
    if subprocess.check_output(["git","status","--porcelain","--untracked-files=no"],text=True).strip():
        raise ValueError("Use a clean isolated host checkout")
    private = root/"build/pose-trace-private"
    public = root/"build/pose-trace-aggregates"
    private.mkdir(parents=True,exist_ok=False)
    public.mkdir(parents=True,exist_ok=False)
    summary = dict(schema=1,source=source,seed=args.seed,runnerSeconds=RUNNER_SECONDS,
                   cases=declare(args.seed),physicalQualification=False,precisionEnabled=False,
                   protectedLayoutsDrawn=False,executionRetryAllowed=False)
    summary_path = public/"summary.json"
    write_summary(summary_path,summary)
    deadline = Deadline()
    originals = None
    try:
        if deadline.run(["bash","tooling/opencv/build-host.sh"],private/"baseline-build.log",600) != 0:
            raise RuntimeError("Baseline host build failed")
        baseline = private/"baseline-replay"
        baseline.write_bytes((root/"build/vision-replay").read_bytes());baseline.chmod(0o700)
        summary["baselineBinarySHA256"] = digest(baseline)
        originals, changed = prepare.prepare(root)
        import difflib
        patch = "".join("".join(difflib.unified_diff(originals[name].splitlines(True),changed[name].splitlines(True),
                         fromfile="a/"+name,tofile="b/"+name)) for name in originals)
        summary["observerPatchSHA256"] = hashlib.sha256(patch.encode()).hexdigest()
        for name,text in changed.items():
            (root/name).write_text(text)
        if deadline.run(["bash","tooling/opencv/build-host.sh"],private/"observer-build.log",600) != 0:
            raise RuntimeError("Observer host build failed")
        observed = root/"build/vision-replay"
        summary["observerBinarySHA256"] = digest(observed)
        write_summary(summary_path,summary)
        for index,(stage,width,flags) in enumerate(CASES):
            case = summary["cases"][index]
            case["status"] = "started"
            write_summary(summary_path,summary)
            fixture = private/(stage+"-"+str(width))
            try:
                if deadline.run([sys.executable,"tooling/simulation/house_layout_fixture.py",str(fixture),
                                 "--seed",str(args.seed),"--width",str(width),*flags],private/(fixture.name+"-generate.log"),600) != 0:
                    raise RuntimeError("Fixture generation failed")
                reports = []
                for kind,executable in (("baseline",baseline),("observed",observed)):
                    result = private/(fixture.name+"-"+kind+".json")
                    command = [sys.executable,"tooling/simulation/replay_fixture.py","--executable",str(executable),
                               "--fixture",str(fixture),"--output",str(result),"--refine","--bundle","--house"]
                    if kind == "observed":
                        command.append("--pose-trace")
                    exit_code = deadline.run(command,private/(fixture.name+"-"+kind+".log"),660)
                    case[kind+"ExitCode"] = exit_code
                    report = pose_residuals.load_json(result)
                    # Exit 1 retains an original failed accuracy/availability
                    # gate, but a rejected/crashed candidate is incomplete.
                    if exit_code not in (0,1) or report.get("candidateRejected") or not isinstance(report.get("queries"),list):
                        raise RuntimeError("Incomplete candidate execution")
                    positive, negative = (12,8) if stage == "rough" else (20,20)
                    if (report.get("positiveQueries"),report.get("negativeQueries"),len(report["queries"])) != (positive,negative,positive+negative):
                        raise ValueError("Declared case denominator changed")
                    reports.append(report)
                case["decisionEquivalent"] = equivalent(*reports)
                if not case["decisionEquivalent"]:
                    raise ValueError("Observer changed a candidate output")
                # Residual evaluation has its own child-process deadline too;
                # it cannot consume the remainder of the managed job unbounded.
                metrics_path = private/(fixture.name+"-metrics.json")
                command = [sys.executable,str(Path(__file__).with_name("pose_residuals.py")),str(result),str(metrics_path),"--stage",stage]
                if deadline.run(command,private/(fixture.name+"-metrics.log"),180) != 0:
                    raise RuntimeError("Residual evaluator incomplete")
                metrics = pose_residuals.load_json(metrics_path)
                if set(metrics) != pose_residuals.PUBLIC_KEYS or metrics.get("complete") is not True:
                    raise ValueError("Evaluator aggregate contract differs")
                case["residuals"] = metrics
                case["originalGatePassed"] = reports[1]["passed"] is True
                case["diagnosticComplete"] = True
                case["status"] = "complete"
            except Exception as error:
                case["status"] = "incomplete"
                case["errorClass"] = type(error).__name__
            write_summary(summary_path,summary)
            print(json.dumps({key:case[key] for key in ("stage","width","status","diagnosticComplete","originalGatePassed")}),flush=True)
    except Exception as error:
        summary["preparationErrorClass"] = type(error).__name__
    finally:
        if originals is not None:
            for name,text in originals.items():
                (root/name).write_text(text)
        write_summary(summary_path,summary)
    return 0 if summary["diagnosticComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
