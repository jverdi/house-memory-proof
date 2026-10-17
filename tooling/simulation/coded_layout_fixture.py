#!/usr/bin/env python3
"""Independent ray/plane images for four coded-reference capture regions.

The candidate receives photographs, noisy camera priors, measured print sizes
and owner-selected region IDs. Marker poses, true cameras and query labels stay
in the evaluator. This is a development fixture, not a calibrated phone model
or a connected-house navigation qualification.
"""
import argparse,hashlib,io,json,math,zipfile
from pathlib import Path
import numpy as np
from PIL import Image
from house import box,identity,render,v


def paint_references(rgb,depth,valid,position,yaw,k,boards,book):
    """Ray intersections with physical print planes, including occlusion."""
    height,width=depth.shape;yy,xx=np.mgrid[:height,:width]
    right=np.array([math.cos(yaw),-math.sin(yaw),0.]);forward=np.array([math.sin(yaw),math.cos(yaw),0.])
    rays=(xx[...,None]-k[2])/k[0]*right-(yy[...,None]-k[5])/k[4]*np.array([0.,0.,1.])+forward
    nearest=np.where(valid,depth,np.inf).astype(float)
    for board in boards:
        center=np.array(board['center']);u=np.array(board['right']);down=np.array([0.,0.,-1.]);normal=np.cross(u,down)
        denominator=rays@normal
        with np.errstate(divide='ignore',invalid='ignore'):
            distance=np.dot(center-position,normal)/denominator
        safe=np.where(np.isfinite(distance),distance,0.)
        offset=position+rays*safe[...,None]-center
        # Stabilize exact cell/outer boundaries against sin(pi/2) roundoff.
        x=np.round(offset@u/board['width']+.5,12);y=np.round(offset@down/board['width']+.5,12)
        selected=(distance>.15)&(distance<nearest)&(x>=0)&(x<1)&(y>=0)&(y<1)
        # Each source pixel samples one printed cell. No detector/pose routine
        # participates in the renderer or generates measured corner positions.
        columns=np.clip((x[selected]*10).astype(int),0,9);rows=np.clip((y[selected]*10).astype(int),0,9)
        pixels=np.asarray(book[str(board['code'])],dtype=np.uint8).reshape(10,10)
        rgb[selected]=np.repeat(pixels[rows,columns,None],3,axis=1)
        nearest[selected]=distance[selected]
    return rgb


