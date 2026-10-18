"""Reproducible analytic observation faults, separate from geometry/render truth.

Models are deliberately named approximations. In particular Gaussian image blur
is not a rolling-shutter model, and these parameters are not calibrated iPhone
measurements. A candidate receives only returned observations, never the input
truth, degradation configuration, generator seed or private event ledger.
"""
from dataclasses import dataclass, asdict
import io
import math
import numpy as np
from PIL import Image, ImageFilter


@dataclass(frozen=True)
class Profile:
    depth_sigma_m: float = .003
    depth_scale: float = 1.
    depth_bias_m: float = 0.
    depth_correlation: float = .65
    edge_mix: float = 0.
    missing_depth_fraction: float = .02
    thin_dropout_fraction: float = 0.
    exposure_stops: float = 0.
    image_noise: float = 0.
    blur_pixels: float = 0.
    jpeg_quality: int = 95
    focal_scale: float = 1.
    principal_offset_px: float = 0.
    translation_drift_m_per_s: float = .001
    rotation_drift_rad_per_s: float = 0.
    pose_jump_frame: int = -1
    pose_jump_m: float = 0.
    frame_clock_offset_s: float = 0.
    frame_clock_rate: float = 1.
    depth_clock_offset_s: float = 0.
    missing_every: int = 0
    tracking_break_every: int = 0

    def validate(self):
        for key,value in asdict(self).items():
            if not isinstance(value,(int,float)) or not math.isfinite(value):raise ValueError('Nonfinite sensor parameter')
        bounds={'depth_sigma_m':(0,.2),'depth_scale':(.8,1.2),'depth_bias_m':(-.2,.2),'depth_correlation':(0,.99),
            'edge_mix':(0,1),'missing_depth_fraction':(0,1),'thin_dropout_fraction':(0,1),'exposure_stops':(-6,6),
            'image_noise':(0,100),'blur_pixels':(0,8),'jpeg_quality':(1,100),'focal_scale':(.8,1.2),'principal_offset_px':(-50,50),
            'translation_drift_m_per_s':(0,.2),'rotation_drift_rad_per_s':(0,.1),'pose_jump_frame':(-1,100000),
            'pose_jump_m':(0,2),'frame_clock_offset_s':(-100,100),'frame_clock_rate':(.99,1.01),'depth_clock_offset_s':(-1,1),
            'missing_every':(0,100000),'tracking_break_every':(0,100000)}
        for key,(low,high) in bounds.items():
            if not low<=getattr(self,key)<=high:raise ValueError('Sensor parameter outside generator budget')
        for key in ['jpeg_quality','pose_jump_frame','missing_every','tracking_break_every']:
            if not isinstance(getattr(self,key),int):raise ValueError('Integer sensor parameter required')


