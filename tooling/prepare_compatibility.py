"""Recover exact earlier-writer synthetic archive bytes for native compatibility."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import zlib

ROOT=Path(__file__).resolve().parents[1]


def materialize(output):
    fixture=json.loads((ROOT/'fixtures/compatibility/testflight-source-161-1.json').read_text())
    if fixture['schema']!=1 or fixture['encoding']!='zlib-base64' or fixture['archiveBytes']!=795929:
        raise ValueError('Unsupported earlier-writer fixture')
    compressed=base64.b64decode(fixture['data'],validate=True)
    decoder=zlib.decompressobj();raw=decoder.decompress(compressed,fixture['archiveBytes']+1)
    if len(raw)!=fixture['archiveBytes'] or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError('Earlier-writer byte inventory differs')
    if hashlib.sha256(raw).hexdigest()!=fixture['archiveSHA256']:
        raise ValueError('Earlier-writer archive digest differs')
    output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(raw)
    return {key:value for key,value in fixture.items() if key!='data'}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    print(json.dumps(materialize(args.output),sort_keys=True))
