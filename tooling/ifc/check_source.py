"""Read actual Swift GLB/CSV outputs and independently recover IFC project coordinates."""
import csv,json,struct,sys
from pathlib import Path
root=Path(sys.argv[1]);source=json.loads((root/'ifc-source.json').read_text())
reference=source['drawings'][0]['ifcCoordinates'];assert reference['originMetres']==dict(x=1000000,y=0,z=0) and reference['mapConversions'][0]['values']['Scale']==.001
cases=[]
for name in ['ifc-source','ifc-registered']:
    raw=(root/(name+'.glb')).read_bytes();assert raw[:4]==b'glTF' and struct.unpack_from('<I',raw,8)[0]==len(raw)
    length=struct.unpack_from('<I',raw,12)[0];model=json.loads(raw[20:20+length]);start=20+length+8
    refs=model['extras']['ifcSourceCoordinates'];assert len(refs)==1 and refs[0]['coordinates']==reference
    assert refs[0]['id'].lower()==source['drawings'][0]['id'].lower()
    node=next(n for n in model['nodes'] if n.get('mesh')==0);extra=node['extras'];registration=extra['sourceToHouseRegistration']
    assert extra['sourceSegment'].lower()==source['segments'][0]['id'].lower()
    if name=='ifc-source':assert registration is None and extra['exportCoordinateFrame'].startswith('segment:')
    else:assert registration['values']==[0,-1,0,7,1,0,0,-3,0,0,1,2,0,0,0,1] and extra['exportCoordinateFrame']=='house'
    accessor=model['accessors'][model['meshes'][0]['primitives'][0]['attributes']['POSITION']];view=model['bufferViews'][accessor['bufferView']]
    assert accessor['componentType']==5126 and accessor['type']=='VEC3'
    points=[struct.unpack_from('<3f',raw,start+view.get('byteOffset',0)+accessor.get('byteOffset',0)+12*i) for i in range(accessor['count'])]
    origin=reference['originMetres'];project=[]
    for x,y,z in points:
        point=[x,-z,y]
        if registration:
            m=registration['values'];delta=[point[i]-m[i*4+3] for i in range(3)]
            point=[sum(m[j*4+i]*delta[j] for j in range(3)) for i in range(3)]
        project.append(tuple(point[i]+origin[k] for i,k in enumerate('xyz')))
    assert tuple(min(p[i] for p in project) for i in range(3))==(999999.5,19.,30.)
    assert tuple(max(p[i] for p in project) for i in range(3))==(1000000.5,21.,33.)
    cases.append(dict(case=name,vertices=len(points),projectBoundsRecovered=True,registrationReversed=registration is not None))
with (root/'ifc-source.csv').open(newline='') as f:rows=list(csv.DictReader(f))
feature=next(r for r in rows if r['record_type']=='feature');assert json.loads(feature['provenance_json'])['ifcSourceCoordinates']==reference
assert feature['coordinate_frame'].startswith('segment:') and json.loads(feature['registration_json']).get('transform') is None
report=dict(passed=True,cases=cases,sourceOriginPreserved=True,crsRetainedWithoutApplication=True,csvProvenancePreserved=True,physicalQualification=False)
(Path(sys.argv[2])/'ifc-source-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
