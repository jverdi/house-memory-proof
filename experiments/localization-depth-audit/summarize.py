"""Aggregate-only diagnosis of sealed development output; never publish inputs."""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import zipfile
import numpy as np

CANONICAL=np.array([[1,0,0,0],[0,0,-1,0],[0,1,0,0],[0,0,0,1]],float)


def distribution(values):
    values=np.asarray(values,dtype=float)
    values=values[np.isfinite(values)]
    return dict(count=int(values.size),p50=float(np.quantile(values,.5,method='inverted_cdf')) if values.size else None,
        p95=float(np.quantile(values,.95,method='inverted_cdf')) if values.size else None,maximum=float(values.max()) if values.size else None)


def angular_error(a,b):
    a=np.asarray(a).reshape(4,4);b=np.asarray(b).reshape(4,4)
    return math.degrees(math.acos(float(np.clip((np.trace(a[:3,:3].T@b[:3,:3])-1)/2,-1,1))))


def ray_points(pixels,k,camera,origin,geometry):
    k=np.asarray(k).reshape(3,3);camera=np.asarray(camera).reshape(4,4);origin=np.asarray(origin)
    rays=np.column_stack(((pixels[:,0]-k[0,2])/k[0,0],-(pixels[:,1]-k[1,2])/k[1,1],-np.ones(len(pixels))))@camera[:3,:3].T
    position=camera[:3,3]+origin;inverse=np.divide(1,rays,out=np.full_like(rays,np.inf),where=np.abs(rays)>1e-12);nearest=np.full(len(rays),np.inf)
    for item in geometry:
        low=np.asarray(item['low']);high=np.asarray(item['high'])
        with np.errstate(invalid='ignore'):a=(low-position)*inverse;b=(high-position)*inverse
        enter=np.minimum(a,b);leave=np.maximum(a,b)
        for axis in range(3):
            parallel=np.abs(rays[:,axis])<=1e-12;inside=low[axis]<=position[axis]<=high[axis]
            enter[parallel,axis]=-np.inf if inside else np.inf;leave[parallel,axis]=np.inf if inside else -np.inf
        near=enter.max(axis=1);far=leave.min(axis=1);hit=np.where(near>1e-8,near,far)
        good=(far>=near)&(hit>1e-8)&(hit<=5)&(hit<nearest);nearest[good]=hit[good]
    valid=np.isfinite(nearest);points=np.full((len(rays),3),np.nan);points[valid]=position+rays[valid]*nearest[valid,None]-origin
    return points,valid


def project(points,camera,k):
    camera=np.asarray(camera).reshape(4,4);k=np.asarray(k).reshape(3,3)
    local=(points-camera[:3,3])@camera[:3,:3];z=-local[:,2]
    with np.errstate(invalid='ignore',divide='ignore'):
        return np.column_stack((k[0,0]*local[:,0]/z+k[0,2],-k[1,1]*local[:,1]/z+k[1,2]))


def matches(source,query):
    # Exact 256-bit Hamming distance, original ratio/absolute/mutual checks.
    source=np.frombuffer(source,dtype='<u8').reshape(-1,4);query=np.frombuffer(query,dtype='<u8').reshape(-1,4)
    if len(source)<2 or len(query)<2:return np.empty((0,2),int)
    forward=[];reverse_distance=np.full(len(source),257);reverse_query=np.full(len(source),-1)
    for start in range(0,len(query),64):
        distances=np.bitwise_count(query[start:start+64,None,:]^source[None,:,:]).sum(axis=2)
        best=np.argmin(distances,axis=1);first=distances[np.arange(len(best)),best];second=np.partition(distances,1,axis=1)[:,1]
        for i in range(len(best)):
            if first[i]<=64 and first[i]<.75*second[i]:forward.append((int(best[i]),start+i))
        local=np.argmin(distances,axis=0);value=distances[local,np.arange(len(source))];changed=value<reverse_distance
        reverse_distance[changed]=value[changed];reverse_query[changed]=start+local[changed]
    return np.asarray([(s,q) for s,q in forward if reverse_query[s]==q],int).reshape(-1,2)


