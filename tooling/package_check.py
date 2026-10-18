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
import ifc_properties_check

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
    for drawing in house.get('drawings',[]):
        add((drawing.get('ifcProperties') or {}).get('asset'))
        for mark in drawing.get('marks') or []:add(mark.get('sourceAsset'))
    return assets


def drawing_mark_check(mark):
    require(isinstance(mark,dict),'Invalid drawing mark')
    require(type(mark.get('page')) is int and 0<=mark['page']<10000,'Invalid drawing page')
    require(isinstance(mark.get('sourceAsset'),str) and len(mark['sourceAsset'])<=100 and ASSET.fullmatch(mark['sourceAsset']),'Invalid drawing original')
    require(type(mark.get('reviewed')) is bool,'Invalid drawing review state')
    kind=mark.get('kind');require(kind in ['Room name','Possible boundary'],'Invalid drawing mark type')
    def text(value):return isinstance(value,str) and len(value.encode('utf-8'))<=4096 and '\0' not in value
    require(text(mark.get('label')),'Invalid drawing label')
    def shape(points):
        require(isinstance(points,list) and len(points)<=128 and all(isinstance(p,dict) and all(numeric(p.get(k)) and 0<=p[k]<=1 for k in ['u','v']) for p in points),'Invalid drawing coordinates')
        xy=[(p['u'],p['v']) for p in points]
        if kind=='Room name':
            require(len(xy)==2 and all(abs(xy[0][i]-xy[1][i])>1e-6 for i in [0,1]),'Invalid room label box');return
        require(len(xy)>=3 and len(set(xy))==len(xy) and abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(xy,xy[1:]+xy[:1])))>1e-8,'Invalid boundary polygon')
        def turn(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        def on(a,b,p):return abs(turn(a,b,p))<1e-12 and all(min(a[i],b[i])-1e-12<=p[i]<=max(a[i],b[i])+1e-12 for i in [0,1])
        for i,a in enumerate(xy):
            b=xy[(i+1)%len(xy)]
            for j in range(i+2,len(xy)):
                if i==0 and j==len(xy)-1:continue
                c,d=xy[j],xy[(j+1)%len(xy)]
                require(not (turn(a,b,c)*turn(a,b,d)<0 and turn(c,d,a)*turn(c,d,b)<0) and not any([on(a,b,c),on(a,b,d),on(c,d,a),on(c,d,b)]),'Crossed boundary polygon')
    shape(mark.get('points'));method=mark.get('method')
    provenance=['originalPoints','originalLabel','profileHash','runtime','rawScore']
    if method=='manual':require(all(mark.get(k) is None for k in provenance),'Manual drawing mark has detector provenance');return
    require(method in ['visionText','visionRectangle'] and ((method=='visionText')==(kind=='Room name')),'Invalid drawing detector')
    shape(mark.get('originalPoints'))
    require(text(mark.get('originalLabel')) and text(mark.get('runtime')) and bool(mark['runtime']),'Missing drawing suggestion provenance')
    require(mark.get('profileHash')=='9f858468f850556e2d7799d6389e839e53bf6c16ef58e5af5d3c92e85893dc36','Unknown drawing suggestion profile')
    require(numeric(mark.get('rawScore')) and 0<=mark['rawScore']<=1,'Invalid drawing detector score')


def envelope_check(value,feature=None,*,iso_dates=False):
    if value is None:return
    require(isinstance(value,dict) and type(value.get('version')) is int and value['version'] in (1,2),'Invalid envelope version')
    source=identity(value.get('sourceFeatureID'))
    require(type(value.get('sourceRevision')) is int and value['sourceRevision']>0 and type(value.get('sourceInterval')) is int and 0<=value['sourceInterval']<127,'Invalid envelope dependency')
    width=value.get('widthMetres');height=value.get('heightMetres');axis=value.get('widthAxis');section=value.get('section')
    require(numeric(width) and .001<=width<=4,'Invalid measured outer width')
    if section=='Round':require(height is None and axis is None,'Round envelope has rectangular metadata')
    else:
        require(section=='Rectangular' and numeric(height) and .001<=height<=4 and vector(axis),'Invalid measured cross section')
        require(abs(math.sqrt(sum(axis[k]**2 for k in ['x','y','z']))-1)<1e-6,'Invalid width axis')
    end=value.get('sourceEndInterval')
    if value['version']==1:require(end is None,'Legacy envelope has a connected interval range')
    else:require(section=='Round' and type(end) is int and value['sourceInterval']<end<127,'Invalid connected envelope range')
    tolerance=value.get('dimensionToleranceMetres')
    require(tolerance is None or (numeric(tolerance) and 0<tolerance<min(width,height or width)/2),'Invalid size tolerance')
    evidence=value.get('evidence');require(isinstance(evidence,str) and bool(evidence.strip()) and len(evidence.encode('utf-8'))<=4096 and '\0' not in evidence,'Missing envelope measurement evidence')
    recorded=value.get('recorded')
    if iso_dates:
        require(isinstance(recorded,str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z',recorded),'Invalid CSV measurement date')
        try:datetime.datetime.strptime(recorded,'%Y-%m-%dT%H:%M:%SZ')
        except ValueError:raise InvalidPackage('Invalid CSV measurement date') from None
    else:require(numeric(recorded),'Invalid measurement date')
    if feature is None:return
    require(feature.get('kind') in ['observed','synthetic'] and source!=identity(feature['id']),'Invalid envelope evidence kind or self-reference')
    dependencies=feature.get('annotationSources')
    require(isinstance(dependencies,list) and len(dependencies)==1 and identity(dependencies[0].get('featureID'))==source and type(dependencies[0].get('revision')) is int and dependencies[0]['revision']==value['sourceRevision'],'Envelope dependency differs')
    route=feature.get('route');expected_points=2 if value['version']==1 else end-value['sourceInterval']+2
    require(isinstance(route,list) and len(route)==expected_points and all(vector(p) for p in route),'Invalid envelope centerline')
    if value['version']==2:
        connected_envelope_geometry(feature,width)
        return
    # Independently inspect the cross section, cap placement and mesh topology.
    xyz=lambda p:[p[k] for k in ['x','y','z']]
    dot=lambda a,b:sum(x*y for x,y in zip(a,b))
    sub=lambda a,b:[x-y for x,y in zip(a,b)]
    a,b=map(xyz,route);delta=sub(b,a);length=math.sqrt(dot(delta,delta));require(length>1e-5,'Zero envelope interval')
    t=[v/length for v in delta];reference=xyz(axis) if axis else ([0,0,1] if abs(t[2])<.9 else [0,1,0])
    w=sub(reference,[v*dot(reference,t) for v in t]);magnitude=math.sqrt(dot(w,w));require(magnitude>=.1,'Parallel envelope width')
    w=[v/magnitude for v in w];h=[t[1]*w[2]-t[2]*w[1],t[2]*w[0]-t[0]*w[2],t[0]*w[1]-t[1]*w[0]]
    n=64 if section=='Round' else 4;vertices=feature['mesh']['vertices'];indices=feature['mesh']['triangles']
    require(len(vertices)==2*n+2 and len(indices)==12*n,'Envelope mesh dimensions differ')
    expected=[]
    for center in [a,b]:
        for i in range(n):
            if section=='Round':x,y=math.cos(2*math.pi*i/n)*width/2,math.sin(2*math.pi*i/n)*width/2
            else:
                signs=[(-1,-1),(1,-1),(1,1),(-1,1)];x,y=signs[i][0]*width/2,signs[i][1]*height/2
            expected.append([center[k]+w[k]*x+h[k]*y for k in range(3)])
    expected+=[a,b]
    require(all(max(abs(x-y) for x,y in zip(xyz(actual),target))<1e-8 for actual,target in zip(vertices,expected)),'Envelope mesh disagrees with recorded dimensions')
    topology=[]
    for i in range(n):j=(i+1)%n;topology += [i,j,i+n,j,j+n,i+n,2*n,j,i,2*n+1,i+n,j+n]
    require(indices==topology,'Envelope cap or side topology differs')


def connected_envelope_geometry(feature,width):
    """Check circles on both incident cylinders, rather than replaying the writer."""
    xyz=lambda p:[p[k] for k in ['x','y','z']]
    dot=lambda a,b:sum(x*y for x,y in zip(a,b))
    sub=lambda a,b:[x-y for x,y in zip(a,b)]
    cross=lambda a,b:[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
    unit=lambda v:[x/math.sqrt(dot(v,v)) for x in v]
    route=list(map(xyz,feature['route']));deltas=[sub(b,a) for a,b in zip(route,route[1:])]
    require(all(dot(v,v)>1e-10 for v in deltas),'Zero connected envelope interval')
    tangents=list(map(unit,deltas));vertices=list(map(xyz,feature['mesh']['vertices']));n=64;r=width/2
    require(len(vertices)==len(route)*n+2,'Connected ring count differs')
    require(vertices[-2:]==[route[0],route[-1]],'Connected end cap differs')
    extensions=[0]
    for a,b in zip(tangents,tangents[1:]):
        cosine=dot(a,b);require(cosine>=-1e-12,'Connected turn exceeds 90 degrees')
        extensions.append(r*math.sqrt(max(0,(1-cosine)/(1+cosine))))
    extensions.append(0)
    require(all(math.sqrt(dot(v,v))>extensions[i]+extensions[i+1]+1e-5 for i,v in enumerate(deltas)),'Connected bend is too tight')
    for i,center in enumerate(route):
        incident=tangents[max(0,i-1):min(len(tangents),i+1)]
        normal=unit([sum(t[k] for t in incident) for k in range(3)])
        offsets=[sub(v,center) for v in vertices[i*n:(i+1)*n]]
        require(all(abs(dot(p,normal))<1e-8 for p in offsets),'Ring left its bisector plane')
        for tangent in incident:
            ring=[[p[k]-tangent[k]*dot(p,tangent) for k in range(3)] for p in offsets]
            require(all(abs(math.sqrt(dot(p,p))-r)<1e-8 for p in ring),'Ring disagrees with measured outer radius')
            for a,b in zip(ring,ring[1:]+ring[:1]):
                require(abs(dot(a,b)/r**2-math.cos(2*math.pi/n))<1e-7 and dot(cross(a,b),tangent)>0,'Ring ordering or sampling differs')
    topology=[]
    for i in range(len(route)-1):
        for j in range(n):
            a=i*n+j;b=i*n+(j+1)%n;topology += [a,b,a+n,b,b+n,a+n]
    first=len(route)*n;last=(len(route)-1)*n
    for j in range(n):k=(j+1)%n;topology += [first,k,j,first+1,last+j,last+k]
    require(feature['mesh']['triangles']==topology,'Connected side or cap topology differs')


def semantic_check(house):
    require(type(house.get('schema')) is int and house['schema'] in (1,2,3,4,5), 'Unsupported house schema')
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
    mark_ids=set();mark_points=0
    for drawing in tables['drawings'].values():
        marks=drawing.get('marks') or []
        require(isinstance(marks,list) and len(marks)<=1000,'Invalid drawing mark count')
        for mark in marks:
            drawing_mark_check(mark)
            key=identity(mark.get('id'));require(key not in mark_ids,'Repeated drawing mark identity');mark_ids.add(key)
            mark_points+=len(mark['points'])+len(mark.get('originalPoints') or [])
        require(len(mark_ids)<=50000 and mark_points<=1_000_000,'Drawing mark inventory limit')
        if drawing.get('ifcCoordinates') is not None:
            require(str(drawing.get('asset','')).endswith('.ifc'),'IFC frame requires its original source')
            ifc_coordinates_check(drawing['ifcCoordinates'])
        if drawing.get('ifcProperties') is not None:
            require(drawing.get('ifcCoordinates') is not None,'IFC properties require source coordinates')
            try:ifc_properties_check.reference_check(drawing['ifcProperties'],drawing.get('asset'))
            except (ValueError,TypeError,KeyError,AttributeError) as error:raise InvalidPackage(str(error)) from error
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
        if feature.get('ifcObject') is not None:
            reference(feature,'sourceDrawingID','drawings');reference(feature,'segmentID','segments')
            require(feature.get('kind')=='planned' and tables['drawings'][identity(feature['sourceDrawingID'])].get('ifcProperties') is not None,'IFC object requires planned source properties')
            try:ifc_properties_check.object_check(feature['ifcObject'])
            except (ValueError,TypeError,KeyError,AttributeError) as error:raise InvalidPackage(str(error)) from error
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
        envelope_check(feature.get('envelope'),feature)
        envelope=feature.get('envelope')
        if envelope:
            original=tables['features'].get(identity(envelope['sourceFeatureID']))
            if original and original.get('revision')==envelope['sourceRevision']:
                end=envelope.get('sourceEndInterval',envelope['sourceInterval'])
                route=original.get('route',[])
                require(original.get('envelope') is None and end<len(route)-1 and feature['route']==route[envelope['sourceInterval']:end+2], 'Envelope source interval differs')
                require(all(feature.get(key)==original.get(key) for key in ['roomID','stageID','segmentID']), 'Envelope source frame differs')
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
        house = json_bytes(archive.read('house.json'))
        require(isinstance(hashes, dict), 'Invalid manifest digest inventory')
        payloads=set(names)-{'manifest.json'}
        unhashed=payloads-set(hashes)
        legacy_index=house.get('schema')==1 and unhashed=={'index.html'}
        require(set(hashes).issubset(payloads) and (not unhashed or legacy_index), 'Manifest/member inventory mismatch')
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
        if legacy_index:
            # The genuine schema-1 writer omitted only index.html from its SHA
            # manifest. ZIP CRC is still read and checked; original assets and
            # the offline viewer never receive this compatibility exception.
            with archive.open('index.html') as source:
                while chunk := source.read(1024*1024):
                    total+=len(chunk)
                    require(total<=MAX_ARCHIVE,'Expanded byte budget exceeded')
        counts = semantic_check(house)
        assets = required_assets(house)
        require({'assets/'+key for key in assets} == {n for n in names if n.startswith('assets/')}, 'Referenced/original asset inventory mismatch')
        property_bytes=0
        for drawing in house.get('drawings',[]):
            reference=drawing.get('ifcProperties')
            if reference is None:continue
            path='assets/'+reference['asset'];size=archive.getinfo(path).file_size;property_bytes+=size
            require(size<=4_000_000 and property_bytes<=64_000_000,'IFC property read budget')
            data=archive.read(path)
            require(json_bytes(data).get('sourceSchema')==drawing['ifcCoordinates']['sourceSchema'],'IFC source schema differs')
            try:ifc_properties_check.validate(data,reference,drawing['asset'],[f for f in house['features'] if f.get('sourceDrawingID')==drawing['id'] and f.get('ifcObject') is not None])
            except (ValueError,TypeError,KeyError,AttributeError) as error:raise InvalidPackage(str(error)) from error
        # The JSON round trip is independent of Codable and excludes NaN/Infinity.
        require(json_bytes(json.dumps(house, allow_nan=False).encode()) == house, 'Metadata JSON round trip differs')
        return dict(passed=True, reader='Python standard library independent archive reader', archiveVersion=1,
                    sourceRevision=house['revision'], metadataSHA256=hashes['house.json'], verifiedOriginals=len(assets),
                    verifiedPayloadBytes=total, members=len(entries), semanticCounts=counts,legacyIndexCRCOnly=legacy_index,
                    jsonRoundTripPassed=True, sourceModified=False, extractedFiles=0, physicalPrecisionQualified=False,
                    limitations=['Schema/identity/geometry/asset checks do not qualify capture accuracy or actual cloud-provider recovery.',
                                 'GLB, USDZ and rendered viewer behavior require their separate independent readers.'])
