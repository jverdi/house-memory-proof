import copy
import json
import unittest
from check_tour_provenance import check, digest
from test_package_check import fixture
from package_check import required_assets


class TourSourceContracts(unittest.TestCase):
    def setUp(self):
        self.house, _ = fixture()
        self.raw = json.dumps(self.house, sort_keys=True).encode()
        assets = sorted(required_assets(self.house))
        descriptor = 'tour-director-v2-source-bound\ncamera-motion-v1\nfps=30\nseed=0\n'
        self.plan = dict(sourceRevision=self.house['revision'], fps=30, provenance=dict(schema=1,
            metadataEncoding='swift-json-sorted-keys-v1',sourceMetadataSHA256=digest(self.raw),sourceAssets=assets,
            sourcePackageSHA256=digest(('tour-package-v1\n'+digest(self.raw)+'\n'+'\n'.join(assets)+'\n').encode()),
            profileDescriptor=descriptor, profileSHA256=digest(descriptor.encode()), deterministicSeed=0))

    def test_source_and_profile_digest_independence(self):
        self.assertTrue(check(self.plan, self.raw, self.house)['passed'])
        for key,value in [('sourceMetadataSHA256','0'*64),('sourcePackageSHA256','0'*64),('sourceAssets',[]),
                          ('profileDescriptor','changed'),('profileSHA256','0'*64),('deterministicSeed',False),('schema',2)]:
            with self.subTest(key=key):
                plan=copy.deepcopy(self.plan);plan['provenance'][key]=value
                with self.assertRaises(ValueError):check(plan,self.raw,self.house)
        changed=copy.deepcopy(self.house);changed['revision'] += 1
        raw=json.dumps(changed,sort_keys=True).encode()
        with self.assertRaises(ValueError):check(self.plan,raw,self.house)

    def test_input_changes_are_not_hidden_by_reencoding(self):
        changed=copy.deepcopy(self.house);changed['name']='An altered input'
        with self.assertRaises(ValueError):check(self.plan,self.raw,changed)
        supplied=dict(revision=self.house['revision'])
        self.assertTrue(check(self.plan,self.raw,supplied)['passed'])
        legacy=copy.deepcopy(self.house);legacy['schema']=1
        current=copy.deepcopy(self.house);current['schema']=5
        raw=json.dumps(current,sort_keys=True).encode();migrated=copy.deepcopy(self.plan)
        proof=migrated['provenance'];proof['sourceMetadataSHA256']=digest(raw)
        proof['sourcePackageSHA256']=digest(('tour-package-v1\n'+digest(raw)+'\n'+'\n'.join(proof['sourceAssets'])+'\n').encode())
        self.assertTrue(check(migrated,raw,legacy)['passed'])
        missing=copy.deepcopy(self.plan);missing.pop('provenance')
        with self.assertRaises(ValueError):check(missing,self.raw,self.house)


if __name__=='__main__':unittest.main()
