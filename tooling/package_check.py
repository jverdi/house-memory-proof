"""Independent, bounded reader for a complete House Xray evidence archive.

No extraction, rendering, network access or writes to the source package. This
checks the reusable evidence contract; it does not certify captured accuracy.
"""
import hashlib
import datetime
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


def ifc_coordinates_check(value):
    if value is None:return
    require(isinstance(value,dict) and type(value.get('version')) is int and value['version']==1 and value.get('converter')=='web-ifc-0.0.72','Invalid IFC frame version')
    def text(value):return isinstance(value,str) and len(value.encode('utf-8'))<=4096 and '\0' not in value
    require(text(value.get('sourceSchema')) and bool(value['sourceSchema']) and text(value.get('sourceLengthUnit')),'Invalid IFC source units/schema')
    origin=value.get('originMetres')
    require(vector(origin) and all(abs(origin[k])<=1e9 for k in ('x','y','z')),'Invalid IFC source origin')
    maps=value.get('mapConversions')
    require(isinstance(maps,list) and len(maps)<=16,'Invalid IFC coordinate conversion inventory')
    seen=set()
    for item in maps:
        require(isinstance(item,dict),'Invalid IFC conversion')
        key=item.get('expressID');require(type(key) is int and 0<key<=2147483647 and key not in seen,'Invalid IFC conversion identity');seen.add(key)
        values=item.get('values');target=item.get('targetCRS')
        require(isinstance(values,dict) and set(values)<=set('Eastings Northings OrthogonalHeight XAxisAbscissa XAxisOrdinate Scale FactorX FactorY FactorZ'.split()) and all(numeric(v) and abs(v)<=1e12 for v in values.values()),'Invalid IFC conversion values')
        require(isinstance(target,dict) and set(target)<=set('Name Description GeodeticDatum VerticalDatum MapProjection MapZone MapUnit'.split()) and all(text(v) for v in target.values()),'Invalid IFC target CRS')


def service_check(value):
    if value is None:return
    require(isinstance(value,dict),'Invalid service details')
    fields='observedLabel circuitReference panelReference cableCategory endpoint port conduitSize pipeDuctEnvelope installationDate identityEvidence'.split()
    for key in fields:
        text=value.get(key)
        require(text is None or (isinstance(text,str) and len(text.encode('utf-8'))<=4096 and '\0' not in text),'Invalid service text field')
    require(value.get('classification') in [None,'Unknown','Structure / blocking','Electrical power','Low voltage','Plumbing supply','Plumbing drain','Plumbing vent','HVAC supply','HVAC return','HVAC exhaust','Insulation','Fire-stopping','Access point'],'Invalid service class')
    require(value.get('confidence') in [None,'Unknown','Unconfirmed','Owner confirmed'],'Invalid identity confidence')
    require(value.get('confidence')!='Owner confirmed' or bool((value.get('identityEvidence') or '').strip()),'Owner-confirmed identity lacks evidence')
    if value.get('installationDate') is not None:
        text=value['installationDate'];require(re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}',text) is not None,'Invalid installation date')
        try:datetime.date.fromisoformat(text)
        except ValueError:raise InvalidPackage('Invalid installation date') from None
    if value.get('boundaryID') is not None:identity(value['boundaryID'])


