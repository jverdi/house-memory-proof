"""Analytic evaluator tests, not a replay of any localization layout."""
import base64
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np

import pose_residuals as evaluator
import test_preparation
import trace_contract


def solve():
    row = copy.deepcopy(test_preparation.records()[2])
    pixels = [(142+20*(i%6), 88+20*(i//6)) for i in range(30)]
    row.update(xy=[v for p in pixels for v in p], xyz=[v for u, v0 in pixels for v in ((u-192)/100, -(v0-128)/100, -2)],
               intrinsics=[200,0,192,0,200,128,0,0,1],
               state=[7,0,0,-2,math.pi,0,0,0,0,2,math.pi,0,0,0,0,2])
    return row


def fixture(root):
    report = root/"case.json"
    audit = root/"case.audit"
    (audit/"pose-trace").mkdir(parents=True)
    row = solve()
    rows = test_preparation.records(); rows[2] = row
    raw = test_preparation.encoded(rows)
    (audit/"pose-trace/trace.jsonl").write_bytes(raw)
    identity = row["sourceIDs"][0]
    segment = "00000000-0000-0000-0000-000000000002"
    room = "00000000-0000-0000-0000-000000000003"
    descriptors = b"".join(i.to_bytes(32, "little") for i in range(30))
    encoded = base64.b64encode(descriptors).decode()
    normalized = [v/(384 if i%2 == 0 else 256) for i, v in enumerate(row["xy"])]
    image = dict(cameraWidth=384, cameraHeight=256, xy=normalized, descriptors=encoded, count=30)
    images = dict(sources=[dict(image, observationID=identity)],
                  queries=[dict(image, image="opaque-1.png"), dict(image, image="opaque-2.png")])
    (audit/"images.json").write_text(json.dumps(images))
    points = [dict(x=x,y=y,z=z) for x,y,z in np.asarray(row["xyz"]).reshape(-1,3)]
    mapping = dict(segmentID=segment,frameID=segment,points=points,descriptors=encoded,
                   views=[dict(observationID=identity,start=0,count=30)])
    (audit/("map-"+segment+".json")).write_text(json.dumps(mapping))
    names = {"opaque-1.png":"nominal-a.jpg", "opaque-2.png":"nominal-b.jpg"}
    (audit/"query-names.json").write_text(json.dumps(names))
    camera = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    shape = dict(low=[-1,-1,-2.01],high=[1,1,-2])
    query = dict(width=384,height=256,intrinsics=row["intrinsics"],segmentID=segment,
                 shouldMatch=True,expectedCamera=camera,scenario="nominal selected room")
    oracle = dict(queries=[dict(query,image=name) for name in names.values()],
                  mappingCameras={identity:evaluator.geometry.CANONICAL.T.flatten().tolist()},
                  completeLayout=[dict(room=room,origin=[0,0,0])],oracleOnlyGeometry=[shape],oracleOnlyFinishedGeometry=[shape])
    (audit/"oracle.json").write_text(json.dumps(oracle))
    (audit/"sealed-candidate.json").write_text(json.dumps(dict(candidateBinarySHA256="a"*64,
        traceSHA256=hashlib.sha256(raw).hexdigest(),oracleReadDenied=True,queryLabelsExcluded=True)))
    report.write_text(json.dumps(dict(candidateBinarySHA256="a"*64,passed=False,
        queries=[dict(image="nominal-a.jpg",accepted=True),dict(image="nominal-b.jpg",accepted=False)])))
    house = dict(observations=[dict(id=identity,segmentID=segment,intrinsics=row["intrinsics"])],
                 segments=[dict(id=segment,roomID=room)])
    with zipfile.ZipFile(audit/"input.hxray","w") as archive:
        archive.writestr("house.json",json.dumps(house)); archive.writestr("manifest.json","{}")
    return report, audit


class ResidualTests(unittest.TestCase):
    def test_centroid_and_opencv_axes_restore_camera(self):
        row = solve()
        np.testing.assert_allclose(evaluator.observed_pose(row["state"],10),row["matrix"],atol=1e-12)
        shifted = row["state"][:]; shifted[1] += 12.5
        self.assertAlmostEqual(evaluator.observed_pose(shifted,10)[3],12.5)

    def test_selection_uses_actual_indices_and_retains_rejected_pose(self):
        row = solve(); row.update(status=0,matrix=[],rejection=6,inlierIndices=list(range(1,30)),inlierCount=29)
        truth = test_preparation.records()[2]["matrix"]
        surface = np.asarray(row["xyz"]).reshape(-1,3).copy()
        row["xyz"][0] += .2
        metrics = evaluator.Metrics()
        counts = evaluator.solve_metrics(row,truth,surface,np.ones(30,dtype=bool),metrics)
        report = metrics.report()
        self.assertEqual(counts["inputCorrespondences"],30)
        self.assertEqual(counts["selectedCorrespondences"],29)
        self.assertAlmostEqual(report["inputQueryPixels"]["maximum"],20)
        self.assertEqual(report["selectedQueryPixels"]["maximum"],0)
        self.assertEqual(report["refinedPositionMetres"]["count"],1)

    def test_missing_surfaces_and_behind_camera_are_denominators(self):
        row = solve(); row["xyz"][2] = 2
        surface = np.asarray(row["xyz"]).reshape(-1,3)
        counts = evaluator.solve_metrics(row,row["matrix"],surface,np.zeros(30,dtype=bool),evaluator.Metrics())
        self.assertEqual(counts["inputBehindTruthCamera"],1)
        self.assertEqual(counts["inputWithoutTruthSurface"],30)

    def test_returned_pose_must_match_observer(self):
        row = solve(); row["matrix"][3] = 1
        with self.assertRaises(ValueError):
            evaluator.solve_metrics(row,test_preparation.records()[2]["matrix"],np.asarray(row["xyz"]).reshape(-1,3),np.ones(30,dtype=bool),evaluator.Metrics())

    def test_metric_bound_and_nonfinite_fail_closed(self):
        metric = evaluator.Metrics(limit=2)
        metric.add("a",[1,2])
        with self.assertRaises(ValueError): metric.add("b",[3])
        with self.assertRaises(ValueError): evaluator.Metrics().add("a",[float("nan")])

    def test_complete_aggregate_retains_failed_gate_and_abstentions(self):
        with tempfile.TemporaryDirectory() as folder:
            path, _ = fixture(Path(folder))
            result = evaluator.summarize(path,"rough")
        self.assertEqual(set(result),evaluator.PUBLIC_KEYS)
        self.assertTrue(result["complete"])
        self.assertFalse(result["originalGatePassed"])
        self.assertEqual(result["queryOutcomes"],dict(positiveAccepted=1,positiveAbstained=1))
        source = result["sourceMetrics"]
        self.assertEqual(source["counts"]["selectedCorrespondences"],30)
        self.assertAlmostEqual(source["metrics"]["selectedSourceDepthMetres"]["maximum"],0)
        self.assertNotIn("opaque",json.dumps(result))
        self.assertNotIn("00000000",json.dumps(result))
        self.assertNotIn("nominal-a",json.dumps(result))

    def test_corrupt_seal_or_footer_cannot_publish_metrics(self):
        for fault in ("seal","footer","outcome","feature"):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory() as folder:
                path,audit=fixture(Path(folder))
                if fault=="seal":
                    seal=json.loads((audit/"sealed-candidate.json").read_text());seal["traceSHA256"]="b"*64
                    (audit/"sealed-candidate.json").write_text(json.dumps(seal))
                elif fault=="footer":
                    trace=audit/"pose-trace/trace.jsonl";raw=trace.read_bytes().rsplit(b"\n",2)[0]+b"\n";trace.write_bytes(raw)
                    seal=json.loads((audit/"sealed-candidate.json").read_text());seal["traceSHA256"]=hashlib.sha256(raw).hexdigest()
                    (audit/"sealed-candidate.json").write_text(json.dumps(seal))
                elif fault=="outcome":
                    report=json.loads(path.read_text());report["queries"][0]["accepted"]=False;path.write_text(json.dumps(report))
                else:
                    images=json.loads((audit/"images.json").read_text());images["queries"][0]["xy"][0]+=.1
                    (audit/"images.json").write_text(json.dumps(images))
                with self.assertRaises(ValueError): evaluator.summarize(path,"rough")

    def test_ambiguous_source_pixel_is_explicitly_unscored(self):
        with tempfile.TemporaryDirectory() as folder:
            path,audit=fixture(Path(folder))
            images=json.loads((audit/"images.json").read_text());source=images["sources"][0]
            raw=base64.b64decode(source["descriptors"]);source["descriptors"]=base64.b64encode(raw+raw[:32]).decode()
            source["xy"]+=source["xy"][:2];source["count"]+=1
            (audit/"images.json").write_text(json.dumps(images))
            result=evaluator.summarize(path,"rough")
        self.assertEqual(result["sourceMetrics"]["counts"]["inputWithoutUniqueSourcePixel"],1)
        self.assertEqual(result["sourceMetrics"]["metrics"]["inputSourcePixels"]["count"],29)


if __name__ == "__main__":
    unittest.main()
