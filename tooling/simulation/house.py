#!/usr/bin/env python3
"""Deterministic ray-cast camera/depth fixtures, with an isolated oracle.

The .hxray input contains images, imperfect poses, depth/confidence and room names.
It deliberately contains no truth mesh, true room dimensions, registration or
true camera poses. oracle.json is evaluator-only and must not enter the candidate.
This is analytic rendering, not a validated iPhone sensor simulator.
"""
import argparse,hashlib,json,math,uuid,zipfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageFilter

def identity(seed,name):return str(uuid.uuid5(uuid.NAMESPACE_URL,f'house-xray/{seed}/{name}')).upper()
def v(p):return dict(zip(('x','y','z'),map(float,p)))
def box(center,size,color,trade):
 c=np.array(center);s=np.array(size)/2
 return {'low':(c-s).tolist(),'high':(c+s).tolist(),'color':color,'trade':trade}
def room(rng):
 w=float(rng.uniform(3.5,5.5));d=float(rng.uniform(3.5,5));height=float(rng.uniform(2.5,3.1));items=[]
 items.append(box((0,0,-1.47),(w,d,.14),(95,80,60),'floor'))
 # Camera-height origin; independent room frames are intentionally not registered.
 for side in [-1,1]:
  for x in np.arange(-w/2,w/2,.406):items.append(box((x,side*d/2,height/2-1.4),(.038,.14,height),(180,135,88),'structure'))
  for y in np.arange(-d/2,d/2,.406):items.append(box((side*w/2,y,height/2-1.4),(.14,.038,height),(180,135,88),'structure'))
 for x in np.arange(-w/2,w/2,.406):items.append(box((x,0,height-1.4),(.05,d,.2),(180,135,88),'structure'))
 items += [box((0,d/2-.04,-.25),(w*.8,.018,.018),(240,178,40),'electrical'),box((-.5,d/2-.05,.2),(.018,.018,1.2),(170,125,245),'lowVoltage'),box((w/2-.08,0,.2),(.05,d*.7,.05),(65,160,220),'plumbing'),box((0,0,height-1.65),(w*.7,.25,.25),(80,190,170),'hvac')]
 finish=[box((0,side*d/2,height/2-1.4),(w,.025,height),(205,210,210),'finish') for side in [-1,1]]+[box((side*w/2,0,height/2-1.4),(.025,d,height),(205,210,210),'finish') for side in [-1,1]]+[box((0,0,height-1.53),(w,d,.025),(220,220,225),'ceiling')]
 return items,finish,[w,d,height]
def render(items,position,yaw,width,height):
 fx=width*.72;fy=fx;cx=width/2;cy=height/2
 yy,xx=np.mgrid[:height,:width];right=np.array([math.cos(yaw),-math.sin(yaw),0]);forward=np.array([math.sin(yaw),math.cos(yaw),0]);up=np.array([0,0,1])
 rays=(xx[...,None]-cx)/fx*right-(yy[...,None]-cy)/fy*up+forward
 inv=np.divide(1,rays,out=np.full_like(rays,np.inf),where=np.abs(rays)>1e-12)
 nearest=np.full((height,width),np.inf);colors=np.zeros((height,width,3),np.uint8)+15
 for item in items:
  a=(np.array(item['low'])-position)*inv;b=(np.array(item['high'])-position)*inv
  near=np.minimum(a,b).max(axis=2);far=np.maximum(a,b).min(axis=2);hit=np.where(near>.1,near,far)
  selected=(far>=near)&(hit>.15)&(hit<nearest)&(hit<5)
  nearest[selected]=hit[selected];colors[selected]=item['color']
 # Stable spatial texture helps the renderer exhibit blur/lighting changes.
 finite=np.isfinite(nearest);safe=np.where(finite,nearest,0)
 surface=position+rays*safe[...,None]
 pattern=((np.floor(surface[...,0]*21)+np.floor(surface[...,1]*17)+np.floor(surface[...,2]*23))%2)*.18+.82
 colors=(colors*pattern[...,None]).astype(np.uint8)
 rotation=np.stack([right,up,-forward],axis=1)
 adapter=np.array([[1,0,0],[0,0,1],[0,-1,0]])
 matrix=np.eye(4);matrix[:3,:3]=adapter@rotation;matrix[:3,3]=adapter@position
 return colors,safe.astype('<f4'),finite,matrix,[fx,0,cx,0,fy,cy,0,0,1]