def coordinate_declaration_check(value):
    if value is None:return
    require(isinstance(value,dict) and value.get('unit') in ['Metres','Millimetres','Centimetres','Feet','Inches'] and value.get('upright') in ['Z up','Y up'],'Invalid imported coordinate declaration')


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
    require(type(house.get('schema')) is int and house['schema'] in (1,2,3), 'Unsupported house schema')
    identity(house.get('id'))
    require(type(house.get('revision')) is int and house['revision'] >= 0, 'Invalid source revision')
    tables = {}
    limits = dict(rooms=100, features=10000, observations=50000, segments=50000,
                  stages=10000, references=1000, documentaryPhotos=50000, boundaries=1000, drawings=10000)
    for name, limit in limits.items():
        rows = house.get(name, [])
        require(isinstance(rows, list) and len(rows) <= limit, 'Metadata count limit: '+name)
        ids = [identity(item.get('id')) for item in rows]
        require(len(set(ids)) == len(ids), 'Duplicate '+name+' identity')
        tables[name] = dict(zip(ids, rows))
    for drawing in tables['drawings'].values():
        if drawing.get('ifcCoordinates') is not None:
            require(str(drawing.get('asset','')).endswith('.ifc'),'IFC frame requires its original source')
            ifc_coordinates_check(drawing['ifcCoordinates'])
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
        service_check(feature.get('service'))
        declared=feature.get('importedCoordinates')
        if declared is not None:
            coordinate_declaration_check(declared)
            reference(feature,'sourceDrawingID','drawings');reference(feature,'segmentID','segments')
            drawing=tables['drawings'][identity(feature['sourceDrawingID'])]
            require(isinstance(drawing.get('asset'),str) and drawing['asset'].endswith('.ply'),'Imported coordinates require original PLY')
        boundary_id=(feature.get('service') or {}).get('boundaryID')
        if boundary_id is not None:
            boundary=tables['boundaries'].get(identity(boundary_id));require(boundary is not None,'Missing service boundary')
            segment=tables['segments'].get(identity(boundary.get('segmentID')));require(segment is not None,'Missing boundary session')
            require(all(identity(segment[k])==identity(feature[k]) for k in ['roomID','stageID']),'Service boundary scope mismatch')
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
    for feature in tables['features'].values():
        def controls_check(controls,minimum,maximum,require_source_ids=False):
            require(isinstance(controls,list) and minimum<=len(controls)<=maximum,'Invalid photograph control count')
            ids=[identity(c.get('observationID')) for c in controls]
            require(len(set(ids))==len(ids),'Repeated photograph control')
            sources={identity(i) for i in feature.get('sourceIDs',[])} if require_source_ids else set()
            for control,identifier in zip(controls,ids):
                require(identifier in tables['observations'],'Photograph control references an absent original')
                observation=tables['observations'][identifier]
                require(identity(observation['segmentID'])==identity(feature.get('segmentID')),'Photograph control belongs to another session')
                require(all(numeric(control.get(k)) and 0<=control[k]<=1 for k in ['u','v']),'Invalid photograph control coordinate')
                if require_source_ids:require(identifier in sources,'Photograph control omitted from source identities')
        if feature.get('photoControls') is not None:controls_check(feature['photoControls'],3,3)
        if feature.get('pointTracks') is not None:
            tracks=feature['pointTracks']
            require(isinstance(tracks,list) and len(tracks)==len(feature['mesh']['vertices']),'Photograph tracks do not match point geometry')
            for track in tracks:controls_check(track.get('controls'),3,12,True)
    for connection in house.get('connections', []):
        reference(connection, 'fromFeature', 'features'); reference(connection, 'toFeature', 'features')
        require(identity(connection['fromFeature']) != identity(connection['toFeature']), 'Self-connected service route')
        require(all(type(connection.get(k)) is int and connection[k] in (0,1) for k in ('fromEnd','toEnd')), 'Invalid service endpoint')
    annotation_ids=set();annotation_points=0
    for record in house.get('documentaryPhotos', []):
        require(record.get('image') is not None, 'Missing documentary image')
        reference(record,'roomID','rooms',True);reference(record,'stageID','stages',True)
        marks=[] if record.get('annotations') is None else record['annotations']
        require(isinstance(marks,list) and len(marks)<=1000,'Invalid image annotation count')
        for mark in marks:
            require(isinstance(mark,dict),'Invalid image annotation record')
            identifier=identity(mark.get('id'))
            require(identifier not in annotation_ids,'Repeated image annotation identity')
            annotation_ids.add(identifier)
            points=mark.get('points');kind=mark.get('kind')
            require(isinstance(points,list) and len(points)<=512,'Invalid image annotation points')
            require(all(isinstance(p,dict) and all(numeric(p.get(k)) and 0<=p[k]<=1 for k in ['u','v']) for p in points),'Invalid image coordinate')
            require(isinstance(mark.get('label'),str) and len(mark['label'].encode('utf-8'))<=4096 and type(mark.get('reviewed')) is bool,'Invalid image annotation label or review state')
            pairs=[(p['u'],p['v']) for p in points]
            if kind=='point':valid=len(points)==1
            elif kind=='box':valid=len(points)==2 and abs(points[0]['u']-points[1]['u'])>1e-6 and abs(points[0]['v']-points[1]['v'])>1e-6
            elif kind=='polygon':
                valid=len(points)>=3 and len(set(pairs))==len(points) and abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(pairs,pairs[1:]+pairs[:1])))>1e-8
            elif kind=='curve':valid=len(points)>=2 and all(a!=b for a,b in zip(pairs,pairs[1:]))
            else:valid=False
            require(valid,'Invalid image annotation geometry')
            annotation_points+=len(points)
            require(len(annotation_ids)<=50000 and annotation_points<=1_000_000,'Image annotation budget exceeded')
    return dict(rooms=len(tables['rooms']), stages=len(tables['stages']), sessions=len(tables['segments']),
                features=len(tables['features']), observations=len(tables['observations']),
                documentaryPhotos=len(tables['documentaryPhotos']), imageAnnotations=len(annotation_ids), vertices=vertices, triangles=triangles,
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
