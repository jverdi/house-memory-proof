"""Read the actual native drawing-mark archive; emit aggregate evidence only."""
import json
from pathlib import Path
import sys
import zipfile
from package_check import check_package

source,out=map(Path,sys.argv[1:])
report=check_package(source)
with zipfile.ZipFile(source) as archive:
    house=json.loads(archive.read('house.json'))
    drawing=house['drawings'][0];marks=drawing['marks']
    assert house['schema']==5 and not house['features'] and len(house['rooms'])==1
    assert all(not m['reviewed'] and m['points']==m['originalPoints'] and m['label']==m['originalLabel'] for m in marks)
    names=[m for m in marks if m['kind']=='Room name']
    boundaries=[m for m in marks if m['kind']=='Possible boundary']
    assert any('ROOM A' in m['label'].upper() for m in names)
    assert any('ROOM B' in m['label'].upper() for m in names) and len(boundaries)>=2
    assert archive.read('assets/'+drawing['asset']).startswith(b'%PDF')
    assert all(m['sourceAsset']==drawing['asset'] and m['page']==0 for m in marks)
aggregate=dict(passed=True,reader='Independent Python drawing archive reader',verifiedOriginals=report['verifiedOriginals'],
    textSuggestions=len(names),boundarySuggestions=len(boundaries),reviewRequired=True,sourcePageLinksPreserved=True,
    detectorProvenancePreserved=True,measuredGeometryCreated=False,sourceRecordsPublished=False,physicalQualification=False)
out.write_text(json.dumps(aggregate,indent=2)+'\n')
print(json.dumps(aggregate))
