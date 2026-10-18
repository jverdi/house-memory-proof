"""Capture bundles from varied connected house geometry; oracle stays separate.

Uses the existing analytic ray renderer and the independent degradation adapter.
This initial capture policy observes selected corners plus tilted upper-wall
views. It is NOT a complete coverage, continuous walkthrough or field claim.
"""
import argparse
from dataclasses import replace
import hashlib
import json
import math
from pathlib import Path
import zipfile
import numpy as np
from house import identity,v,box,render
from house_topology import generate,geometry,validate,topology_signature
from sensor_degradation import Degrader,PROFILES


def make(dest,seed,width=384,profile_name='nominal',map_stage='rough'):
    if width not in [128,192,384,768] or profile_name not in PROFILES or map_stage not in ['rough','finished']:raise ValueError('Unsupported fixture profile')
    dest=Path(dest);dest.mkdir(parents=True,exist_ok=True);height=width*3//4
    layout=generate(seed);pitch=layout['pitch'];profile=PROFILES[profile_name];assets={};observations=[];segments=[];rooms=[];queries=[];mapping={};now=813974400.
    stages={name:identity(seed,'whole-stage-'+name) for name in ['rough','finished']};origins={};targets=[];capture_ledger=[]
    for i,room in enumerate(layout['rooms']):
        x,y=max(room['cells'],key=lambda cell:(sum(cell),cell));origin=np.array([(x+.5)*pitch,(y+.5)*pitch,room['elevation']+1.4]);origins[i]=origin
        rooms.append(dict(id=identity(seed,'whole-room-'+str(i)),name=room['name'],level=room['level'],origin=v((0,0,0)),size=v((5,4,2.8)),isDesign=True))
        # Retained measured targets sit in front of the finish on two boundary
        # walls of the selected cell. Candidate receives pixels/depth only.
        for n,(along,elevation) in enumerate([(.45,-.5),(1.15,.65),(.75,.1)]):
            g=box((origin[0]+along,(y+1)*pitch-.14,origin[2]+elevation),(.4,.012,.4),(235,235,235),'reference');g['id']=identity(seed,f'whole-target-{i}-front-{n}');targets.append(g)
        for n,(along,elevation) in enumerate([(1.2,-.45),(.55,.65),(.95,.15)]):
            g=box(((x+1)*pitch-.14,origin[1]+along,origin[2]+elevation),(.012,.4,.4),(235,235,235),'reference');g['id']=identity(seed,f'whole-target-{i}-side-{n}');targets.append(g)
    geometries={stage:geometry(layout,stage)+targets for stage in stages}
    def asset(data,ext):
        key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
    def photograph(room_index,stage,shift,yaw_offset=0,elevation=0,tilt=0,keep_targets=True):
        origin=origins[room_index];position=origin+np.array([shift/math.sqrt(2),-shift/math.sqrt(2),elevation]);yaw=math.pi/4+yaw_offset
        forward=np.array([math.sin(yaw)*math.cos(tilt),math.cos(yaw)*math.cos(tilt),math.sin(tilt)]);right=np.array([math.cos(yaw),-math.sin(yaw),0]);up=np.cross(right,forward)
        # Conservative frustum culling changes cost, not visibility or truth.
        selected=[];horizontal=.5/.72;vertical=(height/width)*.5/.72
        for item in geometries[stage]:
            if not keep_targets and item['trade']=='reference':continue
            lo,hi=item['low'],item['high'];corners=np.array([[x,y,z] for x in [lo[0],hi[0]] for y in [lo[1],hi[1]] for z in [lo[2],hi[2]]])-position
            z=corners@forward;x=corners@right;y=corners@up
            if (z<=1e-8).all() or (z>=5).all() or (x>z*horizontal).all() or (x < -z*horizontal).all() or (y>z*vertical).all() or (y < -z*vertical).all():continue
            selected.append(item)
        rgb,depth,valid,m,k,ids=render(selected,position,yaw,width,height,texture_seed=seed,pitch=tilt,visibility=True)
        m[:3,3]-=np.array([origin[0],origin[2],-origin[1]])
        thin=np.zeros(depth.shape,bool)
        for index,item in enumerate(selected):
            if item['trade'] in ['electrical','lowVoltage']:thin|=ids==index
        return rgb,depth,np.where(valid,2,0).astype(np.uint8),m,k,thin
    canonical=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])
    segment_ids={}
    for stage_index,stage in [(list(stages).index(map_stage),map_stage)]:
        for i,room in enumerate(rooms):
            sid=identity(seed,f'whole-segment-{i}-{stage}');segment_ids[i,stage]=sid
            segments.append(dict(id=sid,roomID=room['id'],stageID=stages[stage],started=now+stage_index*100,interrupted=False,approved=False,referencePoses=[]))
            degradation=Degrader(seed+i*1009+stage_index*10301,profile)
            for frame,(shift,tilt) in enumerate([(s,0) for s in [-.3,-.2,-.1,.1,.2,.3]]+[(-.12,.35),(.12,.35)]):
                rgb,depth,confidence,m,k,thin=photograph(i,stage,shift,tilt=tilt)
                sample=degradation.observe(rgb,depth,confidence,m,k,timestamp=frame/3,index=frame,thin_mask=thin)
                if sample is None:continue
                oid=identity(seed,f'whole-observation-{i}-{stage}-{frame}');mapping[oid]=m.flatten().tolist()
                observations.append(dict(id=oid,roomID=room['id'],stageID=stages[stage],segmentID=sid,timestamp=sample['timestamp'],date=now+stage_index*100+frame/3,
                    image=asset(sample['image'],'jpg'),depth=asset(sample['depth'].tobytes(),'depth32'),confidence=asset(sample['confidence'].tobytes(),'confidence8'),depthWidth=width,depthHeight=height,width=width,height=height,
                    camera=sample['camera'].flatten().tolist(),intrinsics=sample['intrinsics'],tracking=sample['tracking'],light=700*(2**profile.exposure_stops),sharpness=.1,
                    note='Synthetic partial house observation; no inferred completeness.',documentary=False,imageOrientation=1,
                    captureMetadata=dict(version=1,source='analytic-replay',kind='rgbd_posed',mode='synthetic-frame',deviceModel='Analytic fixture',systemVersion='Uncalibrated generator',
                        frameTimestamp=sample['timestamp'],receivedUTC=now+stage_index*100+frame/3,receiptUptimeBeforeUTC=10+stage_index*100+frame/3,receiptUptimeAfterUTC=10.001+stage_index*100+frame/3,
                        calibrationWidth=width,calibrationHeight=height,imagePixelFormat=0,depthEncoding='float32-le-metres-optical-axis',confidenceEncoding='uint8-arkit-0-low-1-medium-2-high',depthTimestamp=sample['depthTimestamp'],
                        unavailable=dict(frameToUTC='No measured frame-to-UTC mapping is provided to the candidate.',motionTimestamp='No independent motion observation.',distortion='No calibrated lens-distortion model.',exif='Rendered image has no camera EXIF.',pixelFormat='Input is an analytic RGB array, not a CoreVideo camera pixel buffer.'))))
            capture_ledger.append(dict(room=i,stage=stage,attemptedFrames=8,retainedFrames=sum(o['segmentID']==sid for o in observations),events=degradation.events))
    for stage_index,stage in [(list(stages).index(map_stage),map_stage)]:
        for i in range(len(rooms)):
            sid=segment_ids[i,stage];query_degrader=Degrader(seed+70001+i+stage_index*101,replace(profile,missing_every=0,tracking_break_every=0,pose_jump_frame=-1))
            for number,(shift,angle,elevation) in enumerate([(-.17,-2,.03),(.04,1,-.05),(.24,2,.06),(-.06,1.5,.02)]):
                rgb,depth,confidence,m,k,thin=photograph(i,stage,shift,math.radians(angle),elevation)
                sample=query_degrader.observe(rgb,depth,confidence,m,k,timestamp=number/3,index=number,thin_mask=thin)
                filename=f'query-{i}-{stage}-{number}.jpg';(dest/filename).write_bytes(sample['image'])
                visible=[]
                for row in np.linspace(height*.15,height*.85,6).astype(int):
                    for col in np.linspace(width*.15,width*.85,8).astype(int):
                        if confidence[row,col]==2 and .15<float(depth[row,col])<5:
                            visible.append([int(col),int(row),float(depth[row,col])])
                q=dict(image=filename,width=width,height=height,intrinsics=sample['intrinsics'],segmentID=sid,shouldMatch=True,expectedCamera=(canonical@m).flatten().tolist(),scenario=stage+' selected room',truthIntrinsics=k,visibleSurfaceSamples=visible);queries.append(q)
                # Different selected spaces use identical query bytes. Truth
                # labels and filename semantics are removed by the OS sandbox.
                other=next(j for j in range(len(rooms)) if j!=i and rooms[j]['level']==rooms[i]['level'])
                alternatives=[other]
                different_floor=next((j for j in range(len(rooms)) if rooms[j]['level']!=rooms[i]['level']),None)
                alternatives.append(different_floor if different_floor is not None else next(j for j in range(len(rooms)) if j not in [i,other]))
                for target in alternatives:
                    name=f'wrong-{i}-{stage}-{number}-{target}.jpg';(dest/name).write_bytes(sample['image'])
                    queries.append(dict(q,image=name,segmentID=segment_ids[target,stage],shouldMatch=False,scenario='wrong floor' if rooms[target]['level']!=rooms[i]['level'] else 'wrong room'))
    house=dict(schema=1,id=identity(seed,'whole-house'),name='Synthetic connected house',created=now,revision=1,rooms=rooms,
        stages=[dict(id=stages[name],name='Rough-in' if name=='rough' else 'Finished',date=now+index*100,kind='synthetic',phase='Rough-in' if name=='rough' else 'Finished') for index,name in enumerate(stages)],
        features=[],observations=observations,segments=segments,dimensions=[],drawings=[],bookmarks=[],references=[],documentaryPhotos=[],connections=[],isDemo=True,notes='Design dimensions are placeholders. Actual topology, routes, dimensions and ideal poses are evaluator-only.',closureNotes='')
    entries={'house.json':json.dumps(house,separators=(',',':')).encode(),**assets}
    entries['manifest.json']=json.dumps(dict(format='HouseXray',version=1,sha256={n:hashlib.sha256(b).hexdigest() for n,b in entries.items()})).encode()
    with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as z:
        for name,data in entries.items():z.writestr(name,data)
    oracle=dict(renderer='Connected varied house analytic AABB rendering',queries=queries,mappingCameras=mapping,injectedTranslationDriftMetres=profile.translation_drift_m_per_s*7/3,
        expectedMapCount=len(segments),mapStage=map_stage,layout=layout,captureLedger=capture_ledger,profile=profile_name,topologySignature=topology_signature(layout),fieldQualified=False,
        limitations=['Selected corners and tilted upper-wall views, not complete house coverage','Analytic sensor faults are not empirically calibrated','Registration across rooms, closed-loop guidance and continuous stair paths are not scored by this localization replay'])
    (dest/'vision-queries.json').write_text(json.dumps(oracle,indent=2))
    summary=dict(**validate(layout),topologySignature=topology_signature(layout),sourcePhotographs=len(observations),maps=len(segments),nominalQueries=sum(q['shouldMatch'] for q in queries),criticalQueries=sum(not q['shouldMatch'] for q in queries),width=width,profile=profile_name,mapStage=map_stage,oracleIsSeparate=True,physicalQualification=False)
    (dest/'generator-summary.json').write_text(json.dumps(summary,indent=2)+'\n');return summary


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--seed',type=int,required=True);p.add_argument('--width',type=int,default=384);p.add_argument('--profile',choices=PROFILES,default='nominal');p.add_argument('--stage',choices=['rough','finished'],default='rough');a=p.parse_args();print(json.dumps(make(a.output,a.seed,a.width,a.profile,a.stage)))
