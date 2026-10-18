"""Independent source-route and explicit-link checks for a native service tour."""
import json
import math
from pathlib import Path
import sys
import zipfile


def check(plan,house):
    def require(ok,message):
        if not ok:raise ValueError(message)
    def vector(p):return [p[k] for k in ('x','y','z')]
    def dot(a,b):return sum(x*y for x,y in zip(a,b))
    features={f['id']:f for f in house['features']}
    segments={s['id']:s for s in house.get('segments',[])}
    connections={c['id']:c for c in house.get('connections',[])}
    require(plan['sourceRevision']==house['revision'] and plan['fps']==30,'Wrong source revision or frame rate')
    require(0<len(plan['shots'])<=1800,'Missing or oversized shot inventory')
    require(len(connections)==len(house.get('connections',[])) and len(features)==len(house['features']),'Ambiguous source identities')
    frames=0;groups={};endpoints=set()
    for shot in plan['shots']:
        event=shot.get('serviceInspection');subject=shot.get('subject')
        require(event and event['profile']=='reviewed-route-v1' and subject,'Missing service inspection')
        feature=features.get(subject['featureID'])
        require(feature and feature['revision']==subject['featureRevision'] and feature['roomID']==shot['roomID'],'Stale route identity')
        require(feature.get('reviewed') is True and not feature.get('hidden',False) and feature.get('artifactValid') is not False,'Unreviewed or inactive source')
        require(feature['kind'] in (['observed','synthetic'] if house.get('isDemo') else ['observed']),'Unsupported route evidence')
        route=feature['route'];index=event['routeIndex']
        require(2<=len(route)<=4096 and type(index) is int and 0<=index<len(route),'Invalid route point')
        point=vector(route[index])
        if feature.get('segmentID'):
            segment=segments.get(feature['segmentID']);require(segment and segment.get('registration'),'Unchecked route frame')
            m=segment['registration']['values'];point=[sum(m[row*4+k]*point[k] for k in range(3))+m[row*4+3] for row in range(3)]
        require(all(abs(a-b)<1e-9 for a,b in zip(point,vector(subject['point']))),'Inspection left its source route')
        endpoint=0 if index==0 else 1 if index==len(route)-1 else None
        require(event.get('endpoint')==endpoint and (endpoint is None or type(event['endpoint']) is int),'Incorrect endpoint designation')
        if endpoint is not None:endpoints.add((feature['id'],endpoint))
        require(shot.get('endPosition') is None and shot.get('endYaw') is None and shot.get('endPitch') is None,'Camera interpolates across a route gap')
        require(shot.get('layerMode')=='Rough-in','Wrong route stage display')
        link_ids=event['confirmedLinkIDs'];require(len(link_ids)==len(set(link_ids)),'Duplicate connection identity')
        for identity in link_ids:
            link=connections.get(identity);require(link and link['confirmed'] is True and endpoint is not None,'Unconfirmed connection')
            ends=[(link['fromFeature'],link['fromEnd']),(link['toFeature'],link['toEnd'])]
            require(ends[0][0]!=ends[1][0] and all(type(end) is int and end in (0,1) for _,end in ends),'Invalid connection endpoint')
            require((feature['id'],endpoint) in ends,'Connection has a different endpoint')
            other=features.get(next(identity for identity,_ in ends if identity!=feature['id']))
            require(other and other.get('reviewed') is True and other['trade']==feature['trade'],'Connection has no reviewed peer in this trade')
            require(other['kind'] in (['observed','synthetic'] if house.get('isDemo') else ['observed']) and len(other.get('route',[]))>=2 and not other.get('hidden',False) and other.get('artifactValid') is not False,'Inactive connection peer')
        camera=vector(shot['position']);delta=[a-b for a,b in zip(point,camera)];yaw=shot['yaw'];pitch=shot['pitch']
        forward=[-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)]
        right=[math.cos(yaw),math.sin(yaw),0];up=[right[1]*forward[2],-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]]
        depth=dot(delta,forward);half=math.tan(math.radians(65)/2)*.75
        require(.35<=math.sqrt(dot(delta,delta))<=30 and depth>.03,'Inspection target range')
        require(abs(dot(delta,right))<=depth*half*plan['width']/plan['height'] and abs(dot(delta,up))<=depth*half,'Endpoint outside camera frame')
        n=shot['duration']*30;require(abs(n-round(n))<1e-6 and 1<=n<=150,'Invalid encoded chunk duration');frames+=round(n)
        key=(feature['id'],index);previous=groups.get(key)
        if previous:
            require(shot['position']==previous['position'] and shot['yaw']==previous['yaw'] and shot['pitch']==previous['pitch'] and event==previous['serviceInspection'],'Inspection changed across chunk boundary')
            require(abs(shot['startPhase']-previous['endPhase'])<1e-9,'Inspection timeline gap')
        else:require(shot['startPhase']==0,'Partial inspection start')
        require(0<=shot['startPhase']<shot['endPhase']<=1,'Invalid inspection phase');groups[key]=shot
    require(all(s['endPhase']==1 for s in groups.values()) and 150<=frames<=1800,'Incomplete inspection timeline')
    return dict(passed=True,reader='Independent Python service-tour reader',frames=frames,inspections=len(groups),endpoints=len(endpoints),sourceRoutesVerified=True,explicitConnectionsOnly=True,cameraCutsVerified=True,physicalQualification=False)


if __name__=='__main__':
    with zipfile.ZipFile(sys.argv[1]) as archive:house=json.loads(archive.read('house.json'))
    report=check(json.loads(Path(sys.argv[2]).read_text()),house)
    Path(sys.argv[3]).write_text(json.dumps(report,indent=2)+'\n')
