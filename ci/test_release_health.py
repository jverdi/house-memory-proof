import copy
import datetime as dt
import unittest
from unittest.mock import patch
from release_health import summarize, release, collect_live

NOW=dt.datetime(2026,10,18,tzinfo=dt.timezone.utc)
SOURCE='a'*40
POLICY=dict(automatic_renewal=False,release_tag='personal-beta')


def snapshot():
    return dict(checkedUTC=NOW.isoformat(),apple=dict(readAccessVerified=True,builds=[dict(attributes=dict(
        version='161.1',processingState='VALID',expired=False,uploadedDate=(NOW-dt.timedelta(days=1)).isoformat(),expirationDate=(NOW+dt.timedelta(days=89)).isoformat()))]),
        github=dict(readAccessVerified=True,source=SOURCE,runs=[dict(id=1,name='Build and deliver House Proof',head_sha=SOURCE,status='completed',conclusion='success')]))


class ReleaseHealthContracts(unittest.TestCase):
    def test_valid_beta_does_not_claim_acceptance_or_physical_installation(self):
        result=summarize(snapshot(),POLICY,NOW)
        self.assertTrue(result['passed']);self.assertEqual(result['buildAgeDays'],1)
        self.assertEqual(result['daysUntilExpiry'],89)
        self.assertFalse(result['automaticRenewal']);self.assertIsNone(result['releaseAccepted']);self.assertFalse(result['releaseAcceptanceEvaluated'])
        self.assertFalse(result['physicalInstallationVerified'])

    def test_monitor_does_not_wait_for_itself_or_skipped_readiness(self):
        s=snapshot()
        s['github']['runs'] += [dict(id=2,name='Inspect release health',head_sha=SOURCE,status='in_progress',conclusion=None),dict(id=3,name='Inspect TestFlight readiness',head_sha=SOURCE,status='completed',conclusion='skipped')]
        self.assertTrue(summarize(s,POLICY,NOW)['passed'])

    def test_stale_missing_pending_and_failed_ci_cannot_pass(self):
        for mutation in [lambda s:s.__setitem__('checkedUTC',(NOW-dt.timedelta(days=2)).isoformat()),
                         lambda s:s['github'].__setitem__('runs',[]),
                         lambda s:s['github']['runs'][0].__setitem__('status','in_progress'),
                         lambda s:s['github']['runs'][0].__setitem__('head_sha','b'*40),
                         lambda s:s['github']['runs'].append(dict(id=2,name='Whole-house evaluation',head_sha=SOURCE,status='completed',conclusion='failure'))]:
            s=snapshot();mutation(s);self.assertFalse(summarize(s,POLICY,NOW)['passed'])

    def test_expired_beta_and_close_expiry_are_explicit(self):
        s=snapshot();s['apple']['builds'][0]['attributes']['expirationDate']=(NOW-dt.timedelta(seconds=1)).isoformat()
        r=summarize(s,POLICY,NOW);self.assertFalse(r['passed']);self.assertTrue(r['refreshDue'])
        s=snapshot();s['apple']['builds'][0]['attributes']['expirationDate']=(NOW+dt.timedelta(days=6)).isoformat()
        r=summarize(s,POLICY,NOW);self.assertTrue(r['refreshDue']);self.assertEqual(r['expiryWarningDays'],7)
        self.assertFalse(r['automaticRenewal'])

    def test_unavailable_credentials_are_unknown_without_sensitive_exception_text(self):
        secret='DO-NOT-PRINT-A-TOKEN'
        with patch('release_health.make_token',side_effect=RuntimeError(secret)),patch('release_health.github',side_effect=RuntimeError(secret)):
            s=collect_live(NOW)
        r=summarize(s,POLICY,NOW)
        self.assertFalse(r['passed']);self.assertIsNone(r['refreshDue']);self.assertNotIn(secret,str(r))
        self.assertFalse(s['apple']['networkAttempted'])

    def test_release_reference_mismatch_never_dispatches(self):
        with patch('release_health.github',return_value=dict(sha='b'*40)) as api:
            with self.assertRaisesRegex(ValueError,'does not match'):release(SOURCE,dispatch=True)
            self.assertEqual(api.call_count,1)
            self.assertNotIn('POST',str(api.call_args_list))

    def test_unaccepted_shipping_is_blocked_before_network(self):
        with patch('release_health.github') as api:
            with self.assertRaisesRegex(ValueError,'acceptance gates'):release(SOURCE,ref='personal-beta',ship=True,dispatch=True)
            api.assert_not_called()

    def test_validation_dispatch_never_claims_delivery(self):
        with patch('release_health.github',side_effect=[dict(sha=SOURCE),{}]) as api:
            r=release(SOURCE,dispatch=True)
            self.assertTrue(r['dispatched']);self.assertFalse(r['testflightDeliveryVerified'])
            self.assertEqual(api.call_args.kwargs['body']['inputs']['ship'],'false')


if __name__=='__main__':unittest.main()
