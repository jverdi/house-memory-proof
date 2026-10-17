import copy
import unittest
from testflight_readiness import ready_for_owner

class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.report=dict(personal_account_holder_verified=True,owner_has_testflight_access=True,target_build='161.1',builds=[dict(version='161.1',processing_state='VALID',expired=False,beta_state=dict(internalBuildState='IN_BETA_TESTING'),groups=[dict(name='Personal iPhone',internal=True)])])
    def test_verified_owner_build_is_ready(self):self.assertTrue(ready_for_owner(self.report))
    def test_upload_or_processing_alone_is_not_ready(self):
        for state in ['PROCESSING','FAILED','INVALID']:
            self.report['builds'][0]['processing_state']=state;self.assertFalse(ready_for_owner(self.report))
    def test_owner_and_group_are_required(self):
        for key in ['personal_account_holder_verified','owner_has_testflight_access']:
            changed=copy.deepcopy(self.report);changed[key]=False;self.assertFalse(ready_for_owner(changed))
        self.report['builds'][0]['groups']=[];self.assertFalse(ready_for_owner(self.report))
    def test_expired_or_unavailable_beta_is_not_ready(self):
        self.report['builds'][0]['expired']=True;self.assertFalse(ready_for_owner(self.report))
        self.report['builds'][0]['expired']=False;self.report['builds'][0]['beta_state']['internalBuildState']='PROCESSING';self.assertFalse(ready_for_owner(self.report))
    def test_wrong_or_duplicate_build_number_is_not_ready(self):
        self.report['target_build']='162.1';self.assertFalse(ready_for_owner(self.report))
        self.report['target_build']='161.1';self.report['builds']*=2;self.assertFalse(ready_for_owner(self.report))

if __name__=='__main__':unittest.main()
