import copy
import unittest
from check_tour_reveal import check


def fixture():
    def point(x,y,z):return dict(x=x,y=y,z=z)
    def feature(key,stage,trade,y):return dict(id=key,revision=1,roomID='room',stageID=stage,kind='synthetic',trade=trade,mesh=dict(vertices=[point(-1,y,-1),point(1,y,-1),point(0,y,1)],triangles=[0,1,2]))
    house=dict(revision=1,isDemo=True,stages=[dict(id='rough'),dict(id='finish')],features=[feature('target','rough','Structure',2),feature('surface','finish','Wall finish',1)])
    subject=dict(featureID='target',featureRevision=1,point=point(0,2,0))
    event=dict(profile='matched-reveal-v1',finishes=[dict(featureID='surface',featureRevision=1,point=point(0,1,0))],roughStageID='rough',finishedStageIDs=['finish'],fadeOutStart=.15,fadeOutEnd=.35,restoreStart=.65,restoreEnd=.85)
    shot=dict(roomID='room',position=point(0,0,0),yaw=0,pitch=0,duration=5,startPhase=0,endPhase=1,subject=subject,reveal=event,layerMode='Finished',includesPlannedGeometry=False)
    return dict(sourceRevision=1,fps=30,width=1920,height=1080,shots=[shot]),house


class RevealContracts(unittest.TestCase):
    def test_source_linked_reveal_and_chunk_continuity(self):
        plan,house=fixture();self.assertEqual(check(plan,house)['frames'],150)
        first=plan['shots'][0];second=copy.deepcopy(first);first['endPhase']=.5;second['startPhase']=.5;plan['shots'].append(second)
        self.assertEqual(check(plan,house)['frames'],300)
        second['position']['x']=.01
        with self.assertRaises(ValueError):check(plan,house)

    def test_refuses_stale_unframed_or_incomplete_reveals(self):
        for fault in range(9):
            with self.subTest(fault=fault):
                plan,house=fixture();shot=plan['shots'][0]
                if fault==0:house['features'][0]['revision']=2
                if fault==1:shot['endPosition']=dict(x=0,y=0,z=0)
                if fault==2:shot['reveal']['finishes']=[]
                if fault==3:shot['reveal']['restoreEnd']=.5
                if fault==4:shot['endPhase']=.8
                if fault==5:shot['reveal']['finishes'][0]['point']['y']=3
                if fault==6:shot['subject']['point']['x']=10
                if fault==7:house['features'][1]['kind']='planned'
                if fault==8:shot['reveal']['finishedStageIDs']=['rough']
                with self.assertRaises(ValueError):check(plan,house)
