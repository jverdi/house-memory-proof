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
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'build/evidence/offline-viewer-mobile.png'});
 if(errors.length||network.length||filtered>initial.viewer.shown)throw Error(JSON.stringify({errors,network,initial,filtered}));
 fs.writeFileSync('build/evidence/offline-viewer-validation.json',JSON.stringify({passed:true,objects:initial.viewer.objects,stageFilteredObjects:filtered,externalRequests:network,errors,offlineFileProtocol:true},null,2));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
