"""Independent readers for self-contained native export profiles.

Reader APIs: https://trimesh.org/trimesh.exchange.load.html and
https://openusd.org/release/api/class_sdf_layer.html.
Reports contain counts, hashes and contract results, never geometry or identities.
"""
import csv
from collections import Counter, defaultdict
import hashlib
import io
import math
from pathlib import Path, PurePosixPath
import stat
import struct
import zipfile
from package_check import require, identity, json_bytes, rigid, service_check, coordinate_declaration_check, ifc_coordinates_check
import ifc_properties_check

MAX_MODEL=512*1024*1024
COLUMNS='schema_version house_id house_revision record_type id parent_id index name room_id room_name level stage_id stage_name stage_date evidence_kind trade coordinate_frame segment_id registration_json x_m y_m z_m x2_m y2_m z2_m length_m endpoint_label from_feature_id from_end to_feature_id to_end confirmed reviewed hidden date source source_ids_json provenance_json notes'.split()
NUMERIC=set('schema_version house_revision index level x_m y_m z_m x2_m y2_m z2_m length_m from_end to_end'.split())


def bounded(path,limit=MAX_MODEL):
    require(path.is_file() and 0<path.stat().st_size<=limit,'Model is missing, empty or exceeds the reader budget')
    return path.read_bytes()


def report(raw,format,reader,**counts):
    return dict(passed=True,format=format,reader=reader,sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw),
        sourceModified=False,externalResourcesLoaded=False,physicalPrecisionQualified=False,**counts)


def mesh(path):
    raw=bounded(path)
    extension=path.suffix.lower()[1:]
    if extension=='obj':
        # Native OBJ is geometry-only. No filesystem or network resolver is used.
        for line in raw.decode('utf-8').splitlines():
            command=line.strip().split(maxsplit=1)
            require(not command or command[0].lower() not in ['mtllib','call','csh'],'External OBJ dependencies are outside the self-contained profile')
    try:
        import numpy as np
        import trimesh
    except ImportError:
        raise ValueError('Independent trimesh reader unavailable; use the prepared validation environment') from None
    require(trimesh.__version__=='5.1.1','Expected pinned trimesh 5.1.1 reader')
    scene=trimesh.load_scene(io.BytesIO(raw),file_type=extension,process=False,maintain_order=True,
        split_groups=True,group_material=False,resolver={},allow_remote=False)
    require(0<len(scene.geometry)<=10000,'No geometry or too many groups')
    vertices=triangles=clouds=0
    for item in scene.geometry.values():
        points=np.asarray(item.vertices)
        require(points.ndim==2 and points.shape[1]==3 and len(points)>0 and np.isfinite(points).all(),'Nonfinite or empty geometry')
        vertices+=len(points)
        faces=np.asarray(getattr(item,'faces',[]))
        if faces.size:
            require(faces.ndim==2 and faces.shape[1]==3 and np.issubdtype(faces.dtype,np.integer) and (faces>=0).all() and (faces<len(points)).all(),'Invalid triangle indices')
            triangles+=len(faces)
        else:clouds+=1
    return report(raw,extension.upper(),'trimesh '+trimesh.__version__,groups=len(scene.geometry),vertices=vertices,triangles=triangles,pointClouds=clouds,
        geometryOnly=True,sourceGeometryEquivalenceChecked=False)


