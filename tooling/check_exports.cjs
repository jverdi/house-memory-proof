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
(async()=>{for(const name of ['test','textured','points','house-surface']){
  const bytes=fs.readFileSync('build/evidence/'+name+'.glb');
  const result=await validator.validateBytes(new Uint8Array(bytes),{uri:name+'.glb',maxIssues:10000});
  fs.writeFileSync('build/evidence/'+name+'-gltf-validation.json',JSON.stringify(result,null,2));
  console.log(name,JSON.stringify(result.issues));if(result.issues.numErrors)process.exitCode=1;
  const structure=inspect(bytes);fs.writeFileSync('build/evidence/'+name+'-interchange.json',JSON.stringify(structure,null,2));console.log(name,JSON.stringify(structure));
}})().catch(error=>{console.error(error);process.exitCode=1;});
