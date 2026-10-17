#!/usr/bin/env python3
"""Independent known-pixel contracts for the coded print ray renderer."""
import unittest
import numpy as np
from coded_layout_fixture import paint_references


class PrintProjectionTests(unittest.TestCase):
    def draw(self,depth=5.,boards=None,yaw=0.,book=None):
        image=np.full((480,640,3),17,dtype=np.uint8)
        raster=np.full((10,10),255,dtype=np.uint8);raster[2,3]=0;raster[7,6]=64
        targets=boards if boards is not None else [dict(code=7,center=(0,2,0),right=(1,0,0),width=.4)]
        return paint_references(image,np.full((480,640),depth),np.ones((480,640),bool),np.zeros(3),yaw,[500,0,320,0,500,240,0,0,1],targets,book or {'7':raster.flatten().tolist()})
    def test_print_scale_and_asymmetric_orientation(self):
        image=self.draw()
        self.assertEqual(int(image[215,305,0]),0)
        self.assertEqual(int(image[265,335,0]),64)
        self.assertEqual(int(image[195,275,0]),255)
        self.assertEqual(int(image[240,265,0]),17)
        self.assertEqual(int(image[185,320,0]),17)
    def test_foreground_hides_print(self):
        self.assertTrue(np.all(self.draw(depth=1.)==17))
    def test_side_wall_uses_same_print_order(self):
        side=[dict(code=7,center=(2,0,0),right=(0,-1,0),width=.4)]
        self.assertTrue(np.array_equal(self.draw(),self.draw(boards=side,yaw=np.pi/2)))
    def test_nearer_print_occludes_far_print_independent_of_order(self):
        far=dict(code=7,center=(0,2,0),right=(1,0,0),width=.4)
        near=dict(code=8,center=(0,1,0),right=(1,0,0),width=.2)
        book={'7':[255]*100,'8':[80]*100}
        a=self.draw(boards=[far,near],book=book);b=self.draw(boards=[near,far],book=book)
        self.assertTrue(np.array_equal(a,b));self.assertEqual(int(a[240,320,0]),80)
    def test_print_behind_camera_is_absent(self):
        self.assertTrue(np.all(self.draw(boards=[dict(code=7,center=(0,-2,0),right=(1,0,0),width=.4)])==17))


if __name__=='__main__':unittest.main()
