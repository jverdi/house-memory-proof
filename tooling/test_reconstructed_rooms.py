import hashlib
import json
import unittest
from check_reconstructed_navigation import InvalidNavigation
from check_reconstructed_rooms import OFFSETS, read_report
from test_reconstructed_navigation import fixture as floor_fixture


def fixture():
    h = dict(isDemo=True, rooms=[], segments=[], features=[], observations=[])
    for i, offset in enumerate(OFFSETS):
        floor = floor_fixture()[1]['flat']
        room, segment = 'room-'+str(i), 'segment-'+str(i)
        h['rooms'].append(dict(id=room, level=int(i == 2)))
        h['segments'].append(dict(id=segment, roomID=room, stageID='rough', registration=dict(values=[1,0,0,offset[0],0,1,0,offset[1],0,0,1,offset[2],0,0,0,1])))
        feature = floor['features'][0]
        feature.update(id='floor-'+str(i), roomID=room, segmentID=segment, stageID='rough')
        for o in floor['observations']:
            o.update(id=str(i)+'-'+o['id'], roomID=room, segmentID=segment, stageID='rough')
        feature['sourceIDs'] = [o['id'] for o in floor['observations']]
        h['features'].append(feature);h['observations'].extend(floor['observations'])
    report = dict(version=1, profile='registered-reconstructed-fragments-v1', passed=True, fragments=3,
                  capturedViewsPerFragment=9, generatorMeshesSupplied=0, vertices=[4,4,4], links=[[0,1]],
                  missingFloorRefused=True, graphLimited=False,
                  missingFloorTrace=[dict(x=.4,y=0,z=2) for _ in range(3)],
                  registrationSupplied=True, floorClassificationSupplied=True, walkingEnabled=True,
                  upperWalkingEnabled=True, sourceGeometryUnchanged=True, wholeHouseQualified=False,
                  physicalQualification=False, protectedBenchmark=False, completedSteps=16,
                  trace=[dict(x=-.2+(i+1)*.2 if i<8 else 1.4-(i-7)*.2,y=0,z=2) for i in range(16)],
                  upperFloorJump=dict(x=.32,y=0,z=5.2))
    return report, h


def read(report, h):
    data=json.dumps(h).encode();report['privatePackageSHA256']=hashlib.sha256(data).hexdigest()
    return read_report(report,data)


class RegisteredReconstructionReader(unittest.TestCase):
    def test_scores_both_seam_directions_and_separate_floor(self):
        result=read(*fixture())
        self.assertEqual(result['tracedSteps'],16)
        self.assertEqual(result['roomBoundaryCrossings'],2)
        self.assertFalse(result['wholeHouseQualified'])

    def test_rejects_missing_support_registration_and_source_mutations(self):
        for fault in range(8):
            report,h=fixture()
            if fault==0:h['features'][1]['mesh']['vertices'][0]['x']=.5
            elif fault==1:h['segments'][1]['registration']['values'][3]=1.8
            elif fault==2:h['features'][1]['sourceIDs'].pop()
            elif fault==3:h['observations'][10]['roomID']='wrong'
            elif fault==4:h['features'][2]['geometrySource']='capturedMesh'
            elif fault==5:h['segments'][1]['stageID']='finished'
            elif fault==6:h['rooms'][2]['level']=0
            else:h['features'][1]['segmentID']=h['segments'][0]['id']
            with self.subTest(fault=fault),self.assertRaises(InvalidNavigation):read(report,h)

    def test_rejects_incomplete_false_or_broader_claims(self):
        for key,value in [('graphLimited',True),('missingFloorRefused',False),('links',[[0,1],[0,2]]),
                          ('completedSteps',15),('wholeHouseQualified',True),('registrationSupplied',False),
                          ('upperFloorJump',dict(x=0,y=0,z=2))]:
            report,h=fixture();report[key]=value
            with self.subTest(key=key),self.assertRaises(InvalidNavigation):read(report,h)
        report,h=fixture();report['trace'][5]['z']=5.2
        with self.assertRaises(InvalidNavigation):read(report,h)
        report,h=fixture();read(report,h)
        with self.assertRaises(InvalidNavigation):read_report(report,json.dumps(h).encode()+b' ')


if __name__ == '__main__':
    unittest.main()
