// General GLB entry point using the same independent Khronos reader as CI.
// No external resource loader is installed; exported models must be self-contained.
const fs=require('node:fs'),crypto=require('node:crypto');
async function check(path){
  const size=fs.statSync(path).size;
  if(size<28||size>512*1024*1024)throw Error('GLB is outside the 512 MiB reader budget');
  const bytes=fs.readFileSync(path);
  if(bytes.readUInt32LE(0)!==0x46546c67||bytes.readUInt32LE(4)!==2||bytes.readUInt32LE(8)!==size)throw Error('Invalid GLB header');
  const length=bytes.readUInt32LE(12);
  if(length>100000000||20+length>size||bytes.readUInt32LE(16)!==0x4e4f534a)throw Error('Invalid bounded GLB JSON chunk');
  const doc=JSON.parse(bytes.subarray(20,20+length).toString('utf8'));
  if((doc.buffers??[]).some(b=>b.uri!==undefined)||(doc.images??[]).some(i=>i.uri!==undefined))throw Error('Self-contained GLB required; external or data-URI resources are not loaded');
  let validator;
  try{validator=require('../build/validation/node_modules/gltf-validator');}
  catch{throw Error('Independent Khronos reader is unavailable; use the prepared validation environment');}
  const result=await validator.validateBytes(new Uint8Array(bytes),{uri:'input.glb',maxIssues:10000});
  const codes={};for(const item of result.issues.messages??[])codes[item.code]=(codes[item.code]??0)+1;
  const report={passed:result.issues.numErrors===0,format:'GLB 2.0',reader:'Khronos glTF Validator',
    sha256:crypto.createHash('sha256').update(bytes).digest('hex'),bytes:size,
    errors:result.issues.numErrors,warnings:result.issues.numWarnings,issueCodes:codes,
    externalResourcesLoaded:false,sourceModified:false,physicalPrecisionQualified:false,
    houseXraySemanticsChecked:false};
  if(report.passed&&doc.asset?.generator==='House Xray'){
    try{report.structure=require('./check_exports.cjs').inspect(bytes);report.houseXraySemanticsChecked=true;}
    catch{report.passed=false;report.semanticError='House Xray hierarchy or camera timeline does not match its embedded source records';}
  }
  return report;
}
module.exports={check};
if(require.main===module){
  if(process.argv.length!==3){console.log(JSON.stringify({passed:false,error:'Usage: node tooling/model_check.cjs model.glb'}));process.exitCode=2;}
  else check(process.argv[2]).then(report=>{console.log(JSON.stringify(report));process.exitCode=report.passed?0:1;})
    .catch(error=>{console.log(JSON.stringify({passed:false,format:'GLB 2.0',error:error.message,externalResourcesLoaded:false,sourceModified:false}));process.exitCode=1;});
}
