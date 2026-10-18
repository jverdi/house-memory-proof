const fs=require('fs');
const assert=require('node:assert/strict');
const validator=require('../build/validation/node_modules/gltf-validator');
function inspect(bytes) {
  const jsonLength=bytes.readUInt32LE(12);
  const doc=JSON.parse(bytes.subarray(20,20+jsonLength).toString());
  const binary=bytes.subarray(28+jsonLength);
  const roots=doc.scenes[doc.scene].nodes,seen=new Set(),parents=new Map();
  function walk(index,parent=null){
    assert(!seen.has(index),'node repeated or hierarchy cycle');seen.add(index);parents.set(index,parent);
    for(const child of doc.nodes[index].children??[])walk(child,index);
  }
  roots.forEach(n=>walk(n));assert.equal(seen.size,doc.nodes.length,'unreachable exported node');
  for(let i=0;i<doc.nodes.length;i++)if(doc.nodes[i].mesh!==undefined){
    const stage=doc.nodes[parents.get(i)],room=doc.nodes[parents.get(parents.get(i))];
    assert.equal(stage.extras.type,'stage');assert.equal(room.extras.type,'room');
    assert.equal(doc.nodes[i].extras.room,room.extras.id);assert.equal(doc.nodes[i].extras.stage,stage.extras.id);
  }
  function floats(index,width){const a=doc.accessors[index],v=doc.bufferViews[a.bufferView],offset=(v.byteOffset??0)+(a.byteOffset??0);assert.equal(a.componentType,5126);return Array.from({length:a.count*width},(_,i)=>binary.readFloatLE(offset+i*4));}
  const shots=doc.extras.tour.shots;
  assert.equal((doc.animations??[]).length,shots.length);
  assert.equal((doc.cameras??[]).length,shots.length);
  for(const [index,animation] of (doc.animations??[]).entries()){
    const shot=shots[index],ts=floats(animation.samplers[0].input,1),ps=floats(animation.samplers[0].output,3),qs=floats(animation.samplers[1].output,4);
    assert(ts.length>=2);assert.equal(ts[0],0);assert(Math.abs(ts.at(-1)-shot.duration)<1e-5);
    for(let i=1;i<ts.length;i++)assert(ts[i]>ts[i-1]);
    assert.equal(animation.channels[0].target.node,animation.channels[1].target.node);
    const node=doc.nodes[animation.channels[0].target.node];assert.equal(node.extras.room,shot.roomID);
    for(let i=0;i<ts.length;i++){
      const t=shot.startPhase+(ts[i]/shot.duration)*(shot.endPhase-shot.startPhase),smooth=t*t*(3-2*t);
      const p=shot.endPosition?['x','y','z'].map(k=>shot.position[k]+(shot.endPosition[k]-shot.position[k])*smooth):['x','y','z'].map(k=>shot.position[k]);
      const target=[p[0],p[2],-p[1]],actual=ps.slice(i*3,i*3+3);
      assert(actual.every((x,j)=>Math.abs(x-target[j])<2e-5),'tour position conversion or smoothing differs');
      const delta=Math.atan2(Math.sin((shot.endYaw??shot.yaw)-shot.yaw),Math.cos((shot.endYaw??shot.yaw)-shot.yaw));
      const yaw=shot.endPosition?shot.yaw+delta*smooth:shot.yaw+Math.sin(t*Math.PI)*.65;
      const pitch=shot.endPosition?shot.pitch+((shot.endPitch??shot.pitch)-shot.pitch)*smooth:shot.pitch;
      const q=qs.slice(i*4,i*4+4),expected=[Math.sin(pitch/2)*Math.cos(yaw/2),Math.sin(yaw/2)*Math.cos(pitch/2),-Math.sin(yaw/2)*Math.sin(pitch/2),Math.cos(yaw/2)*Math.cos(pitch/2)];
      assert(Math.abs(Math.hypot(...q)-1)<1e-5);assert(Math.abs(q.reduce((sum,x,j)=>sum+x*expected[j],0))>1-1e-5,'camera rotation mismatch');
    }
  }
  return {nodes:seen.size,meshes:doc.meshes.length,levels:roots.filter(i=>doc.nodes[i].extras?.type==='level').length,tourClips:shots.length,hierarchyAndAnimationPassed:true};
}
module.exports={inspect};
if(require.main===module)(async()=>{for(const name of ['test','textured','points','house-surface']){
  const bytes=fs.readFileSync('build/evidence/'+name+'.glb');
  const result=await validator.validateBytes(new Uint8Array(bytes),{uri:name+'.glb',maxIssues:10000});
  fs.writeFileSync('build/evidence/'+name+'-gltf-validation.json',JSON.stringify(result,null,2));
  console.log(name,JSON.stringify(result.issues));if(result.issues.numErrors)process.exitCode=1;
  const structure=inspect(bytes);fs.writeFileSync('build/evidence/'+name+'-interchange.json',JSON.stringify(structure,null,2));console.log(name,JSON.stringify(structure));
}
require('node:child_process').execFileSync('python3',['tooling/hm','export-check','--package','build/evidence/test.glb','--output','build/evidence/general-glb-validation.json'],{stdio:'inherit'});
// This small analytic route remains private. Publish only independent counts
// and aggregate coordinate error, never original tracks or image identities.
const routeBytes=fs.readFileSync('build/command-private/photo-curve.glb');
const routeResult=await validator.validateBytes(new Uint8Array(routeBytes),{uri:'photo-curve.glb',maxIssues:10000});
assert.equal(routeResult.issues.numErrors,0);
const length=routeBytes.readUInt32LE(12),route=JSON.parse(routeBytes.subarray(20,20+length).toString()),binary=routeBytes.subarray(28+length);
assert.equal(route.meshes.length,1);const primitive=route.meshes[0].primitives[0];assert.equal(primitive.mode,3);
const a=route.accessors[primitive.attributes.POSITION],view=route.bufferViews[a.bufferView];assert.equal(a.count,3);assert.equal(a.componentType,5126);
const offset=(view.byteOffset??0)+(a.byteOffset??0),expected=[[0,1.1,-1.4],[.3,1.3,-1.45],[.6,1.5,-1.4]];
let maximum=0;for(let i=0;i<3;i++)for(let axis=0;axis<3;axis++)maximum=Math.max(maximum,Math.abs(binary.readFloatLE(offset+(i*3+axis)*4)-expected[i][axis]));
assert(maximum<1e-6);const node=route.nodes.find(n=>n.mesh===0);assert.equal(node.extras.photoCurveSourceTracks.length,3);assert(node.extras.photoCurveSourceTracks.every(t=>t.controls.length===3));
const structure=inspect(routeBytes);
fs.writeFileSync('build/evidence/photo-curve-gltf-validation.json',JSON.stringify({passed:true,reader:'Khronos glTF Validator plus independent fixed-frame line reader',points:3,sourceTracks:3,mode:'LINE_STRIP',metricDiameterInvented:false,maximumCoordinateErrorMetres:maximum,physicalQualification:false,...structure},null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