def summarize(report_file):
    report_file=Path(report_file);audit=report_file.with_suffix('.audit');report=json.loads(report_file.read_text());oracle=json.loads((audit/'oracle.json').read_text())
    sealed=json.loads((audit/'sealed-candidate.json').read_text())
    assert sealed['oracleReadDenied'] and sealed['queryLabelsExcluded'] and sealed['candidateBinarySHA256']==report['candidateBinarySHA256']
    images=json.loads((audit/'images.json').read_text());names=json.loads((audit/'query-names.json').read_text())
    with zipfile.ZipFile(audit/'input.hxray') as z:house=json.loads(z.read('house.json'));manifest_sha=hashlib.sha256(z.read('manifest.json')).hexdigest()
    source_images={s['observationID']:s for s in images['sources']};query_images={names[q['image']]:q for q in images['queries']};observations={o['id']:o for o in house['observations']};segments={s['id']:s for s in house['segments']};layout={r['room']:r for r in oracle['completeLayout']}
    geometry=oracle['oracleOnlyFinishedGeometry'];source_positions=[];source_angles=[];point_errors=[];maps={};matched_ray_count=0;unmatched_ray_count=0
    for path in sorted(audit.glob('map-*.json')):
        m=json.loads(path.read_text());assert m['frameID']==m['segmentID']
        room=segments[m['segmentID']]['roomID'];origin=layout[room]['origin'];points=np.array([[p['x'],p['y'],p['z']] for p in m['points']]);descriptors=base64.b64decode(m['descriptors']);ideal=np.full(points.shape,np.nan)
        for view in m['views']:
            image=source_images[view['observationID']];o=observations[view['observationID']];true_native=np.asarray(oracle['mappingCameras'][o['id']]).reshape(4,4);solved=np.asarray(image['camera']).reshape(4,4)
            source_positions.append(float(np.linalg.norm(solved[:3,3]-true_native[:3,3])));source_angles.append(angular_error(solved,true_native))
            raw=base64.b64decode(image['descriptors']);xy=np.array(image['xy']).reshape(-1,2)*[o['width'],o['height']]
            lookup={raw[i*32:(i+1)*32]:xy[i] for i in range(image['count'])}
            start=view['start'];count=view['count'];pixels=np.array([lookup[descriptors[i*32:(i+1)*32]] for i in range(start,start+count)])
            truth,valid=ray_points(pixels,o['intrinsics'],CANONICAL@true_native,origin,geometry);ideal[start:start+count]=truth
            matched_ray_count+=int(valid.sum());unmatched_ray_count+=int((~valid).sum());point_errors.extend(np.linalg.norm(points[start:start+count][valid]-truth[valid],axis=1).tolist())
        maps[m['segmentID']]=(m,points,ideal,descriptors)
    expected={q['image']:q for q in oracle['queries']};pose_positions=[];pose_angles=[];map_pixel_errors=[];ideal_pixel_errors=[];filtered_bias=[];correspondences=0
    for query in report['queries']:
        q=expected[query['image']]
        if not q['shouldMatch'] or not query['accepted']:continue
        truth=np.asarray(q['expectedCamera']).reshape(4,4);pose=np.asarray(query['worldFromARCamera']).reshape(4,4)
        pose_positions.append(float(np.linalg.norm(pose[:3,3]-truth[:3,3])));pose_angles.append(angular_error(pose,truth))
        image=query_images[q['image']];xy=np.array(image['xy']).reshape(-1,2)*[q['width'],q['height']];qdesc=base64.b64decode(image['descriptors'])
        m,points,ideal,descriptors=maps[q['segmentID']]
        for view in m['views']:
            start=view['start'];count=view['count'];pairs=matches(descriptors[start*32:(start+count)*32],qdesc)
            if not len(pairs):continue
            index=start+pairs[:,0];valid=np.isfinite(ideal[index]).all(axis=1);index=index[valid];qi=pairs[:,1][valid]
            residual=project(points[index],truth,q['intrinsics'])-xy[qi];ideal_residual=project(ideal[index],truth,q['intrinsics'])-xy[qi]
            error=np.linalg.norm(residual,axis=1);ideal_error=np.linalg.norm(ideal_residual,axis=1)
            map_pixel_errors.extend(error.tolist());ideal_pixel_errors.extend(ideal_error.tolist());correspondences+=len(qi)
            filtered_bias.extend(ideal_residual[ideal_error<=2.5].tolist())
    bias=np.array(filtered_bias)
    return dict(candidateBinarySHA256=report['candidateBinarySHA256'],inputManifestSHA256=manifest_sha,oracleReadDenied=True,queryLabelsExcluded=True,
        positiveQueries=report['positiveQueries'],positiveAccepted=report['positiveAccepted'],criticalQueries=report['negativeQueries'],criticalFalseAccepts=report['falseAccepts'],originalGatePassed=report['passed'],
        sourceCameraPositionErrorMetres=distribution(source_positions),sourceCameraAngleErrorDegrees=distribution(source_angles),
        mapFeatureErrorFromSourceRayMetres=distribution(point_errors),sourceRaysIntersectingTruth=matched_ray_count,sourceRaysWithoutTruth=unmatched_ray_count,
        queryPositionErrorMetres=distribution(pose_positions),queryAngleErrorDegrees=distribution(pose_angles),
        descriptorCorrespondences=correspondences,mapPointReprojectionErrorPixels=distribution(map_pixel_errors),sourceRayCorrespondenceErrorPixels=distribution(ideal_pixel_errors),
        correspondenceBiasWithinExistingPixelThreshold=dict(count=len(bias),meanPixels=bias.mean(axis=0).tolist() if len(bias) else None),
        limitations=['Development analysis only; no shipping estimator or gate changed','Source-ray correspondence errors precede runtime RANSAC inlier selection','Ray intersections are an analytic diagnostic, not physical feature truth or a precision certificate','No source identities, poses, images or point arrays are included in this report'])


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args();r=summarize(a.input);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
