#!/usr/bin/env python3
"""Retain every UI case result across XCTest runner restarts."""
import argparse
import json
from pathlib import Path
import re


def summarize(source, log, exit_code):
    expected = sorted(set(re.findall(r'\bfunc\s+(test\w+)\s*\(', source)))
    results = {}
    for name, status, seconds in re.findall(
        r"Test Case '-\[[^\]]+ (test\w+)\]' (passed|failed|skipped) \(([0-9.]+) seconds\)", log
    ):
        results.setdefault(name, []).append(dict(status=status, seconds=float(seconds)))
    failed = sorted(name for name, attempts in results.items()
                    if any(a['status'] != 'passed' for a in attempts))
    missing = sorted(set(expected) - results.keys())
    unexpected = sorted(results.keys() - set(expected))
    repeated = sorted(name for name, attempts in results.items() if len(attempts) != 1)
    passed = sorted(name for name, attempts in results.items()
                    if len(attempts) == 1 and attempts[0]['status'] == 'passed')
    return dict(passed=bool(expected) and exit_code == 0 and not
                (failed or missing or unexpected or repeated),
                runnerExitCode=exit_code, expected=expected, passedCases=passed,
                failedCases=failed, missingCases=missing, unexpectedCases=unexpected,
                repeatedCases=repeated, results=results,
                note='Case-level results retain failures across runner restarts; trailing suite totals are not used.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--log', required=True, type=Path)
    parser.add_argument('--exit-code', required=True, type=int)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = summarize(args.source.read_text(), args.log.read_text(errors='replace'), args.exit_code)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"UI cases: {len(result['passedCases'])}/{len(result['expected'])} passed; complete={result['passed']}")
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
