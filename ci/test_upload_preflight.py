import unittest
from upload_preflight import existing_state

class UploadPreflightTests(unittest.TestCase):
    def build(self,state='VALID',version='161.1'):
        return {'attributes':dict(version=version,processingState=state)}
    def test_new_number_can_upload(self):
        self.assertEqual(existing_state([],'161.1'),'absent')
        self.assertEqual(existing_state([self.build(version='160.1')],'161.1'),'absent')
    def test_retry_reuses_valid_or_processing_upload(self):
        for state in ['VALID','PROCESSING']:
            self.assertEqual(existing_state([self.build(state)],'161.1'),state.lower())
    def test_failed_or_ambiguous_upload_requires_new_attempt(self):
        for records in [[self.build('FAILED')],[self.build('INVALID')],[self.build(),self.build()]]:
            with self.assertRaises(RuntimeError):existing_state(records,'161.1')

if __name__=='__main__':unittest.main()
