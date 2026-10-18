#!/usr/bin/env python3
"""Read the actual native snapshot using only Python's standard library."""
import hashlib
import json
from pathlib import Path
import re
import sys


def checked(base, kind, key, maximum):
    assert re.fullmatch(r'[0-9a-f]{64}\.[a-z0-9]+', key), 'Unsafe snapshot identity'
    path = base / kind / key
    assert path.stat().st_size <= maximum
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == key[:64], 'Object checksum mismatch'
    return data


def main(root):
    base = root / 'incremental-v2' / 'HouseXraySnapshots'
    records = list((base / 'revisions').glob('*.json'))
    assert len(records) == 1
    record = json.loads(records[0].read_text())
    assert record['format'] == 'HouseXraySnapshot' and record['version'] == 2
    assert records[0].stem == record['id']
    metadata = checked(base, 'metadata', record['metadata'], 100_000_000)
    house = json.loads(metadata)
    assert house['id'] == record['projectID'] and house['revision'] == record['revision']
    manifest = json.loads(checked(base, 'manifests', record['chunkManifest'], 32_000_000))
    assert manifest['version'] == 2 and manifest['metadata'] == record['metadata']
    assert manifest['projectID'] == record['projectID']
    assert sorted(a['key'] for a in manifest['assets']) == sorted(record['assets'])
    assert sorted(p['image'] for p in house['documentaryPhotos']) == sorted(record['assets'])
    assert len(manifest['assets']) == len(set(record['assets'])) == 2
    chunks, originals = {}, set()
    for asset in manifest['assets']:
        data = bytearray()
        for part in asset['slices']:
            key = part['chunk']
            if key not in chunks:
                chunks[key] = checked(base, 'chunks', key, 16 * 1024 * 1024)
            offset, length = part['offset'], part['length']
            assert type(offset) is int and type(length) is int
            assert 0 <= offset and 0 < length <= 16 * 1024 * 1024
            assert offset + length <= len(chunks[key])
            data.extend(chunks[key][offset:offset + length])
        assert len(data) == asset['bytes']
        assert hashlib.sha256(data).hexdigest() == asset['key'][:64]
        originals.add(bytes(data))
    assert originals == {b'first independent original', b'second independent original'}
    assert len(chunks) == 1, 'Small originals were not packed together'
    report = dict(passed=True, reader='Python standard library', formatVersion=2,
                  originalsVerified=2, packedChunks=1,
                  manifestSHA256=record['chunkManifest'][:64],
                  remoteDurabilityQualified=False, actualProviderFaultsQualified=False)
    (root / 'chunked-snapshot-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path('build/evidence'))
