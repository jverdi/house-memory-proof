import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import warnings
import zipfile
from package_check import check_package, InvalidPackage


def fixture():
    room, stage, segment, feature, observation = [str(uuid.uuid4()) for _ in range(5)]
    raw = b'original image bytes'
    key = hashlib.sha256(raw).hexdigest()+'.jpg'
    pose = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    house = dict(schema=1,id=str(uuid.uuid4()),revision=4,
        rooms=[dict(id=room,origin=dict(x=0,y=0,z=0),size=dict(x=3,y=4,z=2.5))],
        stages=[dict(id=stage)],segments=[dict(id=segment,roomID=room,stageID=stage,registration=dict(values=pose))],
        features=[dict(id=feature,roomID=room,stageID=stage,segmentID=segment,
                      mesh=dict(vertices=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0),dict(x=0,y=1,z=0)],triangles=[0,1,2]))],
        observations=[dict(id=observation,roomID=room,stageID=stage,segmentID=segment,image=key,camera=pose,
                           intrinsics=[100,0,60,0,100,40,0,0,1],width=120,height=80,timestamp=1)])
    return house, {'assets/'+key:raw}


def archive(path, house, payload, modify=None):
    parts = {'house.json':json.dumps(house).encode(), 'index.html':b'index', 'viewer.html':b'viewer', **payload}
    manifest = dict(format='HouseXray',version=1,sha256={k:hashlib.sha256(v).hexdigest() for k,v in parts.items()})
    parts['manifest.json'] = json.dumps(manifest).encode()
    if modify:
        modify(parts)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as out:
        for name,data in parts.items():
            out.writestr(name,data)


class PortablePackageContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'house.hxray'
        self.house, self.parts = fixture()

    def test_actual_inventory_hashes_and_semantics_without_extraction(self):
        archive(self.path,self.house,self.parts)
        before = self.path.read_bytes()
        report = check_package(self.path)
        self.assertTrue(report['passed'])
        self.assertEqual(report['verifiedOriginals'],1)
        self.assertEqual(report['semanticCounts']['triangles'],1)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(list(Path(self.temp.name).iterdir()),[self.path])

    def test_changed_original_and_incomplete_manifest_fail(self):
        for mutate in [lambda p:p.__setitem__(next(iter(self.parts)),b'changed'),
                       lambda p:p.__setitem__('unlisted.txt',b'forgotten'),
                       lambda p:p.pop(next(iter(self.parts)))]:
            archive(self.path,self.house,self.parts,mutate)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_point_provenance_requires_existing_same_session_originals(self):
        source=self.house['observations'][0]
        self.house['observations']=[dict(source,id=str(uuid.uuid4())) for _ in range(3)]
        controls=[dict(observationID=o['id'],u=.5,v=.4) for o in self.house['observations']]
        feature=self.house['features'][0];feature['sourceIDs']=[c['observationID'] for c in controls]
        feature['pointTracks']=[dict(controls=copy.deepcopy(controls)) for _ in feature['mesh']['vertices']]
        feature['photoControls']=copy.deepcopy(controls)
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])
        for mode in ['missing','different-session','unlisted','bad-coordinate','missing-track','duplicate']:
            house=copy.deepcopy(self.house);item=house['features'][0]
            if mode=='missing':
                identifier=str(uuid.uuid4());item['sourceIDs'].append(identifier);item['pointTracks'][0]['controls'][0]['observationID']=identifier
            elif mode=='different-session':
                other=dict(house['segments'][0],id=str(uuid.uuid4()));house['segments'].append(other);house['observations'][0]['segmentID']=other['id']
            elif mode=='unlisted':item['sourceIDs']=[]
            elif mode=='bad-coordinate':item['photoControls'][0]['u']=1.1
            elif mode=='missing-track':item['pointTracks'].pop()
            else:item['pointTracks'][0]['controls'][1]=item['pointTracks'][0]['controls'][0]
            archive(self.path,house,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_single_photo_annotations_keep_2d_coordinates_and_refuse_malformed_marks(self):
        points=[dict(u=.1,v=.2),dict(u=.8,v=.7),dict(u=.3,v=.9)]
        marks=[dict(id=str(uuid.uuid4()),kind=kind,points=points[:count],label='Visible only',reviewed=False)
               for kind,count in [('point',1),('box',2),('polygon',3),('curve',3)]]
        photo=dict(id=str(uuid.uuid4()),image=self.house['observations'][0]['image'],annotations=marks)
        self.house['documentaryPhotos']=[photo]
        archive(self.path,self.house,self.parts)
        self.assertEqual(check_package(self.path)['semanticCounts']['imageAnnotations'],4)
        for mode in ['bounds','count','duplicate','unknown','zero-box','repeated-curve','collinear','room','label']:
            house=copy.deepcopy(self.house);photo=house['documentaryPhotos'][0];marks=photo['annotations']
            if mode=='bounds':marks[0]['points'][0]['u']=-.1
            elif mode=='count':marks[2]['points'].pop()
            elif mode=='duplicate':marks.append(marks[0])
            elif mode=='unknown':marks[0]['kind']='3d-point'
            elif mode=='zero-box':marks[1]['points'][1]=marks[1]['points'][0]
            elif mode=='repeated-curve':marks[3]['points'][1]=marks[3]['points'][0]
            elif mode=='collinear':marks[2]['points']=[dict(u=x,v=x) for x in [.1,.2,.3]]
            elif mode=='room':photo['roomID']=str(uuid.uuid4())
            else:marks[0]['label']='x'*4097
            archive(self.path,house,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        self.house['documentaryPhotos'][0].pop('annotations')
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])

    def test_rehashed_metadata_cannot_hide_semantic_corruption(self):
        faults = [lambda h:h['observations'][0].__setitem__('segmentID',str(uuid.uuid4())),
                  lambda h:h['features'][0]['mesh'].__setitem__('triangles',[0,1,10]),
                  lambda h:h['observations'][0]['camera'].__setitem__(0,2),
                  lambda h:h['rooms'].append(copy.deepcopy(h['rooms'][0])),
                  lambda h:h['observations'][0].__setitem__('image',hashlib.sha256(b'missing').hexdigest()+'.jpg'),
                  lambda h:h['features'][0]['mesh']['vertices'][0].__setitem__('x',float('nan'))]
        for mutate in faults:
            h=copy.deepcopy(self.house);mutate(h);archive(self.path,h,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_duplicate_zip_and_unsafe_member_fail_before_extraction(self):
        archive(self.path,self.house,self.parts)
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(self.path,'a') as out:out.writestr('house.json',b'{}')
        with self.assertRaisesRegex(InvalidPackage,'Duplicate ZIP'):check_package(self.path)
        for name in ['../escape','/absolute','a/../b','a\\b']:
            archive(self.path,self.house,{**self.parts,name:b'payload'})
            with self.assertRaisesRegex(InvalidPackage,'Unsafe'):check_package(self.path)

    def test_duplicate_json_and_unreferenced_original_fail(self):
        archive(self.path,self.house,self.parts,lambda p:p.__setitem__('manifest.json',b'{"version":1,"version":2}'))
        with self.assertRaisesRegex(InvalidPackage,'Duplicate JSON'):check_package(self.path)
        extra=b'unreferenced';key='assets/'+hashlib.sha256(extra).hexdigest()+'.jpg'
        archive(self.path,self.house,{**self.parts,key:extra})
        with self.assertRaisesRegex(InvalidPackage,'inventory mismatch'):check_package(self.path)


if __name__=='__main__':unittest.main()
