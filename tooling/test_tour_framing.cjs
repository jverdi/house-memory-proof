// Exercise the independent GLB camera reader with known geometry and mutations.
const assert=require('node:assert/strict'),{inspect}=require('./check_exports.cjs');
function fixture(change=()=>{}){
 const parts=[],bufferViews=[],accessors=[];let size=0;
 function floats(values,type,width){
  const bytes=Buffer.alloc(values.length*4);values.forEach((x,i)=>bytes.writeFloatLE(x,i*4));
  const view=bufferViews.length;bufferViews.push({buffer:0,byteOffset:size,byteLength:bytes.length});parts.push(bytes);size+=bytes.length;
  const index=accessors.length;accessors.push({bufferView:view,componentType:5126,count:values.length/width,type});return index;
 }
 const position=floats([-1,-1,-2,1,-1,-2,0,1,-2],'VEC3',3);
 const times=floats(Array.from({length:61},(_,i)=>i/30),'SCALAR',1);
 const translations=floats(Array(183).fill(0),'VEC3',3);
 const rotations=floats(Array.from({length:61},()=>[0,0,0,1]).flat(),'VEC4',4);
 accessors[position].min=[-1,-1,-2];accessors[position].max=[1,1,-2];accessors[times].min=[0];accessors[times].max=[2];
 const shot={roomID:'room',position:{x:0,y:0,z:0},yaw:0,pitch:0,duration:2,startPhase:0,endPhase:1,
   subject:{featureID:'feature',featureRevision:7,point:{x:0,y:2,z:0}},includesPlannedGeometry:false};
 const doc={asset:{version:'2.0'},scene:0,scenes:[{nodes:[0,5]}],nodes:[
  {children:[1],extras:{type:'level'}},{children:[2],extras:{type:'room',id:'room'}},
  {children:[3],extras:{type:'stage',id:'stage'}},{mesh:0,extras:{id:'feature',revision:7,room:'room',stage:'stage',evidence:'observed'}},
  {camera:0,extras:{room:'room'}},{children:[4]}],meshes:[{primitives:[{attributes:{POSITION:position}}]}],
  cameras:[{type:'perspective',perspective:{aspectRatio:16/9,yfov:65*Math.PI/180,znear:.03,zfar:150}}],
  animations:[{samplers:[{input:times,output:translations},{input:times,output:rotations}],channels:[{sampler:0,target:{node:4,path:'translation'}},{sampler:1,target:{node:4,path:'rotation'}}]}],
  bufferViews,accessors,buffers:[{byteLength:size}],extras:{tour:{motionProfile:'camera-motion-v1',framingProfile:'subject-frustum-v1',shots:[shot]}}};
 change(doc,parts);
 let json=Buffer.from(JSON.stringify(doc));json=Buffer.concat([json,Buffer.alloc((4-json.length%4)%4,32)]);
 const binary=Buffer.concat(parts),header=Buffer.alloc(20),binHeader=Buffer.alloc(8);
 header.writeUInt32LE(0x46546c67,0);header.writeUInt32LE(2,4);header.writeUInt32LE(28+json.length+binary.length,8);header.writeUInt32LE(json.length,12);header.writeUInt32LE(0x4e4f534a,16);
 binHeader.writeUInt32LE(binary.length,0);binHeader.writeUInt32LE(0x004e4942,4);
 return Buffer.concat([header,json,binHeader,binary]);
}
assert.equal(inspect(fixture()).tourClips,1);
for(const point of [{x:0,y:-2,z:0},{x:8,y:2,z:0},{x:0,y:.1,z:0}]){
 assert.throws(()=>inspect(fixture(doc=>{doc.extras.tour.shots[0].subject.point=point})),/subject (range|leaves)/);
}
assert.throws(()=>inspect(fixture(doc=>{doc.extras.tour.shots[0].subject.featureID='missing'})),/source identity/);
assert.throws(()=>inspect(fixture(doc=>{doc.extras.tour.shots[0].subject.featureRevision=8})),/source identity/);
assert.throws(()=>inspect(fixture(doc=>{delete doc.extras.tour.shots[0].subject})),/missing source-linked/);
assert.throws(()=>inspect(fixture(doc=>{doc.nodes[3].extras.evidence='planned'})),/planned geometry label/);
assert.equal(inspect(fixture(doc=>{doc.nodes[3].extras.evidence='planned';doc.extras.tour.shots[0].includesPlannedGeometry=true})).tourClips,1);
console.log(JSON.stringify({passed:true,cases:9,reader:'Independent GLB source identity, camera projection and planned-label contracts',rawFixturesPublished:false}));
