import datetime as dt
import unittest
from renewal import decision,warning_days

class RenewalPolicyTests(unittest.TestCase):
    now=dt.datetime(2026,10,17,tzinfo=dt.timezone.utc)
    def build(self,age=0,remaining=None,state='VALID',expired=False):
        return {'attributes':dict(processingState=state,expired=expired,
            uploadedDate=(self.now-dt.timedelta(days=age)).isoformat(),
            expirationDate=(self.now+dt.timedelta(days=90-age if remaining is None else remaining)).isoformat())}
    def test_refresh_boundary_is_45_days_after_upload(self):
        self.assertFalse(decision([self.build(44.999)],self.now)[0])
        self.assertTrue(decision([self.build(45)],self.now)[0])
    def test_recent_replacement_resets_age(self):
        self.assertFalse(decision([self.build(80),self.build(1)],self.now)[0])
        self.assertIsNone(warning_days([self.build(80),self.build(1)],self.now))
    def test_recent_processing_prevents_duplicate_upload(self):
        self.assertFalse(decision([self.build(80),self.build(.5,state='PROCESSING')],self.now)[0])
        self.assertTrue(decision([self.build(80),self.build(2,state='PROCESSING')],self.now)[0])
    def test_expiry_warnings_and_early_expiry(self):
        for days,expected in [(31,None),(30,30),(15,30),(14,14),(8,14),(7,7),(0,7)]:
            with self.subTest(days=days):self.assertEqual(warning_days([self.build(remaining=days)],self.now),expected)
        self.assertTrue(decision([self.build(1,remaining=20)],self.now)[0])
    def test_failed_or_expired_build_does_not_hide_missing_beta(self):
        for values in [[],[self.build(state='FAILED')],[self.build(expired=True)],[self.build(remaining=-1)]]:
            self.assertTrue(decision(values,self.now)[0])

if __name__=='__main__':unittest.main()