def make(dest,book,seed=802117,drift=.003,width=1280):
    dest.mkdir(parents=True,exist_ok=True);rng=np.random.default_rng(seed)
    height=width*3//4;assets={};observations=[];segments=[];rooms=[];references=[];oracle=[];layouts=[]
    now=813974400.;rough=identity(seed,'rough');finished=identity(seed,'finished')
    codes=list(map(int,rng.choice(587,24,replace=False)))
    def asset(data,ext):
        name=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+name]=data;return name
    def encoded(image,format='JPEG'):
        output=io.BytesIO();Image.fromarray(image).save(output,format=format,**({'quality':95} if format=='JPEG' else {}));return output.getvalue()
    canonical=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]])
    for region in range(4):
        w=float(rng.uniform(3.5,4.1));d=float(rng.uniform(3.5,4.1))
        rid=identity(seed,f'room-{region}');sid=identity(seed,f'segment-{region}')
        rooms.append(dict(id=rid,name='Repeated room name',level=region//2,origin=v((0,0,0)),size=v((5,4,2.8)),isDesign=True))
        segments.append(dict(id=sid,roomID=rid,stageID=rough,started=now,interrupted=False,approved=False,referencePoses=[]))
        targets=[]
        for index,(side,a,z) in enumerate([(0,.45,-.50),(0,1.15,.65),(0,.75,.10),(1,1.20,-.45),(1,.55,.65),(1,.95,.15)]):
            code=codes[region*6+index];bid=identity(seed,f'board-{code}')
            center=(a,d/2-.20,z) if side==0 else (w/2-.20,a,z)
            target=dict(code=code,center=center,right=(1,0,0) if side==0 else (0,-1,0),width=.18);targets.append(target)
            raster=np.asarray(book[str(code)],dtype=np.uint8).reshape(10,10)
            print_image=np.repeat(np.repeat(raster,24,axis=0),24,axis=1)
            key=asset(encoded(print_image,'PNG'),'png')
            # A genuine printable image/PDF is retained, with no pose metadata.
            pdf=io.BytesIO();Image.fromarray(print_image).convert('RGB').save(pdf,format='PDF',resolution=240/.18*.0254)
            references.append(dict(id=bid,name=f'Reference {code}',image=key,pdf=asset(pdf.getvalue(),'pdf'),width=.18,location='',valid=True,tagID=code,roomID=rid))
        walls=[box((0,d/2+.01,.1),(w,.04,3),(207,211,214),'wall'),box((w/2+.01,0,.1),(.04,d,3),(207,211,214),'wall'),box((0,0,-1.47),(w,d,.14),(100,90,80),'floor')]
        walls=[dict(item,textureless=True) for item in walls]
        framing=[box((x,d/2-.02,.1),(.038,.08,3),(185,140,95),'structure') for x in [-1.2,-.8,-.4,0,.4,.8,1.2]]
        layouts.append(dict(roomID=rid,level=region//2,width=w,depth=d,references=targets))
        def photograph(shift,elevation=0.,angle=0.,closed=False,challenge=None):
            position=np.array([shift/math.sqrt(2),-shift/math.sqrt(2),elevation]);yaw=math.pi/4+angle
            image,depth,valid,m,k=render(walls if closed else walls+framing,position,yaw,width,height,texture_seed=None if closed else seed)
            chosen=[dict(b) for b in targets]
            if challenge=='missing':chosen=[]
            elif challenge=='moved':chosen[0]['center']=tuple(np.array(chosen[0]['center'])+np.array([.08,0,0]))
            elif challenge=='duplicate':chosen[1]['code']=chosen[0]['code']
            image=paint_references(image,depth,valid,position,yaw,k,chosen,book)
            return encoded(image),m,k
        for frame,shift in enumerate([-.24,-.08,.08,.24]):
            image,m,k=photograph(shift);prior=m.copy();prior[:3,3]+=rng.normal(0,.0005,3)+np.array([drift*frame/3,0,0])
            observations.append(dict(id=identity(seed,f'observation-{region}-{frame}'),roomID=rid,stageID=rough,segmentID=sid,timestamp=float(frame),date=now+frame,image=asset(image,'jpg'),width=width,height=height,camera=prior.flatten().tolist(),intrinsics=k,tracking='synthetic noisy camera prior',light=900,sharpness=.1,note='Independent ray/plane coded-reference source image',documentary=False,imageOrientation=1))
        for closed in [False,True]:
            for number,(shift,elevation,angle) in enumerate([(-.15,.025,-.015),(.13,-.03,.02)]):
                image,m,k=photograph(shift,elevation,angle,closed);name=f'region-{region}-{closed}-{number}.jpg';(dest/name).write_bytes(image)
                oracle.append(dict(image=name,width=width,height=height,intrinsics=k,segmentID=sid,shouldMatch=True,expectedCamera=(canonical@m).flatten().tolist(),scenario='finished coded references' if closed else 'rough coded references'))
        image,m,k=photograph(.02,closed=True)
        for target in [region^1,region^2]:
            name=f'region-{region}-wrong-{target}.jpg';(dest/name).write_bytes(image)
            oracle.append(dict(image=name,width=width,height=height,intrinsics=k,segmentID=identity(seed,f'segment-{target}'),shouldMatch=False,expectedCamera=(canonical@m).flatten().tolist(),scenario='wrong room' if target//2==region//2 else 'wrong floor'))
        for challenge in ['missing','moved','duplicate']:
            image,m,k=photograph(.02,closed=True,challenge=challenge);name=f'region-{region}-{challenge}.jpg';(dest/name).write_bytes(image)
            oracle.append(dict(image=name,width=width,height=height,intrinsics=k,segmentID=sid,shouldMatch=False,expectedCamera=(canonical@m).flatten().tolist(),scenario=challenge+' reference'))
    house=dict(schema=1,id=identity(seed,'house'),name='Coded reference development regions',created=now,revision=1,rooms=rooms,stages=[dict(id=rough,name='Rough',date=now,kind='synthetic',phase='Rough-in'),dict(id=finished,name='Finished',date=now+100,kind='synthetic',phase='Finished')],features=[],observations=observations,segments=segments,dimensions=[],drawings=[],bookmarks=[],references=references,documentaryPhotos=[],connections=[],isDemo=True,notes='Four independent local capture frames; no truth marker positions supplied.',closureNotes='')
    entries={'house.json':json.dumps(house,separators=(',',':')).encode(),**assets}
    entries['manifest.json']=json.dumps(dict(format='HouseXray',version=1,sha256={n:hashlib.sha256(b).hexdigest() for n,b in entries.items()})).encode()
    with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as z:
        for n,b in entries.items():z.writestr(n,b)
    (dest/'vision-queries.json').write_text(json.dumps(dict(renderer='Independent ray/plane coded print regions',queries=oracle,layouts=layouts,fieldQualified=False,injectedTranslationDriftMetres=drift),indent=2))
    return dict(seed=seed,regions=4,levels=2,sourcePhotos=len(observations),nominalQueries=16,rejectionQueries=20,cameraPriorDriftMetres=drift,oracleMarkerPosesExcluded=True,fieldQualified=False)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--codebook',type=Path,required=True);p.add_argument('--seed',type=int,default=802117);p.add_argument('--drift',type=float,default=.003);a=p.parse_args()
    print(json.dumps(make(a.output,json.loads(a.codebook.read_text()),a.seed,a.drift)))
