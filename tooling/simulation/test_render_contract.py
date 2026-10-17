"""Independent geometry checks for the evaluator's analytic ray renderer."""
import math
import unittest
import numpy as np
from house import box,render

class RendererContract(unittest.TestCase):
 def setUp(self):
  self.back=box((0,2.1,0),(10,.2,5),(200,100,50),'wall')
 def test_parallel_on_side_plane_and_outside(self):
  shapes=[box((.5,2.1,0),(1,.2,1),(255,255,255),'wall')]
  for x,expected in [(0.,2.),(-.1,0.)]:
   _,depth,_,_,_=render(shapes,np.array([x,0.,0.]),0,128,96)
   self.assertAlmostEqual(float(depth[48,64]),expected,places=6)
   self.assertTrue(np.isfinite(depth).all())
 def test_depth_is_optical_axis_not_euclidean_range(self):
  _,depth,valid,_,_=render([self.back],np.zeros(3),0,128,96)
  for x in [10,64,118]:
   self.assertTrue(valid[48,x]);self.assertAlmostEqual(float(depth[48,x]),2.,places=6)
 def test_foreground_occlusion_does_not_reveal_background_depth(self):
  front=box((0,.105,0),(.5,.01,.5),(20,250,20),'foreground')
  rgb,depth,valid,_,_=render([self.back,front],np.zeros(3),0,128,96)
  self.assertFalse(valid[48,64]);self.assertEqual(float(depth[48,64]),0.)
  self.assertGreater(int(rgb[48,64,1]),int(rgb[48,64,0]))
 def test_camera_rotation_and_projection_convention(self):
  position=np.array([.2,-.3,.4]);yaw=.37
  _,_,_,m,k=render([self.back],position,yaw,128,96)
  adapter=np.array([[1,0,0],[0,0,1],[0,-1,0]])
  self.assertTrue(np.allclose(m[:3,:3].T@m[:3,:3],np.eye(3)))
  self.assertAlmostEqual(np.linalg.det(m[:3,:3]),1.)
  self.assertTrue(np.allclose(m[:3,3],adapter@position))
  forward=np.array([math.sin(yaw),math.cos(yaw),0]);world=position+forward*2
  camera=np.linalg.inv(m)@np.r_[adapter@world,1]
  self.assertAlmostEqual(k[0]*camera[0]/(-camera[2])+k[2],64.)
  self.assertAlmostEqual(-k[4]*camera[1]/(-camera[2])+k[5],48.)

if __name__=='__main__':unittest.main()
