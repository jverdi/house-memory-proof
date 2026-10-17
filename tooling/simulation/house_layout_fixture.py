#!/usr/bin/env python3
"""Connected, multi-level construction layouts with incomplete camera coverage.

The complete layout/semantic geometry is oracle-only. Candidate images have
noisy depth and camera priors. Unseen cavities remain unknown; this analytic
renderer is not an empirically calibrated phone sensor model.
"""
import argparse,hashlib,io,json,math,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from house import room,render,box,v,identity


def make(dest,seed=905771):
 rng=np.random.default_rng(seed);dest.mkdir(parents=True,exist_ok=True)
 width,height=384,288;now=813974400.;assets={};truth=[];observations=[];segments=[];rooms=[];query_truth=[]
 rough=identity(seed,'layout-rough');finished=identity(seed,'layout-finished')
 sizes=[]
 for index in range(4):
  shapes,finish,dimensions=room(np.random.default_rng(seed+index*1009));sizes.append((shapes,finish,dimensions))
 spacing=max(x[2][0] for x in sizes)+.30;rise=max(x[2][2] for x in sizes)+.35
 complete=[];origins=[]
 for index,(shapes,finish,dimensions) in enumerate(sizes):
  w,d,h=dimensions;origin=np.array([(index%2)*spacing,0,(index//2)*rise]);origins.append(origin)
  # Exterior sheathing remains visible through unfinished framing. Opposed
  # door openings join rooms on each floor; an external stair links levels.
  shapes += [box((0,side*(d/2+.04),h/2-1.4),(w,.03,h),(125,93,61),'structure') for side in [-1,1]]
  shapes += [box((side*(w/2+.04),0,h/2-1.4),(.03,d,h),(125,93,61),'structure') for side in [-1,1]]
  def doorway(items):
   result=[]
   for item in items:
    lo=np.array(item['low']);hi=np.array(item['high'])
    # Side-wall doorway: split crossing pieces at jambs and head. Retain every
    # non-opening piece, including sheathing and the finished wall surface.
    if min(abs(lo[0]),abs(hi[0]))>w/2-.20 and lo[1]<.48 and hi[1]>-.48 and lo[2]<.7:
     cuts=[(lo.copy(),hi.copy())]
     for axis,bound,lower in [(1,-.48,True),(1,.48,False),(2,.7,False)]:
      a,b=lo.copy(),hi.copy()
      if lower:b[axis]=min(b[axis],bound)
      else:a[axis]=max(a[axis],bound)
      if np.all(b>a):
       # Top piece is only the opening width, avoiding overlapping surfaces.
       if axis==2:a[1]=max(a[1],-.48);b[1]=min(b[1],.48)
       if np.all(b>a):result.append(dict(item,low=a.tolist(),high=b.tolist()))
    else:result.append(item)
   return result
  shapes=doorway(shapes);finish=doorway(finish)
  # Stable reference surfaces occupy two wall planes and survive the finish.
  targets=[box((x,d/2-.20,z),(.4,.012,.4),(235,235,235),'reference') for x,z in [(-.9,.15),(.9,.75)]]
  targets += [box((w/2-.20,y,z),(.012,.4,.4),(235,235,235),'reference') for y,z in [(-.8,.3),(.8,.8)]]
  shapes+=targets;finish+=targets
  truth.append(dict(room=identity(seed,f'layout-room-{index}'),level=index//2,origin=origin.tolist(),dimensions=dimensions,rough=shapes,finished=finish))
  for item in shapes:complete.append(dict(item,low=(np.array(item['low'])+origin).tolist(),high=(np.array(item['high'])+origin).tolist()))
 for level in range(2):
  left=level*2;right=left+1;a=sizes[left][2][0]/2;b=spacing-sizes[right][2][0]/2
  complete.append(box(((a+b)/2,0,level*rise-1.47),(b-a+.1,1.2,.14),(95,80,60),'floor'))
 # Stairs are actual geometry outside the two-room row, not a teleported floor.
 steps=18;stair_x=spacing+max(x[2][0] for x in sizes)/2+.8
 for step in range(steps):
  complete.append(box((stair_x,-2.5+step*.25,-1.4+(step+.5)*rise/steps),(1,.25,rise/steps),(110,90,65),'structure'))
 def asset(data,ext):
  key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
 def photograph(index,shift,angle=0,elevation=0,texture=None):
  origin=origins[index]
  # One world-space texture field is shared across rooms and floors. Only
  # the returned AR session frame is recentered; images are never repainted
  # according to the requested room identity.
  position=origin+np.array([shift/math.sqrt(2),-shift/math.sqrt(2),elevation])
  heading=math.pi/4+angle;forward=np.array([math.sin(heading),math.cos(heading),0]);right=np.array([math.cos(heading),-math.sin(heading),0])
  visible=[];horizontal=.5/.72;vertical=(height/width)*.5/.72
  for item in complete:
   low,high=np.array(item['low']),np.array(item['high'])
   corners=np.array([[x,y,z] for x in [low[0],high[0]] for y in [low[1],high[1]] for z in [low[2],high[2]]])-position
   z=corners@forward;x=corners@right;y=corners[:,2]
   if (z<=1e-8).all() or (z>=5).all() or (x>z*horizontal).all() or (x < -z*horizontal).all() or (y>z*vertical).all() or (y < -z*vertical).all():continue
   visible.append(item)
  rgb,depth,valid,m,k=render(visible,position,heading,width,height,texture_seed=seed if texture is None else texture)
  m[:3,3]-=np.array([origin[0],origin[2],-origin[1]])
  stream=io.BytesIO();Image.fromarray(rgb).save(stream,format='JPEG',quality=95)
  return stream.getvalue(),depth,valid,m,k
 canonical=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])
 mapping={}
 for index in range(4):
  rid=identity(seed,f'layout-room-{index}');sid=identity(seed,f'layout-segment-{index}')
  rooms.append(dict(id=rid,name='Repeated room name',level=index//2,origin=v((0,0,0)),size=v((5,4,2.8)),isDesign=True))
  segments.append(dict(id=sid,roomID=rid,stageID=rough,started=now,interrupted=False,approved=False,referencePoses=[]))
  for frame,shift in enumerate([-.3,-.2,-.1,.1,.2,.3]):
   image,depth,valid,m,k=photograph(index,shift);oid=identity(seed,f'layout-frame-{index}-{frame}');mapping[oid]=m.flatten().tolist()
   depth=np.where(valid,depth+rng.normal(0,.003,depth.shape),0).astype('<f4');confidence=np.where(valid,2,0).astype('uint8')
   missing=rng.random(depth.shape)<.02;depth[missing]=0;confidence[missing]=0
   prior=m.copy();prior[:3,3]+=rng.normal(0,.001,3);prior[0,3]+=.03*frame/5
   observations.append(dict(id=oid,roomID=rid,stageID=rough,segmentID=sid,timestamp=float(frame),date=now+frame,image=asset(image,'jpg'),depth=asset(depth.tobytes(),'depth32'),confidence=asset(confidence.tobytes(),'confidence8'),depthWidth=width,depthHeight=height,width=width,height=height,camera=prior.flatten().tolist(),intrinsics=k,tracking='synthetic noisy prior',light=700,sharpness=.1,note='Analytic connected-house capture; incomplete wall coverage.',documentary=False,imageOrientation=1))
  for number,(shift,angle,elevation) in enumerate([(-.17,-2,.03),(.04,1,-.05),(.24,2,.06)]):
   image,_,_,m,k=photograph(index,shift,math.radians(angle),elevation)
   name=f'room-{index}-query-{number}.jpg';(dest/name).write_bytes(image)
   query_truth.append(dict(image=name,width=width,height=height,intrinsics=k,segmentID=sid,shouldMatch=True,expectedCamera=(canonical@m).flatten().tolist(),scenario='nominal selected room'))
  # Same photograph, intentionally selected adjacent room and other floor.
  for target in [index^1,index^2]:
   name=f'room-{index}-wrong-{target}.jpg';(dest/name).write_bytes((dest/f'room-{index}-query-0.jpg').read_bytes())
   query_truth.append(dict(image=name,width=width,height=height,intrinsics=k,segmentID=identity(seed,f'layout-segment-{target}'),shouldMatch=False,expectedCamera=(canonical@m).flatten().tolist(),scenario='wrong room' if target//2==index//2 else 'wrong floor'))
 house=dict(schema=1,id=identity(seed,'layout-house'),name='Connected synthetic layout',created=now,revision=1,rooms=rooms,stages=[dict(id=rough,name='Rough-in',date=now,kind='synthetic',phase='Rough-in'),dict(id=finished,name='Finished',date=now+100,kind='synthetic',phase='Finished')],features=[],observations=observations,segments=segments,dimensions=[],drawings=[],bookmarks=[],references=[],documentaryPhotos=[],connections=[],isDemo=True,notes='Unregistered noisy local capture frames. Design dimensions are placeholders. Complete geometry is evaluator-only.',closureNotes='')
 entries={'house.json':json.dumps(house,separators=(',',':')).encode(),**assets}
 entries['manifest.json']=json.dumps(dict(format='HouseXray',version=1,sha256={n:hashlib.sha256(b).hexdigest() for n,b in entries.items()})).encode()
 with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as z:
  for n,b in entries.items():z.writestr(n,b)
 (dest/'vision-queries.json').write_text(json.dumps(dict(renderer='Connected four-room/two-level analytic layout',queries=query_truth,mappingCameras=mapping,injectedTranslationDriftMetres=.03,completeLayout=truth,oracleOnlyGeometry=complete,fieldQualified=False),indent=2))
 return dict(seed=seed,rooms=4,levels=2,photographs=24,nominalQueries=12,criticalQueries=8,fieldQualified=False,limitations=['Partial corner coverage; unseen surfaces must remain unknown','No calibrated sensor model','Finished-stage acquisition and full stair walkthrough are separate checks'])

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--seed',type=int,default=905771);a=p.parse_args();print(json.dumps(make(a.output,a.seed)))
