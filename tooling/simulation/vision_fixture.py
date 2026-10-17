#!/usr/bin/env python3
"""Textured-corner image localization fixture; query truth is evaluator-only."""
import hashlib,io,json,math,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from house import generate,room,render,v,identity

def make(dest, seed=73192):
 rng=np.random.default_rng(seed);dest.mkdir(parents=True,exist_ok=True)
 h=generate(seed,dest/'base',rooms=1,frames=6,width=64,noise=.001,drift=.001)
 shapes,finish,dimensions=room(np.random.default_rng(seed));items=shapes+finish
 segment=h['segments'][1];rid=h['rooms'][0]['id'];h['segments']=[segment];h['observations']=[]
 h['name']='Synthetic textured-corner visual map';assets={};width=384;height=288
 def put(data,ext):
  key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
 def image_capture(shift,angle,texture,elevation=0):
  heading=math.pi/4+angle;position=np.array([shift/math.sqrt(2),-shift/math.sqrt(2),elevation])
  rgb,depth,valid,m,k=render(items,position,heading,width,height,texture_seed=texture)
  stream=io.BytesIO();Image.fromarray(rgb).save(stream,format='JPEG',quality=95)
  return stream.getvalue(),depth,valid,m,k
 for index,shift in enumerate([-.3,-.2,-.1,.1,.2,.3]):
  image,depth,valid,m,k=image_capture(shift,0,seed)
  depth=np.where(valid,depth+rng.normal(0,.001,depth.shape),0).astype('<f4');confidence=np.where(valid,2,0).astype('uint8')
  prior=m.copy();prior[:3,3]+=rng.normal(0,.001,3)
  h['observations'].append(dict(id=identity(seed,f'visual-{index}'),roomID=rid,stageID=segment['stageID'],segmentID=segment['id'],timestamp=float(index),date=813974400.+index,image=put(image,'jpg'),depth=put(depth.tobytes(),'depth32'),confidence=put(confidence.tobytes(),'confidence8'),depthWidth=width,depthHeight=height,width=width,height=height,camera=prior.flatten().tolist(),intrinsics=k,tracking='synthetic perturbed prior',light=1000,sharpness=.1,note='Synthetic textured corner; not a validated phone sensor.',documentary=False,imageOrientation=1))
 entries={'house.json':json.dumps(h,separators=(',',':')).encode(),**assets}
 entries['manifest.json']=json.dumps({'format':'HouseXray','version':1,'sha256':{k:hashlib.sha256(d).hexdigest() for k,d in entries.items()}}).encode()
 with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as z:
  for name,data in entries.items():z.writestr(name,data)
 queries=[];canonical=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])
 for index,(shift,angle,texture) in enumerate([(-.15,-2,seed),(.05,1,seed),(.25,3,seed),(0,0,seed+901)]):
  image,_,_,pose,k=image_capture(shift,math.radians(angle),texture,[0,.08,-.06,0][index])
  name=f'vision-query-{index}.jpg';(dest/name).write_bytes(image)
  queries.append(dict(image=name,width=width,height=height,intrinsics=k,expectedCamera=(canonical@pose).flatten().tolist(),shouldMatch=texture==seed))
 (dest/'vision-queries.json').write_text(json.dumps({'syntheticOnly':True,'fieldQualified':False,'queries':queries},indent=2))
 print(json.dumps({'mapViews':6,'heldQueryViews':3,'unrelatedTextureQueries':1,'oracleExcludedFromMapArchive':True}))
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('destination',type=Path);p.add_argument('--seed',type=int,default=73192);a=p.parse_args()
 make(a.destination,a.seed)
