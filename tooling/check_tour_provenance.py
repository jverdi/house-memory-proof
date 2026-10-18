"""Independent digest and input-preservation check for native tour sidecars."""
import hashlib
import json
from package_check import required_assets


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def check(plan, metadata, original=None):
    def require(ok, message):
        if not ok:
            raise ValueError(message)
    def preserved(before, after):
        if isinstance(before, dict):
            return isinstance(after, dict) and all(k in after and preserved(v, after[k]) for k, v in before.items())
        if isinstance(before, list):
            return isinstance(after, list) and len(before) == len(after) and all(preserved(a,b) for a,b in zip(before,after))
        return type(before) is type(after) and before == after or type(before) in (int,float) and type(after) in (int,float) and before == after
    source = json.loads(metadata)
    proof = plan.get('provenance')
    require(isinstance(proof, dict) and proof.get('schema') == 1, 'Missing source provenance')
    require(proof.get('metadataEncoding') == 'swift-json-sorted-keys-v1', 'Unknown metadata encoding')
    require(proof.get('sourceMetadataSHA256') == digest(metadata), 'Metadata digest differs')
    if original is not None:
        retained=dict(original)
        # House upgrades older schemas in memory; the input file remains intact.
        if type(retained.get('schema')) is int and 1<=retained['schema']<=5 and source.get('schema')==5:
            retained['schema']=5
        require(preserved(retained, source), 'Native metadata changed supplied source fields')
    assets = sorted(required_assets(source))
    require(proof.get('sourceAssets') == assets, 'Original asset inventory differs')
    package = 'tour-package-v1\n'+digest(metadata)+'\n'+'\n'.join(assets)+'\n'
    require(proof.get('sourcePackageSHA256') == digest(package.encode()), 'Package digest differs')
    descriptor = proof.get('profileDescriptor')
    require(isinstance(descriptor, str) and len(descriptor) <= 4096 and descriptor.endswith('\n'), 'Invalid profile descriptor')
    require(proof.get('profileSHA256') == digest(descriptor.encode()), 'Profile digest differs')
    lines = descriptor.splitlines()
    require(lines[0] == 'tour-director-v2-source-bound' and lines[-2:] == ['fps=30','seed=0'], 'Unknown directing profile')
    require(type(proof.get('deterministicSeed')) is int and proof['deterministicSeed'] == 0, 'Seed differs')
    require(plan.get('sourceRevision') == source['revision'] and plan.get('fps') == 30, 'Source revision or frame rate differs')
    return dict(passed=True, reader='Independent Python tour source and profile digest reader', sourceMetadataVerified=True,
                originalAssetsVerified=len(assets), sourcePackageVerified=True, profileVerified=True,
                deterministicSeedVerified=True, physicalQualification=False)