def usdz(path):
    raw=bounded(path)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        entries=archive.infolist();names=[e.filename for e in entries]
        require(0<len(entries)<=10001 and len(names)==len(set(names)),'Invalid USDZ member inventory')
        require(names[0].endswith('.usda'),'This native USDZ profile requires an ASCII root layer')
        require(entries[0].file_size<=100_000_000,'USD layer exceeds the parse budget')
        require(sum(e.file_size for e in entries)<=MAX_MODEL,'USDZ contents exceed the read budget')
        for entry in entries:
            name=entry.filename
            require(not entry.is_dir() and not stat.S_ISLNK(entry.external_attr>>16) and not entry.flag_bits&1
                and not PurePosixPath(name).is_absolute() and '\\' not in name and '\x00' not in name
                and all(part not in ['','.','..'] for part in name.split('/')),'Unsafe USDZ member path')
            require(entry.compress_type==zipfile.ZIP_STORED,'USDZ members must be stored without compression')
            header=raw[entry.header_offset:entry.header_offset+30]
            require(len(header)==30 and header[:4]==b'PK\x03\x04','Invalid USDZ local header')
            n,e=struct.unpack_from('<HH',header,26)
            require((entry.header_offset+30+n+e)%64==0,'USDZ payload is not 64-byte aligned')
            if entry is not entries[0]:require(name.startswith('textures/') and Path(name).suffix.lower() in ['.jpg','.jpeg','.png'],'Only packaged textures may accompany the root layer')
        require(archive.testzip() is None,'USDZ member checksum mismatch')
        source=archive.read(names[0]).decode('utf-8')
    try:from pxr import Sdf,Usd,UsdGeom
    except ImportError:raise ValueError('Independent OpenUSD reader unavailable; use the prepared validation environment') from None
    require(Usd.GetVersion()==(0,25,11),'Expected pinned OpenUSD 25.11 reader')
    # Parse before composing: reject references/payloads/sublayers, even when
    # hidden in a variant. ImportFromString never resolves their target layers.
    layer=Sdf.Layer.CreateAnonymous('.usda')
    require(layer.ImportFromString(source),'OpenUSD could not parse the root layer')
    require(not layer.GetExternalReferences(),'External USD layers are outside the self-contained native profile')
    stage=Usd.Stage.Open(layer)
    require(stage and UsdGeom.GetStageUpAxis(stage)=='Z' and UsdGeom.GetStageMetersPerUnit(stage)==1,'Native USD units or axis contract is missing')
    meshes=clouds=vertices=faces=assets=0
    for prim in stage.Traverse():
        for attribute in prim.GetAttributes():
            value=attribute.Get()
            if isinstance(value,Sdf.AssetPath):
                require(value.path in names[1:],'Missing or external USD texture');assets+=1
        if prim.IsA(UsdGeom.Mesh) or prim.IsA(UsdGeom.Points):
            geometry=UsdGeom.PointBased(prim);points=geometry.GetPointsAttr().Get()
            require(points is not None and len(points)>0 and all(math.isfinite(v) for point in points for v in point),'Invalid USD positions')
            vertices+=len(points)
            if prim.IsA(UsdGeom.Mesh):
                model=UsdGeom.Mesh(prim);counts=model.GetFaceVertexCountsAttr().Get();indices=model.GetFaceVertexIndicesAttr().Get()
                require(counts is not None and indices is not None and all(c>=3 for c in counts) and sum(counts)==len(indices) and all(0<=i<len(points) for i in indices),'Invalid USD face topology')
                meshes+=1;faces+=len(counts)
            else:
                widths=UsdGeom.Points(prim).GetWidthsAttr().Get()
                require(widths is not None and len(widths) in [1,len(points)] and all(math.isfinite(v) and v>0 for v in widths),'Invalid USD point widths');clouds+=1
    require(meshes+clouds>0,'No USD mesh or point geometry')
    return report(raw,'USDZ native profile','OpenUSD 25.11',meshes=meshes,pointClouds=clouds,vertices=vertices,faces=faces,textureReferences=assets,
        units='metres',upAxis='Z',sourceGeometryEquivalenceChecked=False)


