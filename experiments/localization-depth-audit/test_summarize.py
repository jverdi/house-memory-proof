import importlib.util
from pathlib import Path
import unittest
import numpy as np
spec=importlib.util.spec_from_file_location('depth_audit_summary',Path(__file__).with_name('summarize.py'));audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)

class AggregateDiagnosisContract(unittest.TestCase):
    def test_raycast_and_projection_share_optical_axis_contract(self):
        k=[100,0,64,0,100,48,0,0,1];pixels=np.array([[64,48],[74,48],[64,38]])
        geometry=[dict(low=[-5,1.9,-5],high=[5,2.1,5])]
        points,valid=audit.ray_points(pixels,k,audit.CANONICAL,[0,0,0],geometry)
        self.assertTrue(valid.all());np.testing.assert_allclose(points,[[0,1.9,0],[.19,1.9,0],[0,1.9,.19]],atol=1e-10)
        np.testing.assert_allclose(audit.project(points,audit.CANONICAL,k),pixels,atol=1e-10)

    def test_pose_orientation_metric_is_independent_of_translation(self):
        a=np.eye(4);b=np.eye(4);angle=np.deg2rad(7);c,s=np.cos(angle),np.sin(angle)
        b[:3,:3]=[[c,-s,0],[s,c,0],[0,0,1]];b[:3,3]=[10,-20,30]
        self.assertAlmostEqual(audit.angular_error(a,b),7,places=9)

    def test_hamming_match_and_duplicate_rejection(self):
        rng=np.random.default_rng(19);source=rng.integers(0,256,size=(12,32),dtype=np.uint8);query=source[[6,2,9,0]].copy()
        query[1,0]^=3
        result=audit.matches(source.tobytes(),query.tobytes())
        self.assertEqual(result.tolist(),[[6,0],[2,1],[9,2],[0,3]])
        duplicated=np.concatenate([source,source[6:7]])
        result=audit.matches(duplicated.tobytes(),query.tobytes())
        self.assertFalse(any(q==0 for _,q in result))

if __name__=='__main__':unittest.main()
