import copy
import unittest
from check_capture_runtime import read_reports,InvalidRuntime


def fixture():
    sample=dict(elapsedSeconds=0,deliveredCameraFrames=0,normalTrackingFrames=0,renderedCallbacks=0,savedImages=0,saveFailures=0,pendingSaves=0,maximumPendingSaves=0,completedSaveSeconds=0,maximumSaveSeconds=0,memoryWarnings=0,thermalState='nominal',lowPowerMode=False,batteryState='unknown',freeDiskBytes=1000,processMemory={})
    last=dict(sample,elapsedSeconds=10,deliveredCameraFrames=300,normalTrackingFrames=290,renderedCallbacks=600,savedImages=4,saveFailures=1,maximumPendingSaves=1,completedSaveSeconds=2,maximumSaveSeconds=.8,freeDiskBytes=900,processMemory={'physicalFootprintBytes':100})
    final=dict(last,elapsedSeconds=12,savedImages=5,completedSaveSeconds=3,maximumSaveSeconds=1)
    return [dict(version=1,sessionID='session',projectID='house',mode='capture',startedUTC=100,sourceRevision='abc',build='1.1',hardware='device',systemVersion='26',platform='iPhone simulator',samples=[sample,last,final],acquisitionEndSeconds=10,endedUTC=112,stopReason='owner-stopped',physicalQualification=False,samplePeriodSeconds=10,sampleLimit=721)]


class CaptureRuntimeReader(unittest.TestCase):
    def test_rates_keep_finalization_separate_and_unknowns_explicit(self):
        result=read_reports(fixture());session=result['sessions'][0]
        self.assertFalse(result['physicalQualification']);self.assertFalse(result['presentedFrameRateMeasured'])
        self.assertEqual(session['activeIntervals'][0]['cameraCallbackHz'],30)
        self.assertEqual(session['activeIntervals'][0]['renderCallbackHz'],60)
        self.assertEqual(len(session['activeIntervals']),1)
        self.assertIsNone(session['batteryChange']);self.assertEqual(session['volumeFreeBytesChange'],-100)
        partial=fixture();partial[0].pop('endedUTC');partial[0].pop('stopReason')
        self.assertFalse(read_reports(partial)['sessions'][0]['finalized'])

    def test_malformed_and_inconsistent_evidence_refused(self):
        for field,value in [('elapsedSeconds',0),('deliveredCameraFrames',-1),('normalTrackingFrames',999),('batteryLevel',1.2),('pendingSaves',2),('maximumSaveSeconds',3),('thermalState','cold'),('lowPowerMode',1)]:
            data=fixture();data[0]['samples'][1][field]=value
            with self.subTest(field=field),self.assertRaises(InvalidRuntime):read_reports(data)
        for field,value in [('physicalQualification',True),('sampleLimit',1000),('acquisitionEndSeconds',13),('endedUTC',99)]:
            data=fixture();data[0][field]=value
            with self.subTest(field=field),self.assertRaises(InvalidRuntime):read_reports(data)
        data=fixture();data[0]['samples'][2]['savedImages']=3
        with self.assertRaises(InvalidRuntime):read_reports(data)


if __name__=='__main__':unittest.main()
