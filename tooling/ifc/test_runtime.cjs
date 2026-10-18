// Actual pinned parser regression; raw graphs exist only in private process input.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto'),cp=require('node:child_process');
const WebIFC=require('../../build/ifc-runtime/node_modules/web-ifc/web-ifc-api-node.js');
assert.equal(require('../../build/ifc-runtime/node_modules/web-ifc/package.json').version,'0.0.72');
const context={TextEncoder};vm.createContext(context);
for(const file of ['coordinates.js','properties.js'])vm.runInContext(fs.readFileSync('HouseMemoryProof/IFC/'+file,'utf8'),context);
const base=fs.readFileSync('fixtures/block.ifc','utf8'),insert=(source,rows)=>source.replace('ENDSEC;\nEND-ISO',rows+'\nENDSEC;\nEND-ISO');
const ifc4=base.replace('IFC2X3','IFC4').replace('.ELEMENT.','.NOTDEFINED.');
const mm=ifc4.replace('.LENGTHUNIT.,$,.METRE.','.LENGTHUNIT.,.MILLI.,.METRE.').replace('#17,1.,2.','#17,1000.,2000.').replace('#18,#9,#7,3.','#18,#9,#7,3000.');
const properties=insert(mm,`#40=IFCBUILDINGSTOREY('2J$yPqHBD2TuLf$X2etp$2',#5,'Upper storey',$,$,#15,$,$,.ELEMENT.,3000.);
#41=IFCRELCONTAINEDINSPATIALSTRUCTURE('3J$yPqHBD2TuLf$X2etp$3',#5,$,$,(#22),#40);
#42=IFCPROPERTYSINGLEVALUE('Circuit',$,IFCLABEL('=literal source label'),$);
#43=IFCPROPERTYSINGLEVALUE('NominalDiameter',$,IFCLENGTHMEASURE(25.),#11);
#44=IFCPROPERTYSET('0J$yPqHBD2TuLf$X2etp$4',#5,'Pset_HouseXray',$,(#42,#43));
#45=IFCRELDEFINESBYPROPERTIES('1J$yPqHBD2TuLf$X2etp$5',#5,$,$,(#22),#44);`);
const partial=insert(properties,`#47=IFCBUILDINGELEMENTPROXY('1J$yPqHBD2TuLf$X2etp$1',#5,'Point-only source product',$,$,#15,#48,$,.NOTDEFINED.);
#48=IFCPRODUCTDEFINITIONSHAPE($,$,(#50));
#49=IFCGEOMETRICSET((#6));
#50=IFCSHAPEREPRESENTATION(#10,'Body','GeometricSet',(#49));`);
const units=(name,factor)=>insert(ifc4.replace('IFCUNITASSIGNMENT((#11,#12))','IFCUNITASSIGNMENT((#53,#12))'),`#51=IFCDIMENSIONALEXPONENTS(1,0,0,0,0,0,0);
#52=IFCMEASUREWITHUNIT(IFCLENGTHMEASURE(${factor}),#11);
#53=IFCCONVERSIONBASEDUNIT(#51,.LENGTHUNIT.,'${name}',#52);`);
const scaledCRS=schema=>insert(ifc4.replace('IFC4',schema),`#31=IFCPROJECTEDCRS('Synthetic map','Anisotropic documentary conversion',$,$,$,$,#11);
#32=IFCMAPCONVERSIONSCALED(#10,#31,500000.,4200000.,12.,0.,1.,0.001,0.9996,1.0004,1.002);`);
(async()=>{
 const api=new WebIFC.IfcAPI();await api.Init();api.SetLogLevel(6);
 const cases=[['IFC2x3',base,1],['IFC4 properties',properties,1],['point-only representation',partial,1],['malformed GUID',partial.replaceAll("'1J$yPqHBD2TuLf$X2etp$1'","'bad-guid'"),1],['missing GUID',partial.replaceAll("'1J$yPqHBD2TuLf$X2etp$1'",'$'),1],['foot',units('foot',.3048),.3048],['inch',units('inch',.0254),.0254],['IFC4X3',scaledCRS('IFC4X3'),1],['IFC4X3_ADD2',scaledCRS('IFC4X3_ADD2'),1]];
 for(const [name,source,scale] of cases){
  const model=api.OpenModel(new Uint8Array(Buffer.from(source)),{COORDINATE_TO_ORIGIN:false});
  try{
   const graph=context.IFCProperties.prepare(api,model,WebIFC),reference=context.IFCCoordinates.metadata(api,model,WebIFC),frame=context.IFCCoordinates.frame(reference);
   const positions=[];
   api.StreamAllMeshes(model,mesh=>{
    for(let index=0;index<mesh.geometries.size();index++){
     const placed=mesh.geometries.get(index),geometry=api.GetGeometry(model,placed.geometryExpressID);
     try{
      const vertices=api.GetVertexArray(geometry.GetVertexData(),geometry.GetVertexDataSize()),indices=api.GetIndexArray(geometry.GetIndexData(),geometry.GetIndexDataSize()),m=placed.flatTransformation;
      if(!vertices.length||!indices.length)continue;
      graph.markConverted(mesh.expressID);
      for(let i=0;i<vertices.length;i+=6){const x=vertices[i],y=vertices[i+1],z=vertices[i+2];positions.push(frame.point([m[0]*x+m[4]*y+m[8]*z+m[12],m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14]]))}
     }finally{geometry.delete()}
    }
   });
   const result=graph.finish();result.sourceSHA256=crypto.createHash('sha256').update(source).digest('hex');
   assert.equal(result.summary.convertedProducts,1);
   for(let axis=0;axis<3;axis++){const extent=Math.max(...positions.map(p=>p[axis]))-Math.min(...positions.map(p=>p[axis]));assert(Math.abs(extent-[1,3,2][axis]*scale)<1e-5,name+' metric geometry')}
   const si=result.records.find(r=>r.expressID===11);assert.deepEqual(Array.from(si.derivedFields),['Dimensions']);assert.equal(si.fields.Dimensions.value,0);
   if(name==='IFC4 properties'){assert.equal(result.storeys[0].elevation,3000);assert.equal(result.records.find(r=>r.expressID===43).fields.NominalValue.value,25)}
   if(name==='point-only representation'){assert.equal(result.summary.duplicateGUIDs,2);assert.equal(result.summary.unconvertedRepresentedProducts,1)}
   if(name==='malformed GUID')assert.equal(result.summary.malformedGUIDs,2);
   if(name==='missing GUID')assert.equal(result.summary.missingGUIDs,2);
   if(['foot','inch'].includes(name))assert.equal(reference.sourceLengthUnit,name);
   if(name.startsWith('IFC4X3')){
    assert.equal(reference.sourceSchema,name);assert.equal(reference.mapConversions.length,1);
    const values=reference.mapConversions[0].values;
    for(const [key,value] of Object.entries({Scale:.001,FactorX:.9996,FactorY:1.0004,FactorZ:1.002,Eastings:500000,Northings:4200000,XAxisAbscissa:0,XAxisOrdinate:1}))assert.equal(values[key],value);
    assert.equal(reference.mapConversions[0].targetCRS.MapUnit,'METRE');
   }
   cp.execFileSync('python3',['-c',`import sys,json,hashlib;sys.path.insert(0,'tooling');from ifc_properties_check import validate
r=json.load(sys.stdin);data=json.dumps(r).encode();ref=dict(asset=hashlib.sha256(data).hexdigest()+'.json',sourceSHA256=r['sourceSHA256'],summary=r['summary']);validate(data,ref,r['sourceSHA256']+'.ifc',[])`],{input:JSON.stringify(result)});
  }finally{api.CloseModel(model)}
 }
 console.log(JSON.stringify({passed:true,parser:'web-ifc-0.0.72 actual WASM',cases:cases.length,derivedSIUnitsPreserved:true,independentPropertyReaderPassed:true,rawGraphsPublished:false}));
})().catch(error=>{console.error(error.message);process.exitCode=1});
