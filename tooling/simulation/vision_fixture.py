#!/usr/bin/env python3
"""Textured-corner image localization fixture; query truth is evaluator-only."""
import hashlib,io,json,math,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from house import generate,room,render,v,identity

def make(dest, seed=73192, drift=0.0, frames=6, query_counts=None):
 rng=np.random.default_rng(seed);dest.mkdir(parents=True,exist_ok=True)
 h=generate(seed,dest/'base',rooms=1,frames=6,width=64,noise=.001,drift=.001)
 shapes,finish,dimensions=room(np.random.default_rng(seed));items=shapes+finish
 segment=h['segments'][1];rid=h['rooms'][0]['id'];h['segments']=[segment];h['observations']=[]
 h['name']='Synthetic textured-corner visual map';assets={};mapping_truth={};width=384;height=288
 def put(data,ext):
  key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
 def image_capture(shift,angle,texture,elevation=0):
  heading=math.pi/4+angle;position=np.array([shift/math.sqrt(2),-shift/math.sqrt(2),elevation])
  rgb,depth,valid,m,k=render(items,position,heading,width,height,texture_seed=texture)
  stream=io.BytesIO();Image.fromarray(rgb).save(stream,format='JPEG',quality=95)
  return stream.getvalue(),depth,valid,m,k
 shifts=[-.3,-.2,-.1,.1,.2,.3] if frames==6 else np.linspace(-.6,.6,frames).tolist()
 for index,shift in enumerate(shifts):
  image,depth,valid,m,k=image_capture(shift,0,seed)
  depth=np.where(valid,depth+rng.normal(0,.001,depth.shape),0).astype('<f4');confidence=np.where(valid,2,0).astype('uint8')
  prior=m.copy();prior[:3,3]+=rng.normal(0,.001,3);prior[0,3]+=drift*index/(frames-1)
  mapping_truth[identity(seed,f'visual-{index}')]=m.flatten().tolist()
  h['observations'].append(dict(id=identity(seed,f'visual-{index}'),roomID=rid,stageID=segment['stageID'],segmentID=segment['id'],timestamp=float(index),date=813974400.+index,image=put(image,'jpg'),depth=put(depth.tobytes(),'depth32'),confidence=put(confidence.tobytes(),'confidence8'),depthWidth=width,depthHeight=height,width=width,height=height,camera=prior.flatten().tolist(),intrinsics=k,tracking='synthetic perturbed prior',light=1000,sharpness=.1,note='Synthetic textured corner; not a validated phone sensor.',documentary=False,imageOrientation=1))
 entries={'house.json':json.dumps(h,separators=(',',':')).encode(),**assets}
 entries['manifest.json']=json.dumps({'format':'HouseXray','version':1,'sha256':{k:hashlib.sha256(d).hexdigest() for k,d in entries.items()}}).encode()
 with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as z:
  for name,data in entries.items():z.writestr(name,data)
 queries=[];canonical=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])
 query_cases=[(-.15,-2,seed,0),(.05,1,seed,.08),(.25,3,seed,-.06),(0,0,seed+901,0)]
 if query_counts is not None:
  query_rng=np.random.default_rng(seed ^ 0x78514A)
  positive,negative=query_counts
  query_cases=[(float(query_rng.uniform(-.28,.28)),float(query_rng.uniform(-3,3)),seed,float(query_rng.uniform(-.09,.09))) for _ in range(positive)]
  query_cases += [(float(query_rng.uniform(-.28,.28)),float(query_rng.uniform(-3,3)),seed+901+i,float(query_rng.uniform(-.09,.09))) for i in range(negative)]
 for index,(shift,angle,texture,elevation) in enumerate(query_cases):
  image,_,_,pose,k=image_capture(shift,math.radians(angle),texture,elevation)
  name=f'vision-query-{index}.jpg';(dest/name).write_bytes(image)
  queries.append(dict(image=name,width=width,height=height,intrinsics=k,expectedCamera=(canonical@pose).flatten().tolist(),shouldMatch=texture==seed))
 (dest/'vision-queries.json').write_text(json.dumps({'syntheticOnly':True,'fieldQualified':False,'queries':queries,'mappingCameras':mapping_truth,'injectedTranslationDriftMetres':drift},indent=2))
 print(json.dumps({'mapViews':frames,'heldQueryViews':sum(q['shouldMatch'] for q in queries),'unrelatedTextureQueries':sum(not q['shouldMatch'] for q in queries),'oracleExcludedFromMapArchive':True}),flush=True)
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('destination',type=Path);p.add_argument('--seed',type=int,default=73192);p.add_argument('--frames',type=int,choices=range(6,121),default=6);p.add_argument('--drift',type=float,default=0);a=p.parse_args()
 make(a.destination,a.seed,a.drift,a.frames)
