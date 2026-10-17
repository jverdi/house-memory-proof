import unittest
from verify_archive import validate

class SignedReleaseTests(unittest.TestCase):
    def setUp(self):
        self.info=dict(CFBundleIdentifier='com.example.fixture',CFBundleVersion='7.1',ProofSourceRevision='abc0123456',UIBackgroundModes=['processing'])
        self.signed={'application-identifier':'TESTTEAM01.com.example.fixture','com.apple.developer.team-identifier':'TESTTEAM01','get-task-allow':False}
    def check(self):validate(self.info,self.signed,'com.example.fixture','TESTTEAM01','7.1','abc01234567890')
    def test_matching_identity_passes(self):self.check()
    def test_wrong_source_build_or_bundle_is_refused(self):
        for key in ['CFBundleIdentifier','CFBundleVersion','ProofSourceRevision']:
            with self.subTest(key=key):
                old=self.info[key];self.info[key]='wrong'
                with self.assertRaises(ValueError):self.check()
                self.info[key]=old
    def test_wrong_team_or_debug_signing_is_refused(self):
        for key,value in [('application-identifier','OTHER.com.example.fixture'),('com.apple.developer.team-identifier','OTHER'),('get-task-allow',True)]:
            with self.subTest(key=key):
                old=self.signed[key];self.signed[key]=value
                with self.assertRaises(ValueError):self.check()
                self.signed[key]=old
    def test_undeclared_background_resources_are_refused(self):
        self.info['UIBackgroundModes']=['audio']
        with self.assertRaises(ValueError):self.check()
        self.info['UIBackgroundModes']=['processing'];self.signed['com.apple.developer.background-tasks.continued-processing.gpu']=True
        with self.assertRaises(ValueError):self.check()

if __name__=='__main__':unittest.main()
