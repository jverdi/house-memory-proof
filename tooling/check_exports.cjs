const fs=require('fs');
const validator=require('../build/validation/node_modules/gltf-validator');
(async()=>{const result=await validator.validateBytes(new Uint8Array(fs.readFileSync('build/evidence/test.glb')),{uri:'test.glb',maxIssues:10000});fs.writeFileSync('build/evidence/gltf-validation.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result.issues));if(result.issues.numErrors)process.exit(1);})();
