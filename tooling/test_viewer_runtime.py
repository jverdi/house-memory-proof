import copy
import unittest
from check_viewer_runtime import read_reports, InvalidRuntime, BOUNDS


def fixture():
    sample = dict(elapsedSeconds=0, rendering=dict(callbacks=0, intervals=0, seconds=0, maximumSeconds=0, bins=[0]*9),
                  displayedVertices=100, residentTiles=1, decodedTextures=0, navigationWaiting=False,
                  memoryWarnings=0, thermalState='nominal', lowPowerMode=False, processMemory={})
    later = copy.deepcopy(sample)
    later.update(elapsedSeconds=10, rendering=dict(callbacks=301, intervals=300, seconds=10, maximumSeconds=1/30, bins=[0,0,300,0,0,0,0,0,0]))
    return [dict(version=1, physicalQualification=False, intervalUpperBoundsSeconds=BOUNDS, sessionID='s', projectID='p',
                 projectRevision=1, sourceRevision='test', build='test', hardware='analytic', systemVersion='test', platform='synthetic',
                 startedUTC=0, samples=[sample, later])]


class ViewerRuntimeTests(unittest.TestCase):
    def test_incomplete_and_unknown_resources_remain_explicit(self):
        result = read_reports(fixture())
        sample = result['sessions'][0]
        self.assertFalse(sample['finalized'])
        self.assertIsNone(sample['sampledPhysicalFootprintPeakBytes'])
        self.assertEqual(sample['renderIntervalP95UpperBoundSeconds'], 1/30)
        self.assertFalse(result['physicalQualification'])
        self.assertFalse(result['presentedFrameRateMeasured'])

    def test_overflow_is_not_a_fake_percentile(self):
        value = fixture()
        value[0]['samples'][-1]['rendering'].update(seconds=600, maximumSeconds=2, bins=[0]*8+[300])
        result = read_reports(value)['sessions'][0]
        self.assertIsNone(result['renderIntervalP95UpperBoundSeconds'])
        self.assertEqual(result['intervalsOver100ms'], 300)

    def test_corrupt_counters_histograms_and_resources_are_refused(self):
        changes = [('rendering', 'callbacks', -1), ('rendering', 'callbacks', True),
                   ('rendering', 'intervals', 301), ('rendering', 'bins', [300]),
                   ('rendering', 'bins', [0]*8+[2**63]), ('rendering', 'maximumSeconds', float('nan')),
                   (None, 'decodedTextures', 25), (None, 'residentTiles', 513),
                   (None, 'elapsedSeconds', 0), (None, 'processMemory', {'unknown': 3})]
        for parent, key, replacement in changes:
            with self.subTest(key=key, value=replacement):
                value = fixture();target = value[0]['samples'][-1]
                (target[parent] if parent else target)[key] = replacement
                with self.assertRaises(InvalidRuntime):read_reports(value)

    def test_finalization_and_identity_are_required(self):
        value = fixture();value[0].update(endedUTC=10, stopReason='viewer-inactive')
        self.assertTrue(read_reports(value)['sessions'][0]['finalized'])
        for change in [dict(physicalQualification=True), dict(stopReason=None), dict(endedUTC=-1), dict(intervalUpperBoundsSeconds=[1])]:
            bad=copy.deepcopy(value);bad[0].update(change)
            with self.assertRaises(InvalidRuntime):read_reports(bad)
        with self.assertRaises(InvalidRuntime):read_reports(value+value)

    def test_reset_between_samples_is_refused(self):
        value=fixture();last=copy.deepcopy(value[0]['samples'][0]);last['elapsedSeconds']=20;value[0]['samples'].append(last)
        with self.assertRaises(InvalidRuntime):read_reports(value)


if __name__ == '__main__':unittest.main()