def generate(seed,dest,rooms=3,frames=24,width=128,noise=.004,drift=.015):
 rng=np.random.default_rng(seed);dest.mkdir(parents=True,exist_ok=True);assets={};observations=[];segments=[];space=[];truth={'seed':seed,'generator':'analytic-aabb-v1','not_a_validated_sensor_model':True,'rooms':[],'frames':[]}
 rough=identity(seed,'rough');finished=identity(seed,'finished');now=813974400.0
 def asset(data,ext):
  key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
 for ri in range(rooms):
  shapes,finish,dimensions=room(rng);rid=identity(seed,f'room-{ri}')
  space.append({'id':rid,'name':f'Synthetic room {ri+1}','level':ri//2,'origin':v((0,0,0)),'size':v((5,4,2.8)),'isDesign':True})
  truth['rooms'].append({'id':rid,'dimensions':dimensions,'rough_geometry':shapes,'finished_geometry':finish})
  for phase,stage in [('rough',rough),('finished',finished)]:
   sid=identity(seed,f'{ri}-{phase}');segments.append({'id':sid,'roomID':rid,'stageID':stage,'started':now,'interrupted':False,'approved':False,'referencePoses':[]})
   for f in range(frames):
    heading=(f//6)%4*math.pi/2;shift=(f%6-2.5)*.08;pos=np.array([shift*math.cos(heading),-shift*math.sin(heading),0.0])
    rgb,depth,valid,matrix,k=render(shapes if phase=='rough' else shapes+finish,pos,heading,width,width*3//4)
    oid=identity(seed,f'{sid}-{f}');truth['frames'].append({'id':oid,'camera':matrix.flatten().tolist()})
    depth=np.where(valid,np.maximum(.15,depth+rng.normal(0,noise,depth.shape)),0).astype('<f4');confidence=np.where(valid,2,0).astype('uint8')
    missing=rng.random(depth.shape)<.02;depth[missing]=0;confidence[missing]=0
    pose=matrix.copy();pose[:3,3]+=rng.normal(0,.002,3)+np.array([drift*f/max(1,frames-1),0,0])
    image=Image.fromarray(rgb);degraded=f%13==0
    if degraded:image=image.filter(ImageFilter.GaussianBlur(1.3))
    import io
    stream=io.BytesIO();image.save(stream,format='JPEG',quality=95)
    small=np.asarray(image.convert('L').resize((64,64)),float);sharp=(np.abs(np.diff(small,axis=0)).mean()+np.abs(np.diff(small,axis=1)).mean())/510
    observations.append({'id':oid,'roomID':rid,'stageID':stage,'segmentID':sid,'timestamp':float(f),'date':now+f,'image':asset(stream.getvalue(),'jpg'),'depth':asset(depth.tobytes(),'depth32'),'confidence':asset(confidence.tobytes(),'confidence8'),'depthWidth':width,'depthHeight':width*3//4,'width':width,'height':width*3//4,'camera':pose.flatten().tolist(),'intrinsics':k,'tracking':'synthetic noisy prior','light':1000,'sharpness':sharp,'note':f'Synthetic {phase} observation; camera prior contains noise/drift.','documentary':False,'imageOrientation':1})
 house={'schema':1,'id':identity(seed,'house'),'name':f'Simulated house {seed}','created':now,'revision':1,'rooms':space,'stages':[{'id':rough,'name':'Rough-in','date':now,'kind':'synthetic'},{'id':finished,'name':'Finished','date':now+100,'kind':'synthetic'}],'features':[],'observations':observations,'segments':segments,'dimensions':[],'drawings':[],'bookmarks':[],'references':[],'documentaryPhotos':[],'connections':[],'isDemo':True,'notes':'Analytic synthetic capture; no ground-truth geometry/poses in candidate input. Room dimensions are placeholder design values.','closureNotes':''}
 entries={'house.json':json.dumps(house,separators=(',',':')).encode(),**assets}
 manifest={'format':'HouseXray','version':1,'sha256':{k:hashlib.sha256(value).hexdigest() for k,value in entries.items()}}
 entries['manifest.json']=json.dumps(manifest).encode();entries['index.html']=b'<!doctype html><h1>Synthetic House Xray capture</h1><p>Generated test data, not construction evidence.</p>'
 with zipfile.ZipFile(dest/'candidate.hxray','w',compression=zipfile.ZIP_STORED,allowZip64=True) as z:
  for name,data in entries.items():z.writestr(name,data)
 (dest/'oracle.json').write_text(json.dumps(truth))
 (dest/'generator.json').write_text(json.dumps({'seed':seed,'rooms':rooms,'stages':2,'observations':len(observations),'depth_noise_sigma_m':noise,'translation_drift_m':drift,'oracle_is_separate':True,'validated_iphone_sensor_model':False},indent=2))
 Image.fromarray(rgb).save(dest/'preview.png')
 return house
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--seed',type=int,default=42);p.add_argument('--output',type=Path,required=True);p.add_argument('--rooms',type=int,default=3);p.add_argument('--frames',type=int,default=24);p.add_argument('--width',type=int,default=128);a=p.parse_args()
 assert 1<=a.rooms<=10 and 6<=a.frames<=120 and 64<=a.width<=512
 h=generate(a.seed,a.output,a.rooms,a.frames,a.width);print(json.dumps({'output':str(a.output/'candidate.hxray'),'observations':len(h['observations']),'synthetic':True}))
