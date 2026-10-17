const fs=require('fs');
const validator=require('../build/validation/node_modules/gltf-validator');
(async()=>{for(const name of ['test','textured']){const result=await validator.validateBytes(new Uint8Array(fs.readFileSync('build/evidence/'+name+'.glb')),{uri:name+'.glb',maxIssues:10000});fs.writeFileSync('build/evidence/'+name+'-gltf-validation.json',JSON.stringify(result,null,2));console.log(name,JSON.stringify(result.issues));if(result.issues.numErrors)process.exitCode=1;}})();
