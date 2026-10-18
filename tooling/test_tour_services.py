import copy
import unittest
from check_tour_services import check


def fixture():
    def p(x,y,z):return dict(x=x,y=y,z=z)
    features=[dict(id=name,revision=3,roomID='room',kind='synthetic',trade='Electrical',reviewed=True,route=[p(0,2,0),p(1,2,0)]) for name in ['a','b']]
    link=dict(id='link',fromFeature='a',fromEnd=0,toFeature='b',toEnd=1,confirmed=True)
    shot=dict(roomID='room',position=p(0,0,0),yaw=0,pitch=0,duration=5,startPhase=0,endPhase=1,layerMode='Rough-in',subject=dict(featureID='a',featureRevision=3,point=p(0,2,0)),serviceInspection=dict(profile='reviewed-route-v1',routeIndex=0,endpoint=0,confirmedLinkIDs=['link']))
    return dict(sourceRevision=1,fps=30,width=1920,height=1080,shots=[shot]),dict(revision=1,isDemo=True,features=features,connections=[link])


class ServiceTourContracts(unittest.TestCase):
    def test_reviewed_endpoints_and_resumable_chunks(self):
        plan,house=fixture();self.assertTrue(check(plan,house)['passed'])
        first=plan['shots'][0];second=copy.deepcopy(first);first['endPhase']=.5;second['startPhase']=.5;plan['shots'].append(second)
        self.assertEqual(check(plan,house)['frames'],300)
        second['serviceInspection']['confirmedLinkIDs']=[]
        with self.assertRaises(ValueError):check(plan,house)

    def test_source_route_and_connection_faults_refused(self):
        for fault in range(17):
            with self.subTest(fault=fault):
                plan,house=fixture();shot=plan['shots'][0];feature=house['features'][0]
                if fault==0:feature['reviewed']=False
                if fault==1:feature['revision']=4
                if fault==2:feature['kind']='planned'
                if fault==3:house['connections'][0]['confirmed']=False
                if fault==4:house['connections'][0]['fromEnd']=1
                if fault==5:shot['serviceInspection']['routeIndex']=1
                if fault==6:shot['endPosition']=dict(x=0,y=0,z=0)
                if fault==7:shot['subject']['point']['x']=10
                if fault==8:feature['segmentID']='missing'
                if fault==9:house['features'][1]['trade']='Plumbing'
                if fault==10:shot['endPhase']=.5
                if fault==11:house['connections'].append(copy.deepcopy(house['connections'][0]))
                if fault==12:shot['serviceInspection']['endpoint']=False
                if fault==13:house['features'][1]['kind']='planned'
                if fault==14:house['connections'][0]['toEnd']=2
                if fault==15:house['connections'][0]['toFeature']='a'
                if fault==16:house['features'][1]['hidden']=True
                with self.assertRaises(ValueError):check(plan,house)
