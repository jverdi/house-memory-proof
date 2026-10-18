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
