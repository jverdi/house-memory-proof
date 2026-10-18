"""Independent archive/adaptor admission checks, not a reconstruction score."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np


def check(folder):
    folder=Path(folder);oracle=json.loads((folder/'vision-queries.json').read_text())
    with zipfile.ZipFile(folder/'vision-map.hxray') as z:
        names=z.namelist()
        assert len(names)==len(set(names))
        assert set(names)=={'house.json','manifest.json'}|{n for n in names if n.startswith('assets/')}
        assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names)
        manifest=json.loads(z.read('manifest.json'));house=json.loads(z.read('house.json'))
        assert set(manifest['sha256'])==set(names)-{'manifest.json'}
        for n,h in manifest['sha256'].items():assert hashlib.sha256(z.read(n)).hexdigest()==h
        prohibited={'layout','topologySignature','expectedCamera','mappingCameras','seed','services','stairs','windows','clutter','materialFamily','sceneVariant','captureLedger','shouldMatch','oracleOnlyGeometry','truthIntrinsics','visibleSurfaceSamples'}
        def walk(value):
            if isinstance(value,dict):
                assert not prohibited.intersection(value)
                for v in value.values():walk(v)
            elif isinstance(value,list):
                for v in value:walk(v)
        walk(house)
        segments={s['id']:s for s in house['segments']};rooms={r['id']:r for r in house['rooms']};stages={s['id'] for s in house['stages']}
        assert len(segments)==oracle['expectedMapCount']<=24
        assert len(segments)==len(rooms) and oracle['mapStage'] in ['rough','finished']
        assert not house['features'] and all(r['isDesign'] and r['origin']==dict(x=0.,y=0.,z=0.) for r in house['rooms'])
        assert all(not s.get('registration') and not s['referencePoses'] for s in segments.values())
        observed=set()
        for o in house['observations']:
            s=segments[o['segmentID']];assert s['roomID']==o['roomID'] and s['stageID']==o['stageID'] and o['stageID'] in stages
            count=o['depthWidth']*o['depthHeight'];depth=z.read('assets/'+o['depth']);confidence=z.read('assets/'+o['confidence'])
            assert len(depth)==count*4 and len(confidence)==count
            measured=np.frombuffer(depth,dtype='<f4');mask=np.frombuffer(confidence,dtype=np.uint8)
            assert np.isfinite(measured).all() and np.all(mask<=2) and np.all(measured[mask==0]==0)
            metadata=o['captureMetadata']
            assert metadata['version']==1 and metadata['source']=='analytic-replay' and metadata['kind']=='rgbd_posed'
            assert metadata['frameTimestamp']==o['timestamp'] and metadata['calibrationWidth']==o['width'] and metadata['calibrationHeight']==o['height']
            assert metadata['receiptUptimeAfterUTC']>=metadata['receiptUptimeBeforeUTC']>=0
            assert {'frameToUTC','motionTimestamp','distortion','exif','pixelFormat'}<=set(metadata['unavailable'])
            observed.add(o['id']);assert o['id'] in oracle['mappingCameras']
        assert observed==set(oracle['mappingCameras'])
        assert len({q['image'] for q in oracle['queries']})==len(oracle['queries'])
        for q in oracle['queries']:
            assert q['segmentID'] in segments and (folder/q['image']).is_file()
            m=np.array(q['expectedCamera']).reshape(4,4);assert np.isfinite(m).all() and np.allclose(m[3],[0,0,0,1])
        result=dict(passed=True,sourcePhotographs=len(observed),rooms=len(rooms),maps=len(segments),assets=len(names)-2,
            nominalQueries=sum(q['shouldMatch'] for q in oracle['queries']),criticalQueries=sum(not q['shouldMatch'] for q in oracle['queries']),
            oracleFieldsExcluded=True,allOriginalHashesVerified=True,physicalQualification=False)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('folder',type=Path);a=p.parse_args();print(json.dumps(check(a.folder)))
