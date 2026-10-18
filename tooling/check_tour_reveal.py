"""Independent source-identity, camera and timeline checks for matched reveals."""
import json
import math
from pathlib import Path
import sys
import zipfile


def check(plan, house):
    def require(ok, message):
        if not ok:raise ValueError(message)
    def vector(p):return [p[k] for k in ('x','y','z')]
    def sub(a,b):return [x-y for x,y in zip(a,b)]
    def dot(a,b):return sum(x*y for x,y in zip(a,b))
    def length(p):return math.sqrt(dot(p,p))
    def on_mesh(point, feature):
        vertices=[vector(p) for p in feature['mesh']['vertices']]
        if feature.get('segmentID'):
            segment=next(s for s in house['segments'] if s['id']==feature['segmentID'])
            matrix=segment['registration']['values']
            vertices=[[sum(matrix[row*4+k]*p[k] for k in range(3))+matrix[row*4+3] for row in range(3)] for p in vertices]
        indices=feature['mesh']['triangles']
        for i in range(0,len(indices),3):
            a,b,c=[vertices[j] for j in indices[i:i+3]]
            u,v,w=sub(b,a),sub(c,a),sub(point,a)
            uu,vv,uv,wu,wv=dot(u,u),dot(v,v),dot(u,v),dot(w,u),dot(w,v)
            determinant=uu*vv-uv*uv
            if determinant<=1e-18:continue
            x,y=(vv*wu-uv*wv)/determinant,(uu*wv-uv*wu)/determinant
            error=length([w[k]-x*u[k]-y*v[k] for k in range(3)])
            if x>=-1e-6 and y>=-1e-6 and x+y<=1+1e-6 and error<1e-6:return True
        return not indices and any(length(sub(point,p))<1e-6 for p in vertices)
    features={f['id']:f for f in house['features']}
    stages={s['id']:s for s in house['stages']}
    require(plan['sourceRevision']==house['revision'] and plan['fps']==30,'Source revision or frame rate')
    require(0<len(plan['shots'])<=1800,'Shot inventory')
    frames=0;groups={}
    for shot in plan['shots']:
        event=shot.get('reveal');require(event and event['profile']=='matched-reveal-v1','Missing reveal profile')
        require(all(event.get(k)==v for k,v in [('fadeOutStart',.15),('fadeOutEnd',.35),('restoreStart',.65),('restoreEnd',.85)]),'Invalid fade timeline')
        require(shot.get('endPosition') is None and shot.get('endYaw') is None and shot.get('endPitch') is None,'Comparison camera moved')
        require(shot.get('includesPlannedGeometry') is False and shot['layerMode']=='Finished','Unlabeled planned comparison')
        subject=shot['subject'];rough=features.get(subject['featureID'])
        require(rough and rough['revision']==subject['featureRevision'] and rough['stageID']==event['roughStageID'],'Stale rough source')
        require(rough['roomID']==shot['roomID'] and rough['kind'] in (['observed','synthetic'] if house.get('isDemo') else ['observed']),'Invalid rough source scope')
        finishes=event['finishes'];require(0<len(finishes)<=8,'Missing finish context')
        camera=vector(shot['position']);target=vector(subject['point']);yaw,pitch=shot['yaw'],shot['pitch']
        forward=[-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)]
        right=[math.cos(yaw),math.sin(yaw),0];up=[right[1]*forward[2],-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]]
        for item in [subject,*finishes]:
            feature=features.get(item['featureID']);point=vector(item['point']);delta=sub(point,camera);depth=dot(delta,forward)
            require(feature and feature['revision']==item['featureRevision'] and feature['roomID']==shot['roomID'],'Stale source identity')
            require(on_mesh(point,feature),'Target is not on source geometry')
            require(.35<=length(delta)<=30 and depth>.03,'Target range')
            half=math.tan(math.radians(65)/2)*.75
            require(abs(dot(delta,right))<=depth*half*plan['width']/plan['height'] and abs(dot(delta,up))<=depth*half,'Target outside frame')
            if item is not subject:
                require(feature['trade'] in ['Wall finish','Ceiling'] and feature['stageID'] in event['finishedStageIDs'],'Wrong finish source')
                require(feature['kind'] in (['observed','synthetic'] if house.get('isDemo') else ['observed']),'Planned finish source')
                ray=sub(target,camera);fraction=dot(delta,ray)/dot(ray,ray)
                require(0<fraction<1 and length([delta[k]-fraction*ray[k] for k in range(3)])<1e-6,'Finish is not between camera and evidence')
        require(event['roughStageID'] in stages and set(event['finishedStageIDs'])<=stages.keys(),'Missing stage identity')
        n=shot['duration']*30;require(abs(n-round(n))<1e-6 and 1<=n<=150,'Invalid chunk frames');frames+=round(n)
        key=(shot['roomID'],subject['featureID']);previous=groups.get(key)
        if previous:
            require(shot['position']==previous['position'] and shot['yaw']==previous['yaw'] and shot['pitch']==previous['pitch'] and event==previous['reveal'],'Camera or events changed at chunk boundary')
            require(abs(shot['startPhase']-previous['endPhase'])<1e-9,'Reveal timeline gap')
        else:require(shot['startPhase']==0,'Reveal does not start in finished context')
        require(0<=shot['startPhase']<shot['endPhase']<=1,'Invalid phase interval');groups[key]=shot
    require(all(s['endPhase']==1 for s in groups.values()),'Finish context not restored')
    return dict(passed=True,reader='Independent Python matched-reveal reader',shots=len(plan['shots']),frames=frames,comparisons=len(groups),sourceIdentitiesVerified=True,sameCameraVerified=True,fadeTimelineVerified=True,rawSourceRecordsPublished=False,physicalQualification=False)


if __name__=='__main__':
    with zipfile.ZipFile(sys.argv[1]) as archive:house=json.loads(archive.read('house.json'))
    report=check(json.loads(Path(sys.argv[2]).read_text()),house)
    Path(sys.argv[3]).write_text(json.dumps(report,indent=2)+'\n')
