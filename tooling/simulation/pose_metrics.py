"""Independent fixed-frame pose/overlay scoring; never imported by a candidate."""
import math


def rigid(values):
    if len(values)!=16 or any(not isinstance(x,(int,float)) or isinstance(x,bool) or not math.isfinite(x) for x in values):
        raise ValueError('Pose must be a finite row-major 4x4 matrix')
    if any(abs(values[12+i]-v)>1e-7 for i,v in enumerate([0,0,0,1])):
        raise ValueError('Invalid homogeneous row')
    r=[[values[4*i+j] for j in range(3)] for i in range(3)]
    for i in range(3):
        for j in range(3):
            if abs(sum(r[k][i]*r[k][j] for k in range(3))-(1 if i==j else 0))>1e-5:
                raise ValueError('Non-rigid camera rotation')
    det=sum(r[0][j]*(r[1][(j+1)%3]*r[2][(j+2)%3]-r[1][(j+2)%3]*r[2][(j+1)%3]) for j in range(3))
    if abs(det-1)>1e-5:raise ValueError('Camera rotation includes a reflection')
    return r,[values[i] for i in (3,7,11)]


def pose_errors(estimate,truth):
    r,t=rigid(estimate);q,s=rigid(truth)
    trace=sum(r[i][j]*q[i][j] for i in range(3) for j in range(3))
    return dict(positionMetres=math.dist(t,s),rotationDegrees=math.degrees(math.acos(max(-1.,min(1.,(trace-1)/2)))))


def overlay_errors(estimate,truth,intrinsics,samples):
    """Samples are oracle-visible [u,v,optical-axis depth] at query capture.

    Measure displacement of the same camera ray/depth under the estimated pose,
    and reproject the true world point into the estimated camera. No alignment
    to truth, estimated scale fitting, or candidate depth is used for scoring.
    """
    r,t=rigid(estimate);q,s=rigid(truth)
    if len(intrinsics)!=9 or any(not math.isfinite(x) for x in intrinsics):raise ValueError('Invalid intrinsics')
    if any(abs(intrinsics[i]-v)>1e-8 for i,v in [(1,0),(3,0),(6,0),(7,0),(8,1)]):raise ValueError('Unsupported non-pinhole intrinsics')
    fx,fy,cx,cy=(intrinsics[i] for i in [0,4,2,5])
    if fx<=0 or fy<=0:raise ValueError('Invalid focal length')
    world=[];pixels=[];behind=0
    for sample in samples:
        if len(sample)!=3 or any(not math.isfinite(x) for x in sample) or sample[2]<=0:raise ValueError('Invalid visible surface sample')
        u,v,d=sample;local=[(u-cx)*d/fx,-(v-cy)*d/fy,-d]
        actual=[sum(q[i][j]*local[j] for j in range(3))+s[i] for i in range(3)]
        moved=[sum(r[i][j]*local[j] for j in range(3))+t[i] for i in range(3)]
        world.append(math.dist(actual,moved))
        projected=[sum(r[j][i]*(actual[j]-t[j]) for j in range(3)) for i in range(3)]
        if projected[2]>=-1e-8:behind+=1;continue
        pu=fx*projected[0]/(-projected[2])+cx;pv=fy*(-projected[1])/(-projected[2])+cy
        pixels.append(math.hypot(pu-u,pv-v))
    return dict(worldErrorsMetres=world,reprojectionErrorsPixels=pixels,behindCamera=behind,samples=len(samples))


def distribution(values):
    if any(not math.isfinite(x) or x<0 for x in values):raise ValueError('Nonfinite or negative metric')
    values=sorted(values)
    def percentile(f):return values[max(0,math.ceil(len(values)*f)-1)] if values else None
    return dict(count=len(values),p50=percentile(.5),p95=percentile(.95),maximum=max(values,default=None))
