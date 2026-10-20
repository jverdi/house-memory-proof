"""Compare validated before/after archives without claiming a signed install occurred.

Run in this repository. Input archives are never extracted or changed. The
aggregate output excludes project names, IDs, asset paths and captured content.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tooling'))
from package_check import MAX_ARCHIVE, check_package, json_bytes, require


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    require(path.is_file() and path.stat().st_size <= MAX_ARCHIVE, 'Input is absent or exceeds the archive budget')
    original = digest(path)
    checked = check_package(path)
    with zipfile.ZipFile(path) as archive:
        house = json_bytes(archive.read('house.json'))
        manifest = json_bytes(archive.read('manifest.json'))
        assets = {k: v for k, v in manifest['sha256'].items() if k.startswith('assets/')}
    require(digest(path) == original, 'Input archive changed during validation')
    return original, house, assets, checked


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def compare(before, after, mode='update'):
    require(mode in ('update', 'restore'), 'Unknown comparison mode')
    old_hash, old, old_assets, old_check = read(before)
    new_hash, new, new_assets, new_check = read(after)
    identity_ok = new.get('id') == old.get('id')
    if mode == 'restore':
        # Native restore deliberately creates an independent project, not an
        # overwrite. Everything except these three fields remains exact.
        identity_ok = (new.get('id') != old.get('id') and
                       new.get('name') == old.get('name', '') + ' · restored' and
                       type(new.get('revision')) is int and new['revision'] == 0)
        for key in ('id', 'name', 'revision'):
            old.pop(key, None)
            new.pop(key, None)
    changed = sum(canonical(old.get(k)) != canonical(new.get(k)) or
                  (k in old) != (k in new) for k in old.keys() | new.keys())
    metadata_ok = changed == 0
    assets_ok = old_assets == new_assets
    return dict(schema=1, scope='validated-archive-content-comparison', mode=mode,
                passed=identity_ok and metadata_ok and assets_ok,
                beforeSHA256=old_hash, afterSHA256=new_hash,
                metadataPreserved=metadata_ok, changedTopLevelFieldCount=changed,
                expectedProjectIdentity=identity_ok, originalsPreserved=assets_ok,
                beforeOriginals=len(old_assets), afterOriginals=len(new_assets),
                beforeCounts=old_check['semanticCounts'], afterCounts=new_check['semanticCounts'],
                actualSignedUpdateVerified=False, actualProviderRecoveryVerified=False,
                physicalQualification=False,
                limitation='Content comparison only. Installation, provider retrieval, and source/build evidence must be retained separately. Unexpected metadata additions also require review.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--mode', choices=('update', 'restore'), default='update')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(args.output.resolve() not in (args.before.resolve(), args.after.resolve()), 'Preserve input archives')
    report = compare(args.before, args.after, args.mode)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps(report))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
