// Both native runtimes consume the same private analytic source cases. Only
// aggregate geometry errors and relationship checks are emitted as evidence.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto'),cp=require('node:child_process');
const WebIFC=require('../../build/ifc-runtime/node_modules/web-ifc/web-ifc-api-node.js');
assert.equal(require('../../build/ifc-runtime/node_modules/web-ifc/package.json').version,'0.0.72');
const context={TextEncoder};vm.createContext(context);
for(const name of ['coordinates.js','properties.js'])vm.runInContext(fs.readFileSync('HouseMemoryProof/IFC/'+name,'utf8'),context);
const cases=JSON.parse(fs.readFileSync(process.argv[2]||'HouseMemoryProof/IFC/test-geometry.json','utf8'));
const sub=(a,b)=>a.map((x,i)=>x-b[i]),dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
(async()=>{
 const api=new WebIFC.IfcAPI();await api.Init();api.SetLogLevel(6);let maximumBoundsError=0,maximumVolumeError=0;
 for(const item of cases){
  const id=api.OpenModel(new Uint8Array(Buffer.from(item.source)),{COORDINATE_TO_ORIGIN:false});
  try{
   const properties=context.IFCProperties.prepare(api,id,WebIFC),coordinates=context.IFCCoordinates.metadata(api,id,WebIFC),frame=context.IFCCoordinates.frame(coordinates);
   const all=[];let volume=0;
   api.StreamAllMeshes(id,mesh=>{
    for(let part=0;part<mesh.geometries.size();part++){
     const placed=mesh.geometries.get(part),geometry=api.GetGeometry(id,placed.geometryExpressID);
     try{
      const raw=api.GetVertexArray(geometry.GetVertexData(),geometry.GetVertexDataSize()),indices=api.GetIndexArray(geometry.GetIndexData(),geometry.GetIndexDataSize()),m=placed.flatTransformation,points=[];
      if(!raw.length||!indices.length)continue;
      properties.markConverted(mesh.expressID);
      for(let i=0;i<raw.length;i+=6){const x=raw[i],y=raw[i+1],z=raw[i+2],p=frame.point([m[0]*x+m[4]*y+m[8]*z+m[12],m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14]]);points.push([p[0],-p[2],p[1]])}
      all.push(...points);const origin=points[0];let signed=0;
      for(let i=0;i<indices.length;i+=3)signed+=dot(sub(points[indices[i]],origin),cross(sub(points[indices[i+1]],origin),sub(points[indices[i+2]],origin)))/6;
      volume+=Math.abs(signed);
     }finally{geometry.delete()}
    }
   });
   for(let axis=0;axis<3;axis++)for(const [actual,expected] of [[Math.min(...all.map(p=>p[axis])),item.low[axis]],[Math.max(...all.map(p=>p[axis])),item.high[axis]]])maximumBoundsError=Math.max(maximumBoundsError,Math.abs(actual-expected));
   maximumVolumeError=Math.max(maximumVolumeError,Math.abs(volume-item.volume));
   assert(maximumBoundsError<1e-5,item.name+' bounds');assert(Math.abs(volume-item.volume)<1e-5,item.name+' solid volume: '+volume);
   const graph=properties.finish();graph.sourceSHA256=crypto.createHash('sha256').update(item.source).digest('hex');
   assert.equal(graph.summary.products,item.products);assert.equal(graph.summary.convertedProducts,item.converted);
   const records=new Map(graph.records.map(r=>[r.expressID,r]));
   assert.equal(records.get(70).fields.Name.value,'Synthetic copper');
   assert.equal(records.get(71).fields.RelatingMaterial.value,70);assert.equal(records.get(73).fields.RelatingType.value,72);
   if(item.name==='opening subtraction')assert.equal(records.get(55)?.fields.RelatedOpeningElement.value,54,'opening source relationship retained');
   cp.execFileSync('python3',['-c',`import sys,json,hashlib;sys.path.insert(0,'tooling');from ifc_properties_check import validate
r=json.load(sys.stdin);data=json.dumps(r).encode();ref=dict(asset=hashlib.sha256(data).hexdigest()+'.json',sourceSHA256=r['sourceSHA256'],summary=r['summary']);validate(data,ref,r['sourceSHA256']+'.ifc',[])`],{input:JSON.stringify(graph)});
  }finally{api.CloseModel(id)}
 }
 console.log(JSON.stringify({passed:true,analyticOnly:true,parser:'web-ifc-0.0.72 actual WASM',cases:cases.length,maximumBoundsErrorMetres:maximumBoundsError,maximumSolidVolumeErrorCubicMetres:maximumVolumeError,typeMaterialAndOpeningRelationsPreserved:true,rawFixturesPublished:false,physicalQualification:false}));
})().catch(error=>{console.error(error.message);process.exitCode=1});
