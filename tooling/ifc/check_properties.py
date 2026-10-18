"""Check native IFC semantic handoff without publishing source records."""
import csv,json,struct,sys,zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from package_check import check_package
from ifc_properties_check import validate

root=Path(sys.argv[1]);out=Path(sys.argv[2]);package=root/'ifc-properties.hxray'
report=check_package(package)
with zipfile.ZipFile(package) as archive:
    house=json.loads(archive.read('house.json'));drawing=house['drawings'][0];reference=drawing['ifcProperties']
    graph=json.loads(archive.read('assets/'+reference['asset']))
    summary=validate(archive.read('assets/'+reference['asset']),reference,drawing['asset'],house['features'])
    assert summary['products']==2 and summary['representedProducts']==summary['convertedProducts']==summary['storeys']==1
    records={r['expressID']:r for r in graph['records']}
    assert graph['storeys'][0]['elevation']==3000
    assert records[43]['fields']['NominalValue']['value']==25
    assert records[42]['fields']['NominalValue']['value']=='=literal source label'
    assert records[41]['fields']['RelatedElements'][0]['value']==22 and records[41]['fields']['RelatingStructure']['value']==40
    assert records[45]['fields']['RelatingPropertyDefinition']['value']==44
    assert b'IFCLENGTHMEASURE(25.)' in archive.read('assets/'+drawing['asset'])
raw=(root/'ifc-properties.glb').read_bytes();assert raw[:4]==b'glTF' and struct.unpack_from('<I',raw,8)[0]==len(raw)
model=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
source=model['extras']['ifcSourceCoordinates'][0];assert source['properties']==reference and source['coordinates']==drawing['ifcCoordinates']
features={f['id']:f for f in house['features']};mesh_nodes=[n for n in model['nodes'] if 'mesh' in n]
assert len(mesh_nodes)==len(features)
for node in mesh_nodes:
    extra=node['extras'];feature=features[extra['id']]
    assert extra['ifcObject']==feature['ifcObject'] and extra['ifcObject']['expressID']==22
    assert extra['sourceDrawing']==drawing['id'] and extra['sourceToHouseRegistration'] is None
with (root/'ifc-properties.csv').open(newline='') as source:rows=[r for r in csv.DictReader(source) if r['record_type']=='feature']
assert len(rows)==len(features)
for row in rows:
    provenance=json.loads(row['provenance_json']);assert provenance['ifcObject']==features[row['id']]['ifcObject']
    assert provenance['ifcSourceProperties']==reference and provenance['ifcSourceCoordinates']==drawing['ifcCoordinates']
aggregate=dict(passed=True,reader='Independent Python archive property graph GLB and CSV readers',verifiedOriginals=report['verifiedOriginals'],products=summary['products'],convertedProducts=summary['convertedProducts'],storeys=summary['storeys'],rawUnitsAndPropertiesPreserved=True,sourceObjectLinksPreserved=True,sourceHashesVerified=True,propertyGraphPublished=False,physicalQualification=False)
(out/'ifc-properties-validation.json').write_text(json.dumps(aggregate,indent=2)+'\n');print(json.dumps(aggregate))
