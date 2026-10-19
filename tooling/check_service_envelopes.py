"""Inspect native envelope dimensions, export coordinates and provenance privately."""
import csv,datetime,json,struct,sys,zipfile
from pathlib import Path
from package_check import check_package
from interchange_check import semantic_csv

root,out=map(Path,sys.argv[1:])
report=check_package(root/'service-envelopes.hxray')
with zipfile.ZipFile(root/'service-envelopes.hxray') as archive:house=json.loads(archive.read('house.json'))
features={f['id']:f for f in house['features']};envelopes=[f for f in features.values() if f.get('envelope')]
assert len(envelopes)==5 and {f['envelope']['section'] for f in envelopes}=={'Round','Rectangular'}
assert {f['envelope']['version'] for f in envelopes}=={1,2,3}
assert all(f['envelope']['sourceFeatureID'] in features and len(f['route'])==(f['envelope']['sourceEndInterval']-f['envelope']['sourceInterval']+2 if f['envelope']['version']==2 else 2) for f in envelopes)
data=(root/'service-envelopes.glb').read_bytes();length=struct.unpack_from('<I',data,12)[0]
model=json.loads(data[20:20+length]);binary=data[28+length:];maximum=0;seen=set()
for node in model['nodes']:
    if node.get('extras',{}).get('serviceEnvelope') is None:continue
    feature=features[node['extras']['id']]
    assert feature['id'] not in seen;seen.add(feature['id'])
    assert not any(key in node for key in ['matrix','translation','rotation','scale'])
    assert node['extras']['serviceEnvelope']==feature['envelope']
    assert node['extras']['sourceGeometry']==feature['annotationSources']
    primitive=model['meshes'][node['mesh']]['primitives'][0];assert primitive['mode']==4
    accessor=model['accessors'][primitive['attributes']['POSITION']];view=model['bufferViews'][accessor['bufferView']]
    assert accessor['componentType']==5126 and accessor['count']==len(feature['mesh']['vertices'])
    offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
    for i,point in enumerate(feature['mesh']['vertices']):
        actual=struct.unpack_from('<fff',binary,offset+12*i);expected=[point['x'],point['z'],-point['y']]
        maximum=max(maximum,max(abs(a-b) for a,b in zip(actual,expected)))
assert seen=={f['id'] for f in envelopes} and maximum<1e-6
semantic_csv(root/'service-envelopes.csv')
with (root/'service-envelopes.csv').open(newline='') as source:
    rows=[row for row in csv.DictReader(source) if row['record_type']=='feature']
assert len(rows)==len(features)
for row in rows:
    exported=json.loads(row['provenance_json']).get('envelope');original=features[row['id']].get('envelope')
    if original is None:assert exported is None;continue
    exported=dict(exported);original=dict(original)
    # Semantic CSV uses ISO 8601 whole seconds; the archive retains the full
    # Foundation reference-date value. Compare the instant at CSV resolution.
    recorded=datetime.datetime.strptime(exported.pop('recorded'),'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()
    assert abs(recorded-(original.pop('recorded')+978307200))<1
    assert exported==original
aggregate=dict(passed=True,reader='Independent Python service-envelope archive GLB and CSV readers',
    sections=2,connectedCircularEnvelopes=sum(f['envelope']['version']==2 for f in envelopes),linearTapers=sum(f['envelope']['version']==3 for f in envelopes),sourceCenterlinesPreserved=True,declaredDimensionsVerified=True,sourceDependenciesPreserved=True,
    maximumExportCoordinateErrorMetres=maximum,csvDateResolutionSeconds=1,measurementInstantPreserved=True,toleranceIsSizeOnly=True,sourceRecordsPublished=False,physicalQualification=False)
out.write_text(json.dumps(aggregate,indent=2)+'\n');print(json.dumps(aggregate))
