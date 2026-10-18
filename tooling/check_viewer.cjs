const fs=require('fs'),path=require('path');
const {chromium}=require('../build/validation/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1000,height:760}}),errors=[],network=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(/^https?:/.test(r.url()))network.push(r.url())});
 await page.goto('file://'+path.resolve('build/evidence/offline-viewer.html'));
 await page.waitForFunction(()=>window.houseXrayViewer?.rendered||window.houseXrayError,{timeout:15000});
 const initial=await page.evaluate(()=>({viewer:window.houseXrayViewer,error:window.houseXrayError}));
 if(initial.error||!initial.viewer?.objects)throw Error(JSON.stringify(initial));
 await page.screenshot({path:'build/evidence/offline-viewer.png'});
 const stages=await page.locator('#stage option').count();if(stages>1){await page.selectOption('#stage',{index:1});await page.waitForTimeout(100)}
 const filtered=await page.evaluate(()=>window.houseXrayViewer.shown);
 await page.setViewportSize({width:390,height:844});await page.click('#reset');await page.waitForTimeout(100);await page.screenshot({path:'build/evidence/offline-viewer-mobile.png'});
 if(errors.length||network.length||filtered>initial.viewer.shown)throw Error(JSON.stringify({errors,network,initial,filtered}));
 fs.writeFileSync('build/evidence/offline-viewer-validation.json',JSON.stringify({passed:true,objects:initial.viewer.objects,stageFilteredObjects:filtered,externalRequests:network,errors,offlineFileProtocol:true},null,2));
 await page.goto('file://'+path.resolve('build/command-private/photo-curve-viewer.html'));
 await page.waitForFunction(()=>window.houseXrayViewer?.rendered||window.houseXrayError,{timeout:15000});
 const curve=await page.evaluate(()=>{
   const canvas=document.getElementById('view'),gl=canvas.getContext('webgl2'),pixels=new Uint8Array(canvas.width*canvas.height*4);
   gl.readPixels(0,0,canvas.width,canvas.height,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
   let coloredPixels=0;for(let i=0;i<pixels.length;i+=4)if(Math.max(pixels[i],pixels[i+1],pixels[i+2])>80)coloredPixels++;
   return {objects:window.houseXrayViewer?.objects,lines:window.houseXrayViewer?.lines,shown:window.houseXrayViewer?.shown,coloredPixels,webglError:gl.getError(),error:window.houseXrayError};
 });
 if(curve.error||curve.objects!==1||curve.lines!==1||curve.shown!==1||curve.coloredPixels<10||curve.webglError||errors.length||network.length)throw Error('Offline curve rendering failed');
 fs.writeFileSync('build/evidence/photo-curve-viewer-validation.json',JSON.stringify({passed:true,...curve,externalRequests:0,rawSourcePublished:false,physicalQualification:false},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
