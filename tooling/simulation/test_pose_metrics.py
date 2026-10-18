import math
import unittest
from pose_metrics import pose_errors,overlay_errors,distribution

IDENTITY=[1.,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
K=[400,0,320,0,400,240,0,0,1]


class FixedFrameMetrics(unittest.TestCase):
    def test_translation_preserves_rotation_and_matches_projected_shift(self):
        moved=IDENTITY.copy();moved[3]=.02
        self.assertEqual(pose_errors(moved,IDENTITY),dict(positionMetres=.02,rotationDegrees=0.))
        d=overlay_errors(moved,IDENTITY,K,[[320,240,2],[400,260,4]])
        self.assertTrue(all(abs(x-.02)<1e-10 for x in d['worldErrorsMetres']))
        self.assertAlmostEqual(d['reprojectionErrorsPixels'][0],4.)
        self.assertAlmostEqual(d['reprojectionErrorsPixels'][1],2.)

    def test_rotation_exposes_error_at_zero_camera_translation(self):
        angle=math.radians(1);c,s=math.cos(angle),math.sin(angle)
        moved=[c,0,s,0,0,1,0,0,-s,0,c,0,0,0,0,1]
        self.assertAlmostEqual(pose_errors(moved,IDENTITY)['rotationDegrees'],1.)
        d=overlay_errors(moved,IDENTITY,K,[[320,240,2]])
        self.assertAlmostEqual(d['worldErrorsMetres'][0],4*math.sin(angle/2))
        self.assertAlmostEqual(d['reprojectionErrorsPixels'][0],400*math.tan(angle))

    def test_fixed_house_origin_does_not_change_scores(self):
        truth=IDENTITY.copy();truth[3:12:4]=[10000,-4000,800]
        moved=truth.copy();moved[7]+=.01
        relative=IDENTITY.copy();relative[7]=.01
        a=overlay_errors(moved,truth,K,[[400,200,3]])
        b=overlay_errors(relative,IDENTITY,K,[[400,200,3]])
        self.assertAlmostEqual(a['worldErrorsMetres'][0],b['worldErrorsMetres'][0])
        self.assertAlmostEqual(a['reprojectionErrorsPixels'][0],b['reprojectionErrorsPixels'][0])

    def test_invalid_transforms_and_samples_cannot_be_scored_as_zero(self):
        for index,value in [(0,1.1),(0,-1),(3,float('nan')),(15,0)]:
            bad=IDENTITY.copy();bad[index]=value
            with self.assertRaises(ValueError):pose_errors(bad,IDENTITY)
        with self.assertRaises(ValueError):overlay_errors(IDENTITY,IDENTITY,[0,1,0,0],[[0,0,2]])
        with self.assertRaises(ValueError):overlay_errors(IDENTITY,IDENTITY,K,[[0,0,-2]])
        with self.assertRaises(ValueError):distribution([float('nan')])

    def test_surface_behind_estimated_camera_is_counted(self):
        moved=IDENTITY.copy();moved[11]=-4
        d=overlay_errors(moved,IDENTITY,K,[[320,240,2]])
        self.assertEqual(d,dict(worldErrorsMetres=[4.],reprojectionErrorsPixels=[],behindCamera=1,samples=1))

if __name__=='__main__':unittest.main()