def semantic_csv(path):
    raw=bounded(path,128_000_000);csv.field_size_limit(2_000_000)
    reader=csv.DictReader(io.StringIO(raw.decode('utf-8'),newline=''),strict=True)
    require(reader.fieldnames==COLUMNS,'Unsupported semantic CSV schema')
    rows=list(reader);require(len(rows)<=1_000_000,'CSV record budget exceeded')
    ids=set();features={};children=defaultdict(lambda:defaultdict(list));connections=[];scopes=set();registrations={}
    counts=Counter()
    def text(value):return value[1:] if value.startswith("'") else value
    def xyz(row,suffix='_m'):return tuple(float(row[k+suffix]) for k in 'xyz')
    for row in rows:
        require(None not in row and None not in row.values(),'Malformed CSV row width')
        require(row['schema_version']=='1' and row['house_revision'].isdigit(),'Invalid CSV source version')
        scopes.add((identity(row['house_id']),row['house_revision']));require(len(scopes)==1,'Mixed CSV sources')
        require(row['id'] and row['id'] not in ids,'Duplicate or missing CSV record identity');ids.add(row['id'])
        for key,value in row.items():
            if value and key in NUMERIC:require(math.isfinite(float(value)),'Nonfinite CSV number')
            elif value:
                stripped=value.lstrip()
                require(value.startswith("'") or not (bool(stripped) and stripped[0] in '=+-@' or value[:1] in '\t\r\n'),'Unescaped spreadsheet formula text')
        kind=row['record_type'];require(kind in ['feature','route_point','endpoint','measurement','connection'],'Unknown semantic record kind');counts[kind]+=1
        if kind!='connection':
            identity(row['room_id'])
            require(row['coordinate_frame']==('segment:'+row['segment_id'] if row['segment_id'] else 'house'),'CSV coordinate frame mismatch')
            if row['segment_id']:identity(row['segment_id'])
            if row['registration_json']:
                frame=json_bytes(text(row['registration_json']).encode())
                require(identity(frame['segmentID'])==identity(row['segment_id']) and type(frame['approved']) is bool,'Invalid CSV registration scope')
                if frame.get('transform') is not None:require(rigid(frame['transform'].get('values')),'Nonrigid CSV registration')
                key=identity(row['segment_id'])
                require(key not in registrations or registrations[key]==frame,'Conflicting CSV registrations');registrations[key]=frame
        if kind in ['feature','measurement','connection']:
            provenance=json_bytes(text(row['provenance_json']).encode())
            require(identity(provenance.get('id'))==identity(row['id']),'CSV provenance identity mismatch')
            for key in ['name','notes']:
                if key in provenance:require(text(row[key])==provenance[key],'CSV provenance text mismatch')
            if kind!='connection':
                for column,key in [('room_id','roomID'),('stage_id','stageID'),('segment_id','segmentID')]:
                    if key in provenance:require(row[column]==provenance[key],'CSV provenance scope mismatch')
                require(bool(row['segment_id'])==(provenance.get('segmentID') is not None),'CSV provenance coordinate frame differs')
        if kind=='feature':
            service_check(provenance.get('service'))
            coordinate_declaration_check(provenance.get('importedCoordinates'))
            ifc_coordinates_check(provenance.get('ifcSourceCoordinates'))
            if provenance.get('ifcSourceCoordinates') is not None:
                identity(provenance.get('sourceDrawingID'));identity(provenance.get('segmentID'))
            if provenance.get('ifcObject') is not None:
                properties=provenance.get('ifcSourceProperties')
                require(isinstance(properties,dict) and provenance.get('ifcSourceCoordinates') is not None and provenance.get('kind')=='planned','IFC object source provenance missing')
                try:
                    ifc_properties_check.object_check(provenance['ifcObject'])
                    ifc_properties_check.reference_check(properties,str(properties.get('sourceSHA256'))+'.ifc')
                except (ValueError,TypeError,KeyError,AttributeError) as error:require(False,str(error))
            if provenance.get('importedCoordinates') is not None:
                identity(provenance.get('sourceDrawingID'));identity(provenance.get('segmentID'))
            features[row['id']]=row
            require(json_bytes(text(row['source_ids_json']).encode())==provenance['sourceIDs'],'CSV source identities differ')
            for key in ['trade','hidden','reviewed']:
                expected=str(provenance[key]).lower() if isinstance(provenance[key],bool) else provenance[key]
                require(row[key]==expected,'CSV feature semantic mismatch')
            require(row['evidence_kind']==provenance['kind'],'CSV evidence kind differs')
            if 'endpoint' in provenance:require(text(row['endpoint_label'])==provenance['endpoint'],'CSV endpoint label differs')
        elif kind in ['route_point','endpoint']:
            require(row['index'].isdigit(),'Invalid route index')
            xyz(row);children[row['parent_id']][kind].append(row)
        elif kind=='measurement':
            a,b=xyz(row),xyz(row,'2_m');length=float(row['length_m'])
            require(length>=0 and math.isclose(math.dist(a,b),length,rel_tol=1e-8,abs_tol=1e-8),'CSV measurement geometry differs')
            require(a==tuple(provenance['a'][k] for k in 'xyz') and b==tuple(provenance['b'][k] for k in 'xyz'),'CSV measurement provenance differs')
        else:
            for column,key in [('from_feature_id','fromFeature'),('to_feature_id','toFeature'),('from_end','fromEnd'),('to_end','toEnd')]:
                require(row[column]==str(provenance[key]),'CSV connection provenance differs')
            require(row['confirmed']==str(provenance['confirmed']).lower(),'CSV connection approval differs');connections.append(row)
    for parent,groups in children.items():
        require(parent in features,'CSV route has no source feature');feature=features[parent]
        route=sorted(groups['route_point'],key=lambda r:int(r['index']));ends=sorted(groups['endpoint'],key=lambda r:int(r['index']))
        require([int(r['index']) for r in route]==list(range(len(route))) and route,'Noncontiguous CSV route')
        require([r['index'] for r in ends]==['0','1'] and xyz(ends[0])==xyz(route[0]) and xyz(ends[1])==xyz(route[-1]),'CSV endpoints differ from route')
        for row in route+ends:
            require(all(row[k]==feature[k] for k in ['room_id','stage_id','segment_id','coordinate_frame']),'CSV child scope differs')
    for row in connections:
        require(row['from_feature_id']!=row['to_feature_id'],'Self-connected CSV service')
        for side in ['from','to']:
            require(row[side+'_feature_id'] in children and row[side+'_end'] in ['0','1'],'Missing CSV connection endpoint')
    out=io.StringIO(newline='');writer=csv.DictWriter(out,fieldnames=COLUMNS);writer.writeheader();writer.writerows(rows)
    require(list(csv.DictReader(io.StringIO(out.getvalue(),newline=''),strict=True))==rows,'Independent CSV round trip differs')
    return report(raw,'House Xray semantic CSV v1','Python standard-library csv',records=len(rows),recordTypes=dict(counts),
        relationshipsChecked=True,provenanceChecked=True,csvRoundTripPassed=True)
