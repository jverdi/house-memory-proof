"""Synthetic protocol/preparation checks only; no image or localization run."""
import copy
import io
import json
from pathlib import Path
import unittest

import prepare
import trace_contract as contract


def records():
    source = "00000000-0000-0000-0000-000000000001"
    return [
        dict(type="header", schema=1, coordinateFrame="centroid-local-opencv",
             limitBytes=contract.MAX_BYTES, limitSolves=contract.MAX_SOLVES),
        dict(type="begin", query="opaque-1.png"),
        dict(type="solve", query="opaque-1.png", kind="individual", sourceIDs=[source],
             queryIndices=list(range(30)), xyz=[1.0, 2.0, 3.0]*30, xy=[5.0, 6.0]*30,
             width=384, height=256, intrinsics=[1.0,0,0,0,1.0,0,0,0,1.0], status=1,
             matrix=[1.0,0,0,0,0,1.0,0,0,0,0,1.0,0,0,0,0,1.0], rejection=0,
             inlierCount=30, inlierIndices=list(range(30)), observerReadSucceeded=True,
             state=[7.0]+[0.0]*15),
        dict(type="end", query="opaque-1.png", accepted=True, reason="evaluated"),
        dict(type="begin", query="opaque-2.png"),
        dict(type="end", query="opaque-2.png", accepted=False, reason="no-map"),
        dict(type="footer", queries=2, solves=1, complete=True),
    ]


def encoded(rows):
    return b"".join(json.dumps(dict(row, sequence=i)).encode()+b"\n" for i,row in enumerate(rows))


class TraceContractTests(unittest.TestCase):
    def rejected(self, rows):
        with self.assertRaises(ValueError):
            contract.inspect(io.BytesIO(encoded(rows)), 2)

    def test_all_query_outcomes_and_public_allowlist(self):
        result = contract.inspect(io.BytesIO(encoded(records())), 2)
        self.assertEqual((result["queries"], result["acceptedQueries"], result["abstainedQueries"]), (2,1,1))
        self.assertEqual(set(result), contract.PUBLIC_KEYS)
        self.assertNotIn(b"opaque", json.dumps(result).encode())
        self.assertNotIn(b"00000000", json.dumps(result).encode())

    def test_rejected_solve_retains_selection_without_returned_pose(self):
        rows = records(); rows[2].update(status=0, rejection=6, matrix=[])
        rows[3]["accepted"] = False
        result = contract.inspect(io.BytesIO(encoded(rows)), 2)
        self.assertEqual(result["selectedInliers"], 30)
        self.assertEqual(result["acceptedQueries"], 0)

    def test_no_ransac_selection(self):
        rows = records(); rows[2].update(status=0, rejection=1, matrix=[], inlierCount=0, inlierIndices=[], state=[1.0]+[0.0]*15)
        rows[3]["accepted"] = False
        self.assertEqual(contract.inspect(io.BytesIO(encoded(rows)), 2)["selectedInliers"], 0)

    def test_truncated_and_trailing_data(self):
        raw = encoded(records())
        for data in (raw[:-1], encoded(records()[:-1]), raw+b"{}\n"):
            with self.subTest(data_length=len(data)), self.assertRaises(ValueError):
                contract.inspect(io.BytesIO(data), 2)

    def test_denominator_and_order(self):
        with self.assertRaises(ValueError):
            contract.inspect(io.BytesIO(encoded(records())), 3)
        rows = records(); rows[4]["query"] = rows[1]["query"]; self.rejected(rows)
        rows = records(); rows[2]["query"] = "opaque-2.png"; self.rejected(rows)
        rows = records(); rows[2], rows[3] = rows[3], rows[2]; self.rejected(rows)

    def test_invalid_selection_and_input(self):
        for key,value in [("inlierIndices", [30]*30), ("inlierCount",29), ("queryIndices",[0]*30),
                          ("xyz",[float("nan")]*90), ("xy",[1]*59), ("width",4097),
                          ("observerReadSucceeded",False), ("sourceIDs",["private/path"]),
                          ("matrix",[]), ("state",[3.0]+[0.0]*15), ("status",True)]:
            with self.subTest(key=key):
                rows=records(); rows[2][key]=value; self.rejected(rows)

    def test_private_field_and_duplicate_json_rejected(self):
        rows=records(); rows[2]["imageBytes"]="secret"; self.rejected(rows)
        raw=encoded(records()).replace(b'"schema": 1',b'"schema": 1, "schema": 1',1)
        with self.assertRaises(ValueError):
            contract.inspect(io.BytesIO(raw),2)

    def test_bounded_line_read(self):
        class TooLong:
            def readline(self, limit):
                self.limit=limit
                return b" "*limit
        stream=TooLong()
        with self.assertRaises(ValueError): contract.inspect(stream,2)
        self.assertEqual(stream.limit,contract.MAX_LINE+1)


class PreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=Path(__file__).resolve().parents[3]
        cls.before,cls.after=prepare.prepare(cls.root)

    def test_only_isolated_observer_targets_and_source_unchanged(self):
        self.assertEqual(len(self.after),5)
        self.assertFalse(any(path.startswith('.github/') for path in self.after))
        for path,text in self.before.items():
            self.assertEqual((self.root/path).read_text(),text)

    def test_original_cpp_solver_lines_all_retained_in_order(self):
        # C++ instrumentation is insertion only: no existing algorithm, gate,
        # RNG initialization, detector parameter or return statement is edited.
        old=self.before['packages/visual-core/hx_vision.cpp'].splitlines()
        new=iter(self.after['packages/visual-core/hx_vision.cpp'].splitlines())
        for line in old:
            self.assertTrue(any(candidate==line for candidate in new),line)

    def test_three_actual_solve_sites_observed(self):
        text=self.after['HouseMemoryProof/VisualMapping.swift']
        self.assertEqual(text.count('hx_vision_pose('),3)
        self.assertEqual(text.count('observePose(kind:'),4) # declaration + three calls
        for kind in ['individual','pooled','consensus']:
            self.assertEqual(text.count('observePose(kind:"'+kind+'"'),1)

    def test_private_export_and_sealing_order(self):
        text=self.after['tooling/simulation/VisionReplay.swift']
        self.assertLess(text.index('try trace?.finish('),text.index('let audit=root.appendingPathComponent'))
        text=self.after['tooling/simulation/replay_fixture.py']
        compile(text,'proposed-replay-fixture.py','exec')
        self.assertIn("oracleReadDenied=report['oracleReadDenied']",text)
        self.assertIn("candidate/'temp/pose-trace'",text)

    def test_trace_creation_retains_exclusive_private_file_and_real_errno(self):
        text=self.after['tooling/simulation/VisionReplay.swift']
        self.assertIn('Darwin.open(path.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode_t(0o600))',text)
        self.assertIn('NSError(domain:NSPOSIXErrorDomain,code:Int(errno))',text)
        self.assertIn('FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)',text)
        self.assertNotIn('createFile(atPath:path.path,contents:nil)',text)

    def test_write_controls_do_not_expand_sandbox_policy_or_access_oracle(self):
        before=self.before['tooling/simulation/replay_fixture.py']
        after=self.after['tooling/simulation/replay_fixture.py']
        policy=lambda s:s[s.index(" profile='(version 1)"):s.index(" policy=root/'candidate.sb'")]
        self.assertEqual(policy(before),policy(after))
        self.assertIn("denied_write.returncode!=0 and not forbidden.exists()",after)
        self.assertLess(after.index("Observer write-isolation control failed"),after.index(' result=subprocess.run(sandbox+[str(exe)'))


if __name__=='__main__':
    unittest.main()
