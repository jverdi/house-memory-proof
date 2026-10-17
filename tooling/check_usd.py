from pxr import Usd,UsdGeom
import json,zipfile,struct
for name in ['test','textured','points']:
 p='build/evidence/'+name+'.usdz';stage=Usd.Stage.Open(p)
 assert stage and UsdGeom.GetStageUpAxis(stage)=='Z' and UsdGeom.GetStageMetersPerUnit(stage)==1
 meshes=[UsdGeom.Mesh(x) for x in stage.Traverse() if x.IsA(UsdGeom.Mesh)]
 points=[UsdGeom.Points(x) for x in stage.Traverse() if x.IsA(UsdGeom.Points)]
 assert meshes or points
 for cloud in points:
  assert len(cloud.GetPointsAttr().Get())>0 and len(cloud.GetWidthsAttr().Get())>0
 for mesh in meshes:
  points=mesh.GetPointsAttr().Get();indices=mesh.GetFaceVertexIndicesAttr().Get();counts=mesh.GetFaceVertexCountsAttr().Get()
  assert sum(counts)==len(indices) and all(0<=i<len(points) for i in indices)
 with zipfile.ZipFile(p) as z,open(p,'rb') as f:
  for i in z.infolist():
   assert i.compress_type==zipfile.ZIP_STORED
   f.seek(i.header_offset);header=f.read(30);n,e=struct.unpack_from('<HH',header,26)
   assert (i.header_offset+30+n+e)%64==0
  if name=='textured':
   assert any(x.startswith('textures/') for x in z.namelist())
   assert any(mesh.GetPrim().GetAttribute('primvars:st').HasValue() for mesh in meshes)
 json.dump({'reader':'OpenUSD 25.11','passed':True,'meshes':len(meshes),'units':'metres','upAxis':'Z'},open('build/evidence/'+name+'-usd-validation.json','w'),indent=2)

# An independent ZIP reader checks our streaming ZIP64 format and manifest.
import hashlib
with zipfile.ZipFile('build/evidence/test.hxray') as archive:
 assert archive.testzip() is None
 manifest=json.loads(archive.read('manifest.json'))
 for name,digest in manifest['sha256'].items():
  assert hashlib.sha256(archive.read(name)).hexdigest()==digest
json.dump({'reader':'Python zipfile','passed':True,'format':'ZIP64'},open('build/evidence/archive-validation.json','w'))