class Degrader:
    def __init__(self, seed, profile=Profile()):
        profile.validate();self.profile=profile;self.rng=np.random.default_rng(seed)
        self.depth_state=None;self.previous_time=None;self.first_time=None;self.events=[]

    def observe(self, rgb, depth, confidence, camera, intrinsics, timestamp, index, thin_mask=None):
        p=self.profile
        if not math.isfinite(timestamp) or timestamp<0 or self.previous_time is not None and timestamp<=self.previous_time:raise ValueError('Generator timestamps must increase')
        if not isinstance(index,int) or index<0:raise ValueError('Invalid frame index')
        depth=np.asarray(depth);rgb=np.asarray(rgb);confidence=np.asarray(confidence);camera=np.asarray(camera,dtype=float);k=np.asarray(intrinsics,dtype=float)
        if depth.ndim!=2 or rgb.shape!=(*depth.shape,3) or confidence.shape!=depth.shape or depth.size>1000000:raise ValueError('Mismatched observation arrays')
        if rgb.dtype!=np.uint8 or confidence.dtype!=np.uint8 or depth.dtype.kind!='f':raise ValueError('Unexpected image/depth/confidence encoding')
        if camera.shape!=(4,4) or k.size!=9 or not np.isfinite(camera).all() or not np.isfinite(k).all():raise ValueError('Invalid calibration or pose')
        if not np.allclose(camera[3],[0,0,0,1]) or not np.allclose(camera[:3,:3].T@camera[:3,:3],np.eye(3),atol=1e-6) or not math.isclose(np.linalg.det(camera[:3,:3]),1,abs_tol=1e-6):raise ValueError('Pose is not rigid')
        if not np.isfinite(depth).all() or np.any(depth<0) or np.any(confidence>2):raise ValueError('Invalid renderer depth/confidence')
        if thin_mask is not None and np.asarray(thin_mask).shape!=depth.shape:raise ValueError('Thin-object oracle mask shape mismatch')
        if self.first_time is None:self.first_time=timestamp
        self.previous_time=timestamp
        if p.missing_every and (index+1)%p.missing_every==0:
            self.events.append(dict(index=index,event='missing-frame'));return None
        dt=timestamp-self.first_time;valid=(depth>=.15)&(depth<=5)&(confidence>0)
        if self.depth_state is None or self.depth_state.shape!=depth.shape:self.depth_state=np.zeros(depth.shape)
        self.depth_state=p.depth_correlation*self.depth_state+math.sqrt(1-p.depth_correlation**2)*self.rng.normal(0,p.depth_sigma_m,depth.shape)
        measured=depth.astype(float)*p.depth_scale+p.depth_bias_m+self.depth_state
        mask=confidence.copy();edge=np.zeros(depth.shape,bool);neighbor=depth.copy()
        # Pair only in-image neighbors; no wrapping first/last row or column.
        delta=np.abs(depth[:,1:]-depth[:,:-1])>.08
        edge[:,1:]|=delta;edge[:,:-1]|=delta
        neighbor[:,1:]=np.where(delta,depth[:,:-1],neighbor[:,1:])
        delta=np.abs(depth[1:,:]-depth[:-1,:])>.08
        edge[1:,:]|=delta;edge[:-1,:]|=delta
        neighbor[1:,:]=np.where(delta,depth[:-1,:],neighbor[1:,:])
        if p.edge_mix:
            measured[edge]=(1-p.edge_mix)*measured[edge]+p.edge_mix*neighbor[edge]
            mask[edge]=np.minimum(mask[edge],1)
        missing=self.rng.random(depth.shape)<p.missing_depth_fraction
        if thin_mask is not None:missing|=np.asarray(thin_mask,dtype=bool)&(self.rng.random(depth.shape)<p.thin_dropout_fraction)
        valid &= ~missing & np.isfinite(measured) & (measured>=.15) & (measured<=5)
        measured=np.where(valid,measured,0).astype('<f4');mask[~valid]=0
        image=np.clip(rgb.astype(float)*(2**p.exposure_stops)+self.rng.normal(0,p.image_noise,rgb.shape),0,255).astype(np.uint8)
        image=Image.fromarray(image)
        if p.blur_pixels:image=image.filter(ImageFilter.GaussianBlur(p.blur_pixels))
        output=io.BytesIO();image.save(output,format='JPEG',quality=p.jpeg_quality)
        prior=camera.copy();prior[:3,3]+=np.array([p.translation_drift_m_per_s*dt,0,0])
        theta=p.rotation_drift_rad_per_s*dt;c,s=math.cos(theta),math.sin(theta)
        prior[:3,:3]=np.array([[c,0,s],[0,1,0],[-s,0,c]])@prior[:3,:3]
        tracking='synthetic normal'
        if p.pose_jump_frame>=0 and index>=p.pose_jump_frame:
            prior[0,3]+=p.pose_jump_m
            if index==p.pose_jump_frame:tracking='synthetic limited: pose jump';self.events.append(dict(index=index,event='pose-jump'))
        if p.tracking_break_every and (index+1)%p.tracking_break_every==0:
            tracking='synthetic limited: tracking break';self.events.append(dict(index=index,event='tracking-break'))
        k=k.reshape(3,3).copy();k[0,0]*=p.focal_scale;k[1,1]*=p.focal_scale;k[0,2]+=p.principal_offset_px;k[1,2]+=p.principal_offset_px
        return dict(image=output.getvalue(),depth=measured,confidence=mask,camera=prior,intrinsics=k.flatten().tolist(),
            timestamp=p.frame_clock_offset_s+timestamp*p.frame_clock_rate,
            depthTimestamp=p.frame_clock_offset_s+timestamp*p.frame_clock_rate+p.depth_clock_offset_s,tracking=tracking)


PROFILES={
    'nominal':Profile(),
    'dim-blurred':Profile(exposure_stops=-2,image_noise=4,blur_pixels=1.1,jpeg_quality=65),
    'depth-edges':Profile(depth_sigma_m=.012,edge_mix=.45,missing_depth_fraction=.12,thin_dropout_fraction=.8),
    'calibration-drift':Profile(focal_scale=1.01,principal_offset_px=.8,depth_scale=1.008,depth_bias_m=.003,translation_drift_m_per_s=.005,rotation_drift_rad_per_s=.002),
    'clock-interruptions':Profile(frame_clock_offset_s=.037,frame_clock_rate=1.0001,depth_clock_offset_s=.033,missing_every=7,tracking_break_every=5,pose_jump_frame=9,pose_jump_m=.15),
}
