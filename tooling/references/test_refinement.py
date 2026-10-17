#!/usr/bin/env python3
"""Independent raster/blur/noise checks of the exact compiled detector adapter.

The renderer owns the homography; the detector receives image bytes only.
This checks pixel geometry, not metric or physical-device precision.
"""
import argparse,ctypes,json,math,time
from pathlib import Path
import numpy as np
from PIL import Image,ImageFilter

def run(library):
    lib=ctypes.CDLL(str(library.resolve()))
    lib.hx_tag_image.argtypes=[ctypes.c_uint,ctypes.c_void_p,ctypes.c_uint]
    lib.hx_tag_detect.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_uint,ctypes.c_uint,ctypes.c_uint,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint]
    def ptr(a):return a.ctypes.data_as(ctypes.c_void_p)
    def detect(image):
        height,width=image.shape;ids=np.zeros(64,np.uint32);xy=np.zeros((64,4,2));margin=np.zeros(64)
        count=lib.hx_tag_detect(ptr(image),image.size,width,height,width,ptr(ids),ptr(xy),ptr(margin),64)
        return count,ids,xy
    width,height=640,480;yy,xx=np.mgrid[:height,:width]
    rays=np.stack([xx,yy,np.ones_like(xx)],-1).astype(float)
    corners=np.array([[-1,1,1],[1,1,1],[1,-1,1],[-1,-1,1.]])
    rng=np.random.default_rng(493871);checks=[];started=time.monotonic()
    assert lib.hx_tag_selftest()==1
    for case in range(12):
        code=int(rng.integers(0,587));cells=np.zeros(100,np.uint8)
        assert lib.hx_tag_image(code,ptr(cells),100)==10
        cells=cells.reshape(10,10)
        angle=(case%4)*math.pi/2+rng.uniform(-.15,.15)
        size=rng.uniform(28,70);cx,cy=320+rng.uniform(-60,60),240+rng.uniform(-40,40)
        affine=np.array([[size*math.cos(angle),-size*math.sin(angle),cx],[size*math.sin(angle),size*math.cos(angle),cy],[0,0,1.]])
        perspective=np.array([[1,rng.uniform(-.15,.15),0],[rng.uniform(-.08,.08),rng.uniform(.7,1.1),0],[rng.uniform(-.12,.12),rng.uniform(-.08,.08),1.]])
        h=affine@perspective;local=rays@np.linalg.inv(h).T
        grid=local[:,:,:2]/local[:,:,2,None]*4+5
        mask=(grid[:,:,0]>=0)&(grid[:,:,0]<10)&(grid[:,:,1]>=0)&(grid[:,:,1]<10)
        image=np.full((height,width),235,np.uint8);ij=grid[mask].astype(int)
        image[mask]=np.where(cells[ij[:,1],ij[:,0]]==0,20,235)
        truth=corners@h.T;truth=truth[:,:2]/truth[:,2,None]+.5
        for blur in [0.,.7]:
            pixels=np.asarray(Image.fromarray(image).filter(ImageFilter.GaussianBlur(blur))).astype(float)
            pixels=np.clip(pixels+rng.normal(0,1.5,pixels.shape),0,255).astype(np.uint8)
            count,ids,xy=detect(pixels)
            error=float(np.linalg.norm(xy[0]-truth,axis=1).max()) if count==1 and ids[0]==code else None
            checks.append(dict(case=case,blurPixels=blur,detected=count,codeMatches=count==1 and int(ids[0])==code,maximumCornerErrorPixels=error,passed=error is not None and error<=1.5))
    blank=np.full((height,width),235,np.uint8)
    assert detect(blank)[0]==0
    return dict(passed=all(c['passed'] for c in checks),cases=len(checks),checks=checks,elapsedSeconds=time.monotonic()-started,maximumCornerErrorPixels=max((c['maximumCornerErrorPixels'] for c in checks if c['maximumCornerErrorPixels'] is not None),default=None),fieldQualified=False,limitation='Small independent projective raster/blur/noise fixture; not a camera sensor model or metric pose qualification')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--library',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    report=run(args.library);args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2))
    print(json.dumps({k:report[k] for k in ['passed','cases','maximumCornerErrorPixels','elapsedSeconds']}))
    if not report['passed']:raise SystemExit(1)
