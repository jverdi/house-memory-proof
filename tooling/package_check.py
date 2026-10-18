"""Independent, bounded reader for a complete House Xray evidence archive.

No extraction, rendering, network access or writes to the source package. This
checks the reusable evidence contract; it does not certify captured accuracy.
"""
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat
import uuid
import zipfile

MAX_METADATA = 100_000_000
MAX_ARCHIVE = 500_000_000_000
MAX_MEMBERS = 200_010
ASSET = re.compile(r'[0-9a-f]{64}\.[A-Za-z0-9]+')


class InvalidPackage(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidPackage(message)


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON object key')
        result[key] = value
    return result


def json_bytes(data):
    def invalid_constant(_):
        raise InvalidPackage('Nonfinite JSON number')
    return json.loads(data, object_pairs_hook=object_pairs, parse_constant=invalid_constant)


def identity(value):
    require(isinstance(value, str), 'Missing identity')
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise InvalidPackage('Invalid UUID identity') from None


def numeric(value):
    return type(value) in (int, float) and math.isfinite(value)


def vector(value):
    return isinstance(value, dict) and all(numeric(value.get(k)) for k in ('x', 'y', 'z'))


def rigid(values):
    if not isinstance(values, list) or len(values) != 16 or not all(numeric(v) for v in values):
        return False
    if max(abs(values[12+i] - (1 if i == 3 else 0)) for i in range(4)) > 1e-5:
        return False
    rows = [values[i*4:i*4+3] for i in range(3)]
    if any(abs(sum(a*b for a, b in zip(rows[i], rows[j])) - (i == j)) > .002
           for i in range(3) for j in range(3)):
        return False
    a, b, c = rows
    determinant = a[0]*(b[1]*c[2]-b[2]*c[1])-a[1]*(b[0]*c[2]-b[2]*c[0])+a[2]*(b[0]*c[1]-b[1]*c[0])
    return abs(determinant-1) < .002


def required_assets(house):
    assets = set()
    def add(value):
        if value is not None:
            require(isinstance(value, str) and ASSET.fullmatch(value), 'Unsafe asset identity')
            assets.add(value)
    for observation in house.get('observations', []):
        for key in ('image', 'depth', 'confidence'):
            add(observation.get(key))
        add((observation.get('captureMetadata') or {}).get('exifAsset'))
    for group, keys in [('visualMaps', ('asset',)), ('drawings', ('asset',)),
                        ('segments', ('worldMap',)), ('references', ('image', 'pdf')),
                        ('features', ('texture',)), ('documentaryPhotos', ('image',))]:
        for item in house.get(group, []):
            for key in keys:
                add(item.get(key))
    return assets


def semantic_check(house):
    require(type(house.get('schema')) is int and house['schema'] == 1, 'Unsupported house schema')
    identity(house.get('id'))
    require(type(house.get('revision')) is int and house['revision'] >= 0, 'Invalid source revision')
    tables = {}
    limits = dict(rooms=100, features=10000, observations=50000, segments=50000,
                  stages=10000, references=1000, documentaryPhotos=50000)
    for name, limit in limits.items():
        rows = house.get(name, [])
        require(isinstance(rows, list) and len(rows) <= limit, 'Metadata count limit: '+name)
        ids = [identity(item.get('id')) for item in rows]
        require(len(set(ids)) == len(ids), 'Duplicate '+name+' identity')
        tables[name] = dict(zip(ids, rows))
    def reference(item, key, table, optional=False):
        if optional and item.get(key) is None:
            return
        require(identity(item.get(key)) in tables[table], 'Missing '+key+' relationship')
    for room in tables['rooms'].values():
        require(vector(room.get('origin')) and vector(room.get('size')) and
                all(room['size'][k] > 0 for k in ('x','y','z')), 'Invalid room dimensions')
    for segment in tables['segments'].values():
        reference(segment, 'roomID', 'rooms'); reference(segment, 'stageID', 'stages')
        if segment.get('registration') is not None:
            require(rigid(segment['registration'].get('values')), 'Nonrigid session registration')
    vertices = triangles = 0
    for feature in tables['features'].values():
        reference(feature, 'roomID', 'rooms'); reference(feature, 'stageID', 'stages')
        reference(feature, 'segmentID', 'segments', True)
        mesh = feature.get('mesh', {})
        points, indices = mesh.get('vertices'), mesh.get('triangles')
        require(isinstance(points, list) and all(vector(p) for p in points), 'Invalid mesh vertices')
        require(isinstance(indices, list) and len(indices)%3 == 0 and
                all(type(i) is int and 0 <= i < len(points) for i in indices), 'Invalid triangle topology')
        require(all(vector(p) for p in feature.get('route', [])), 'Invalid service route')
        if feature.get('uv') is not None:
            require(len(feature['uv']) == len(points) and all(numeric(p.get('u')) and numeric(p.get('v')) for p in feature['uv']), 'Invalid texture coordinates')
        vertices += len(points); triangles += len(indices)//3
    for observation in tables['observations'].values():
        for key, table in [('roomID','rooms'), ('stageID','stages'), ('segmentID','segments')]:
            reference(observation, key, table)
        segment = tables['segments'][identity(observation['segmentID'])]
        require(all(identity(observation[k]) == identity(segment[k]) for k in ('roomID','stageID')), 'Observation/session scope mismatch')
        require(rigid(observation.get('camera')), 'Nonrigid observation camera')
        k = observation.get('intrinsics')
        require(isinstance(k, list) and len(k) == 9 and all(numeric(v) for v in k) and k[0]>0 and k[4]>0, 'Invalid camera intrinsics')
        require(numeric(observation.get('timestamp')), 'Invalid capture timestamp')
        require(all(type(observation.get(k)) is int and 0 < observation[k] <= 20000 for k in ('width','height')), 'Invalid photograph dimensions')
        require(observation.get('image') is not None, 'Missing source photograph')
    for connection in house.get('connections', []):
        reference(connection, 'fromFeature', 'features'); reference(connection, 'toFeature', 'features')
        require(identity(connection['fromFeature']) != identity(connection['toFeature']), 'Self-connected service route')
        require(all(type(connection.get(k)) is int and connection[k] in (0,1) for k in ('fromEnd','toEnd')), 'Invalid service endpoint')
    for record in house.get('documentaryPhotos', []):
        require(record.get('image') is not None, 'Missing documentary image')
    return dict(rooms=len(tables['rooms']), stages=len(tables['stages']), sessions=len(tables['segments']),
                features=len(tables['features']), observations=len(tables['observations']),
                documentaryPhotos=len(tables['documentaryPhotos']), vertices=vertices, triangles=triangles,
                serviceConnections=len(house.get('connections', [])))


def check_package(path):
    path = Path(path)
    require(path.is_file(), 'Package does not exist')
    require(path.stat().st_size <= MAX_ARCHIVE, 'Archive exceeds 500 GB inspection budget')
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(0 < len(entries) <= MAX_MEMBERS, 'Invalid archive member count')
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), 'Duplicate ZIP member')
        require(all(not entry.is_dir() and not entry.flag_bits & 1 and not stat.S_ISLNK(entry.external_attr >> 16)
                    and '\\' not in entry.filename and '\x00' not in entry.filename
                    and not PurePosixPath(entry.filename).is_absolute()
                    and all(p not in ('', '.', '..') for p in entry.filename.split('/')) for entry in entries),
                'Unsafe, encrypted or symlink ZIP member')
        require(sum(entry.file_size for entry in entries) <= MAX_ARCHIVE, 'Expanded archive exceeds 500 GB budget')
        require({'manifest.json','house.json','index.html','viewer.html'}.issubset(names), 'Incomplete portable archive')
        require(archive.getinfo('manifest.json').file_size <= MAX_METADATA and archive.getinfo('house.json').file_size <= MAX_METADATA, 'Metadata exceeds 100 MB budget')
        manifest = json_bytes(archive.read('manifest.json'))
        require(manifest.get('format') == 'HouseXray' and type(manifest.get('version')) is int and manifest['version'] == 1, 'Unsupported archive manifest')
        hashes = manifest.get('sha256')
        require(isinstance(hashes, dict) and set(hashes) == set(names)-{'manifest.json'}, 'Manifest/member inventory mismatch')
        total = 0
        for name, expected in hashes.items():
            require(isinstance(expected,str) and re.fullmatch('[0-9a-f]{64}', expected), 'Invalid digest')
            hasher = hashlib.sha256(); count = 0
            with archive.open(name) as source:
                while chunk := source.read(1024*1024):
                    count += len(chunk); total += len(chunk)
                    require(count <= archive.getinfo(name).file_size and total <= MAX_ARCHIVE, 'Expanded byte budget exceeded')
                    hasher.update(chunk)
            require(count == archive.getinfo(name).file_size and hasher.hexdigest() == expected, 'Archive payload checksum mismatch')
            if name.startswith('assets/'):
                key = name[7:]
                require(ASSET.fullmatch(key) and key[:64] == expected, 'Asset key does not identify its original bytes')
        house = json_bytes(archive.read('house.json'))
        counts = semantic_check(house)
        assets = required_assets(house)
        require({'assets/'+key for key in assets} == {n for n in names if n.startswith('assets/')}, 'Referenced/original asset inventory mismatch')
        # The JSON round trip is independent of Codable and excludes NaN/Infinity.
        require(json_bytes(json.dumps(house, allow_nan=False).encode()) == house, 'Metadata JSON round trip differs')
        return dict(passed=True, reader='Python standard library independent archive reader', archiveVersion=1,
                    sourceRevision=house['revision'], metadataSHA256=hashes['house.json'], verifiedOriginals=len(assets),
                    verifiedPayloadBytes=total, members=len(entries), semanticCounts=counts,
                    jsonRoundTripPassed=True, sourceModified=False, extractedFiles=0, physicalPrecisionQualified=False,
                    limitations=['Schema/identity/geometry/asset checks do not qualify capture accuracy or actual cloud-provider recovery.',
                                 'GLB, USDZ and rendered viewer behavior require their separate independent readers.'])
