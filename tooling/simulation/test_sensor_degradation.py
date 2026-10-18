import unittest
import numpy as np
from sensor_degradation import Degrader,Profile,PROFILES


class SensorContract(unittest.TestCase):
    def inputs(self):
        rgb=np.full((24,32,3),120,np.uint8);depth=np.full((24,32),2,np.float32);mask=np.full((24,32),2,np.uint8)
        return rgb,depth,mask,np.eye(4),[24,0,16,0,24,12,0,0,1]

    def test_repeatability_preserves_original_inputs_and_private_ledger(self):
        for profile in PROFILES.values():
            a,b=Degrader(123,profile),Degrader(123,profile);inputs=self.inputs();original=[x.copy() if hasattr(x,'copy') else list(x) for x in inputs]
            for i in range(12):
                x=a.observe(*inputs,timestamp=i/3,index=i);y=b.observe(*inputs,timestamp=i/3,index=i)
                if x is None:self.assertIsNone(y);continue
                self.assertEqual(x.keys(),y.keys());self.assertNotIn('seed',x);self.assertNotIn('events',x)
                for key in x:
                    if isinstance(x[key],np.ndarray):np.testing.assert_array_equal(x[key],y[key])
                    else:self.assertEqual(x[key],y[key])
                self.assertTrue(np.all(x['depth'][x['confidence']==0]==0))
            for x,y in zip(inputs,original):np.testing.assert_array_equal(x,y)

    def test_systematic_scale_calibration_and_clock_faults_are_independent(self):
        p=Profile(depth_sigma_m=0,missing_depth_fraction=0,depth_scale=1.01,depth_bias_m=.004,focal_scale=.99,principal_offset_px=.7,
            frame_clock_offset_s=.04,frame_clock_rate=1.001,depth_clock_offset_s=.033,translation_drift_m_per_s=.02,rotation_drift_rad_per_s=.01)
        d=Degrader(1,p);d.observe(*self.inputs(),timestamp=1,index=0);r=d.observe(*self.inputs(),timestamp=3,index=1)
        np.testing.assert_allclose(r['depth'],2.024,atol=1e-6);self.assertAlmostEqual(r['intrinsics'][0],23.76);self.assertAlmostEqual(r['intrinsics'][2],16.7)
        self.assertAlmostEqual(r['timestamp'],3.043);self.assertAlmostEqual(r['depthTimestamp']-r['timestamp'],.033)
        self.assertAlmostEqual(r['camera'][0,3],.04);self.assertAlmostEqual(np.linalg.det(r['camera'][:3,:3]),1.)

    def test_edge_mixing_downgrades_confidence_without_wrapping(self):
        inputs=list(self.inputs());inputs[1][:,16:]=3
        r=Degrader(1,Profile(depth_sigma_m=0,missing_depth_fraction=0,edge_mix=.5)).observe(*inputs,timestamp=0,index=0)
        np.testing.assert_array_equal(r['confidence'][:,[0,31]],2)
        np.testing.assert_array_equal(r['confidence'][:,15:17],1)
        self.assertAlmostEqual(float(r['depth'][12,16]),2.5)

    def test_thin_dropout_never_substitutes_background_depth(self):
        thin=np.zeros((24,32),bool);thin[:,15]=True
        r=Degrader(1,Profile(depth_sigma_m=0,missing_depth_fraction=0,thin_dropout_fraction=1)).observe(*self.inputs(),timestamp=0,index=0,thin_mask=thin)
        np.testing.assert_array_equal(r['depth'][thin],0);np.testing.assert_array_equal(r['confidence'][thin],0)
        np.testing.assert_array_equal(r['depth'][~thin],2)

    def test_temporal_correlation_and_interruption_denominators(self):
        d=Degrader(8,Profile(depth_sigma_m=.02,depth_correlation=.9,missing_depth_fraction=0));previous=None;correlations=[]
        for i in range(60):
            r=d.observe(*self.inputs(),timestamp=i,index=i)['depth'].astype(float)-2
            if i>10:correlations.append(np.corrcoef(previous.ravel(),r.ravel())[0,1])
            previous=r
        self.assertGreater(float(np.mean(correlations)),.85);self.assertLess(float(np.mean(correlations)),.95)
        d=Degrader(1,Profile(missing_every=4,tracking_break_every=3,pose_jump_frame=5,pose_jump_m=.15))
        frames=[d.observe(*self.inputs(),timestamp=i,index=i) for i in range(12)]
        self.assertEqual(sum(x is None for x in frames),3)
        self.assertEqual(sum(e['event']=='missing-frame' for e in d.events),3)
        self.assertEqual(sum(e['event']=='pose-jump' for e in d.events),1)
        self.assertEqual(sum(e['event']=='tracking-break' for e in d.events),3)
        self.assertTrue(all('limited' in frames[i]['tracking'] for i in [2,5,8]))

    def test_malformed_contract_refused(self):
        with self.assertRaises(ValueError):Degrader(1,Profile(depth_scale=float('nan')))
        with self.assertRaises(ValueError):Degrader(1,Profile(jpeg_quality=50.5))
        for fault in range(4):
            inputs=list(self.inputs())
            if fault==0:inputs[2]=np.zeros((23,32),np.uint8)
            if fault==1:inputs[1][0,0]=np.nan
            if fault==2:inputs[3][0,0]=2
            if fault==3:inputs[2][0,0]=255
            with self.assertRaises(ValueError):Degrader(1).observe(*inputs,timestamp=0,index=0)
        d=Degrader(1);d.observe(*self.inputs(),timestamp=1,index=0)
        with self.assertRaises(ValueError):d.observe(*self.inputs(),timestamp=1,index=1)


if __name__=='__main__':unittest.main()
