import Foundation
import CryptoKit
import SceneKit
import PDFKit
import SQLite3
import ImageIO
import CoreImage
import AVFoundation
import UIKit
import Darwin
import simd

@MainActor enum SelfTests {
    static func run(model:AppModel,includeMovie:Bool=false) async {
        guard let mainRepo=model.repository else{return}
        guard !model.captureInProgress else{model.error="Finish saving the capture before running diagnostics.";return}
        var results:[[String:Any]]=[]
        let wasBusy=model.busy;model.busy=true
        defer{model.busy=wasBusy}
        let runStarted=ProcessInfo.processInfo.systemUptime
        func mark(_ name:String,_ state:String="running") {
            model.status=name
            let progress:[String:Any]=["test":name,"state":state,"completedChecks":results.count,"elapsedSeconds":ProcessInfo.processInfo.systemUptime-runStarted,"memory":memorySample()]
            if let data=try? JSONSerialization.data(withJSONObject:progress,options:[.sortedKeys]) {try? DurableFiles.write(data,to:mainRepo.root.appendingPathComponent("self-test-progress.json"))}
            let partial:[String:Any] = ["completed":false,"sourceRevision":Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local","tests":results]
            if let data=try? JSONSerialization.data(withJSONObject:partial,options:[.sortedKeys]) {try? DurableFiles.write(data,to:mainRepo.root.appendingPathComponent("self-test-partial.json"))}
        }
        func check(_ name:String,_ body:()throws->Bool) async {
            mark(name)
            // Let the progress panel paint between bounded native checks.
            try? await Task.sleep(nanoseconds:20_000_000)
            let started=ProcessInfo.processInfo.systemUptime
            do{try Task.checkCancellation();let ok=try body();results.append(["test":name,"passed":ok,"seconds":ProcessInfo.processInfo.systemUptime-started])}
            catch{results.append(["test":name,"passed":false,"error":error.localizedDescription,"seconds":ProcessInfo.processInfo.systemUptime-started])}
            mark(name,"completed")
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("self-tests-"+UUID().uuidString)
        do {
            let repo=try Repository(root:folder);var house=DemoFactory.make()
            await check("Original asset reads refuse same-size corruption without rewriting saved bytes") {
                let isolated=try Repository(root:folder.appendingPathComponent("asset-read-integrity"))
                let original=Data("Captured original evidence".utf8),key=try isolated.put(original,ext:"bin")
                guard try isolated.read(key)==original,try isolated.read(key,limit:original.count)==original else{return false}
                do {_=try isolated.read(key,limit:original.count-1);return false}catch{}
                var corrupt=original;corrupt[3] ^= 1
                let file=try isolated.assetURL(key);try DurableFiles.write(corrupt,to:file)
                do {_=try isolated.read(key);return false}catch{}
                do {_=try isolated.read(key,limit:original.count);return false}catch{}
                return try Data(contentsOf:file)==corrupt
            }
            await check("Capture buffer copies reject mismatched formats and preserve row padding") {
                for format in [kCVPixelFormatType_DepthFloat32,kCVPixelFormatType_OneComponent8] {
                    let strideBytes=format==kCVPixelFormatType_DepthFloat32 ? 4:1
                    var allocated:CVPixelBuffer?
                    guard CVPixelBufferCreate(kCFAllocatorDefault,3,2,format,[kCVPixelBufferBytesPerRowAlignmentKey as String:64] as CFDictionary,&allocated)==kCVReturnSuccess,let buffer=allocated,
                      CVPixelBufferLockBaseAddress(buffer,[])==kCVReturnSuccess,let base=CVPixelBufferGetBaseAddress(buffer) else{return false}
                    let rowBytes=CVPixelBufferGetBytesPerRow(buffer)
                    memset(base,0xA5,rowBytes*2)
                    for row in 0..<2 {for column in 0..<3 {
                        if strideBytes==4 {base.advanced(by:row*rowBytes).assumingMemoryBound(to:Float.self)[column]=Float(row*3+column+1)/2}
                        else{base.advanced(by:row*rowBytes).assumingMemoryBound(to:UInt8.self)[column]=UInt8((row*3+column)%3)}
                    }}
                    CVPixelBufferUnlockBaseAddress(buffer,[])
                    let packed=try CaptureBuffers.copy(buffer,format:format,bytesPerPixel:strideBytes,width:3,height:2)
                    guard packed.count==6*strideBytes else{return false}
                    for i in 0..<6 {
                        if strideBytes==4 {guard Float(bitPattern:packed.uint32(i*4))==Float(i+1)/2 else{return false}}
                        else{guard packed[i]==UInt8(i%3) else{return false}}
                    }
                    for fault in 0..<3 {
                        do {_=try CaptureBuffers.copy(buffer,format:fault==0 ? kCVPixelFormatType_32BGRA:format,bytesPerPixel:fault==1 ? 2:strideBytes,width:fault==2 ? 4:3,height:2);return false}catch{}
                    }
                    guard CVPixelBufferLockBaseAddress(buffer,.readOnly)==kCVReturnSuccess else{return false}
                    let currentBase=CVPixelBufferGetBaseAddress(buffer)
                    let unchanged=rowBytes>3*strideBytes && currentBase?.advanced(by:3*strideBytes).assumingMemoryBound(to:UInt8.self).pointee==0xA5
                    CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
                    guard unchanged else{return false}
                }
                return true
            }
            await check("Capture provenance survives archive, durable recovery and legacy decoding") {
                let isolated=try Repository(root:folder.appendingPathComponent("capture-provenance"))
                var h=House.empty("Capture provenance")
                let segment=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);h.segments=[segment];try isolated.save(h)
                let key=try isolated.put(Data("original image fixture".utf8),ext:"jpg")
                let exif=try PropertyListSerialization.data(fromPropertyList:["ExposureTime":1.0/60.0,"FocalLength":5.7],format:.binary,options:0)
                let exifKey=try isolated.put(exif,ext:"plist")
                var o=Observation(roomID:segment.roomID,stageID:segment.stageID,segmentID:segment.id,timestamp:1,image:key,width:64,height:48,camera:Rigid().values,intrinsics:[32,0,32,0,32,24,0,0,1],tracking:"synthetic",light:800,sharpness:0.1)
                let metadata=CaptureMetadata(source:"analytic-replay",kind:.rgbPosed,mode:"synthetic-frame",deviceModel:"Synthetic fixture",systemVersion:"Test",frameTimestamp:1,receivedUTC:Date(timeIntervalSince1970:1000),receiptUptimeBeforeUTC:10,receiptUptimeAfterUTC:10.001,calibrationWidth:64,calibrationHeight:48,imagePixelFormat:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,depthEncoding:nil,confidenceEncoding:nil,depthTimestamp:nil,exifAsset:exifKey,unavailable:["frameToUTC":"No calibrated mapping","depthTimestamp":"No separate depth clock","motionTimestamp":"No motion sample","distortion":"Unavailable","depth":"No depth recorded","confidence":"No confidence recorded"])
                o.captureMetadata=metadata;h.observations=[o];try h.validate()
                guard h.assets==Set([key,exifKey]),metadata.valid(for:o) else{return false}
                var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(o)) as! [String:Any];legacy.removeValue(forKey:"captureMetadata")
                let old=try JSONDecoder().decode(Observation.self,from:JSONSerialization.data(withJSONObject:legacy))
                guard old.captureMetadata==nil,old.resolvedKind == .rgbPosed else{return false}
                for fault in 0..<9 {
                    var bad=metadata
                    switch fault {
                    case 0:bad.version=2
                    case 1:bad.frameTimestamp=2
                    case 2:bad.receiptUptimeAfterUTC=9
                    case 3:bad.calibrationWidth=63
                    case 4:bad.kind = .rgbdPosed
                    case 5:bad.depthEncoding="float32-le-metres-optical-axis"
                    case 6:bad.unavailable.removeValue(forKey:"depthTimestamp")
                    case 7:bad.exifAsset=nil
                    default:bad.depthTimestamp = .nan
                    }
                    var changed=h;changed.observations[0].captureMetadata=bad
                    do {try changed.validate();return false}catch{}
                }
                let archive=try Exporter.archive(h,repo:isolated)
                let restoredRepo=try Repository(root:folder.appendingPathComponent("capture-provenance-restore"))
                let restored=try Exporter.restore(archive,repo:restoredRepo)
                guard restored.observations==[o],try restoredRepo.read(exifKey)==exif else{return false}
                try isolated.stageCapture(o,projectID:h.id,room:h.rooms[0],stage:h.stages[0],segment:segment)
                guard try Repository(root:isolated.root).all().first?.observations==[o] else{return false}
                try isolated.journalCapture(projectID:h.id,observation:o)
                var corrupt=exif;corrupt[0] ^= 1;let exifURL=try isolated.assetURL(exifKey)
                try DurableFiles.write(corrupt,to:exifURL)
                guard try !isolated.recoverPendingCaptures().isEmpty,
                  FileManager.default.fileExists(atPath:isolated.captureJournal.appendingPathComponent(o.id.uuidString+".json").path),try Data(contentsOf:exifURL)==corrupt else{return false}
                try DurableFiles.write(exif,to:exifURL)
                guard try isolated.recoverPendingCaptures().isEmpty,try isolated.all().first?.observations==[o] else{return false}
                return try isolated.read(exifKey)==exif
            }
            mark("Depth confidence and bounded input admission")
            do {
                let isolated=try Repository(root:folder.appendingPathComponent("depth-input-admission"))
                let capture=try SimulatedCapture.make(repo:isolated),segment=capture.segments[0]
                let verified=try isolated.integrity(capture);var refused=0
                for fault in 0..<5 {
                    var changed=capture
                    for i in changed.observations.indices {
                        let o=changed.observations[i],count=o.depthWidth*o.depthHeight
                        switch fault {
                        case 0:changed.observations[i].confidence=nil
                        case 1:changed.observations[i].confidence=try isolated.put(Data(repeating:255,count:count),ext:"confidence8")
                        case 2:changed.observations[i].confidence=try isolated.put(Data(repeating:2,count:count+1),ext:"confidence8")
                        case 3:changed.observations[i].confidence=try isolated.put(Data(repeating:2,count:count-1),ext:"confidence8")
                        default:
                            var data=try isolated.read(o.depth!);data.append(0)
                            changed.observations[i].depth=try isolated.put(data,ext:"depth32")
                        }
                    }
                    do{_=try await Reconstruction.fuse(house:changed,segment:segment,repo:isolated,progress:{_ in})}catch{refused+=1}
                    do{_=try await SurfaceReconstruction.build(house:changed,segment:segment,repo:isolated,progress:{_ in})}catch{refused+=1}
                }
                guard refused==10,try isolated.integrity(capture)==verified else{throw HouseError.message("Depth admission accepted an invalid input or changed original evidence.")}
                results.append(["test":"Depth fusion refuses unknown confidence and malformed buffers","passed":true,"refusedInputs":refused,"originalAssetsVerified":verified,"physicalDeviceQualified":false])
            }catch{results.append(["test":"Depth fusion refuses unknown confidence and malformed buffers","passed":false,"error":error.localizedDescription])}
            mark("Capture tracking and clock admission")
            do {
                let isolated=try Repository(root:folder.appendingPathComponent("capture-clock-admission"))
                let original=try SimulatedCapture.make(repo:isolated),segment=original.segments[0],verified=try isolated.integrity(original)
                var synchronized=original
                for i in synchronized.observations.indices {
                    let o=synchronized.observations[i]
                    synchronized.observations[i].captureMetadata=CaptureMetadata(source:"analytic-replay",kind:.rgbdPosed,mode:"synthetic-frame",deviceModel:"Analytic fixture",systemVersion:"Synthetic",frameTimestamp:o.timestamp,receivedUTC:o.date,receiptUptimeBeforeUTC:10+o.timestamp,receiptUptimeAfterUTC:10.001+o.timestamp,calibrationWidth:o.width,calibrationHeight:o.height,imagePixelFormat:0,depthEncoding:"float32-le-metres-optical-axis",confidenceEncoding:"uint8-arkit-0-low-1-medium-2-high",depthTimestamp:o.timestamp,unavailable:["frameToUTC":"Not calibrated","motionTimestamp":"No independent motion samples","distortion":"No distortion calibration","exif":"Rendered fixture","pixelFormat":"Analytic array"])
                }
                try synchronized.validate()
                let positive=try await Reconstruction.fuse(house:synchronized,segment:segment,repo:isolated,progress:{_ in})
                guard !positive.mesh.vertices.isEmpty else{throw HouseError.message("Synchronized depth control was rejected.")}
                let synchronizedFirst=synchronized.observations[0]
                let centerControl=PhotoControl(observationID:synchronizedFirst.id,u:0.5,v:0.5)
                let centerPoint=V3(synchronizedFirst.camera[3],2,synchronizedFirst.camera[7])
                let centerDepth=try isolated.read(synchronizedFirst.depth!),centerConfidence=try isolated.read(synchronizedFirst.confidence!)
                guard BundleRefinement.measuredDepth(centerControl,point:centerPoint,observation:synchronizedFirst,data:centerDepth,confidence:centerConfidence)>1.99 else{throw HouseError.message("Synchronized joint-refinement depth control was rejected.")}
                var refused=0
                for fault in 0..<3 {
                    var changed=synchronized
                    for i in changed.observations.indices {
                        if fault==0 {changed.observations[i].captureMetadata!.depthTimestamp=changed.observations[i].timestamp+0.033}
                        else {changed.observations[i].tracking=fault==1 ? "limited(excessiveMotion)":"notAvailable"}
                    }
                    try changed.validate() // Retain valid raw records even when processing abstains.
                    do{_=try await Reconstruction.fuse(house:changed,segment:segment,repo:isolated,progress:{_ in})}catch{refused+=1}
                    do{_=try await SurfaceReconstruction.build(house:changed,segment:segment,repo:isolated,progress:{_ in})}catch{refused+=1}
                    do{_=try VisualMapping.build(house:changed,segment:segment,repo:isolated)}catch{refused+=1}
                    do{_=try TextureBuilder.build(house:changed,segment:segment,repo:isolated)}catch{refused+=1}
                    let first=changed.observations[0]
                    guard BundleRefinement.measuredDepth(centerControl,point:centerPoint,observation:first,data:centerDepth,confidence:centerConfidence)==0 else{throw HouseError.message("Joint refinement reused incompatible depth.")}
                    let camera=TextureBuilder.Camera(observation:first,depth:try isolated.read(first.depth!),confidence:try isolated.read(first.confidence!))
                    guard !TextureBuilder.visible(UV(u:0.5,v:0.5),z:2,camera:camera) else{throw HouseError.message("Incompatible depth was admitted by texture visibility.")}
                    let selected=PoseRefinement.selected(changed.observations,segment:segment,house:changed).0
                    guard selected.count==(fault==0 ? original.observations.count:0),changed.observations.allSatisfy({$0.spatialProcessingIssue != nil}),
                        try CoverageAnalyzer.analyze(house:changed,segment:segment,repo:isolated).supportedPatches==0 else{throw HouseError.message("Incompatible capture evidence contributed spatial support.")}
                    let boundary=RevealBoundary(name:"Clock check",segmentID:segment.id,origin:V3(-0.2,1.8,1.6),horizontal:V3(1,0,0),vertical:V3(0,0,-1),width:0.4,height:0.4,depth:0.2,finishOffset:0.01,sourceFingerprint:try VisualMapping.fingerprint(house:changed,segment:segment))
                    let coverage=try BoundaryCoverage.analyze(house:changed,boundary:boundary,repo:isolated)
                    guard coverage.supported==0,coverage.cameraCount==0,try isolated.integrity(changed)==verified else{throw HouseError.message("Clock/tracking fault was marked complete or changed an original.")}
                }
                guard refused==12,try isolated.integrity(original)==verified else{throw HouseError.message("Spatial processing accepted incompatible clock or tracking evidence.")}
                results.append(["test":"Known depth clock mismatch and limited tracking abstain without discarding originals","passed":true,"refusedPipelines":refused,"faultConditions":3,"originalAssetsVerified":verified,"synchronizedControlPassed":true,"physicalDeviceQualified":false])
            }catch{results.append(["test":"Known depth clock mismatch and limited tracking abstain without discarding originals","passed":false,"error":error.localizedDescription])}
            mark("Coded reference image-to-pose integration")
            do {results.append(try codedReferenceReport(repo:Repository(root:folder.appendingPathComponent("coded-references")),outputRoot:mainRepo.root))}
            catch {results.append(["test":"Coded reference images, saved corner provenance and finished-wall pose","passed":false,"error":error.localizedDescription])}
            await check("Multi-board pose holds out each board and rejects moved or duplicate references") {var error=0.0;return hx_reference_selftest(&error)==1 && error<0.003}
            await check("Pinned AprilTag identity, corner coordinates, rotation and duplicate rejection") {hx_tag_selftest()==1}
            await check("Object edits refuse stale metadata and rebuilt geometry without overwriting saved work") {
                let isolated=AppModel(root:folder.appendingPathComponent("object-edit-conflict"))
                var h=House.empty("Object edit contract")
                let feature=Feature(name:"Editable object",trade:.unknown,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.documentary,mesh:Mesh(vertices:[V3(1,1,1)],triangles:[]))
                h.features=[feature];guard isolated.commit(h),let before=isolated.house else{return false}
                var edited=feature;edited.notes="First committed edit"
                guard isolated.saveFeatureEdit(edited,expected:feature,projectID:h.id),let saved=isolated.house else{return false}
                guard saved.features[0].revision==feature.revision+1,saved.revision==before.revision+1 else{return false}
                var stale=feature;stale.notes="Must not overwrite"
                guard !isolated.saveFeatureEdit(stale,expected:feature,projectID:h.id),isolated.house==saved else{return false}
                let expected=saved.features[0]
                guard isolated.edit(projectID:h.id,{$0.features[0].mesh.vertices[0].x=2;$0.features[0].revision+=1}),let rebuilt=isolated.house else{return false}
                edited=expected;edited.reviewed=true
                guard !isolated.saveFeatureEdit(edited,expected:expected,projectID:h.id),isolated.house==rebuilt else{return false}
                edited=rebuilt.features[0];edited.id=UUID()
                guard !isolated.saveFeatureEdit(edited,expected:rebuilt.features[0],projectID:h.id) else{return false}
                return try isolated.repository!.all().first(where:{$0.id==h.id})==rebuilt
            }
            await check("Capture owns processing through final save and stale completion cannot unlock a new capture") {
                let isolated=AppModel(root:folder.appendingPathComponent("capture-lease")),first=UUID(),second=UUID()
                guard isolated.beginCapture(first),!isolated.beginCapture(second) else{return false}
                isolated.perform("Blocked export"){nil}
                guard !isolated.busy,isolated.captureInProgress else{return false}
                isolated.endCapture(first)
                guard isolated.beginCapture(second) else{return false}
                isolated.endCapture(first)
                guard isolated.captureInProgress else{return false}
                isolated.endCapture(second);isolated.busy=true
                guard !isolated.beginCapture(first) else{return false}
                isolated.busy=false;return !isolated.captureInProgress
            }
            await check("Typed service evidence preserves unknowns, rejects invalid claims and survives search and archive restore") {
                var h=House.empty("Service evidence contract")
                let segment=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);h.segments=[segment]
                let boundary=RevealBoundary(name:"North service wall",segmentID:segment.id,origin:V3(),horizontal:V3(1,0,0),vertical:V3(0,0,1),width:3,height:2,depth:0.2,finishOffset:0.02,sourceFingerprint:"synthetic service contract")
                h.boundaries=[boundary]
                var feature=Feature(name:"Unknown prewire",trade:.lowVoltage,roomID:segment.roomID,stageID:segment.stageID,kind:.synthetic,mesh:Mesh(vertices:[V3(1,1,1)],triangles:[]))
                let legacy=try JSONEncoder().encode(feature)
                guard try JSONDecoder().decode(Feature.self,from:legacy).service==nil else{return false}
                var details=ServiceDetails();details.classification = .lowVoltage;details.observedLabel="AV café 12";details.panelReference="Rack A";details.circuitReference="Branch 7";details.cableCategory="CAT6A";details.endpoint="Living speaker";details.port="P-24";details.conduitSize="25 mm recorded";details.pipeDuctEnvelope="Unknown";details.installationDate="2024-02-29";details.boundaryID=boundary.id;details.confidence = .ownerConfirmed;details.identityEvidence="Synthetic continuity-test record"
                feature.service=details;h.features=[feature];try h.validate()
                let index=try EvidenceSearch.Index(house:h)
                for query in ["CAT6A P-24","cafe rack","2024-02-29",feature.id.uuidString.lowercased(),"North service wall"] {
                    guard try index.find(query).features.map({$0.id})==[feature.id] else{return false}
                }
                let package=try Exporter.archive(h,repo:repo),target=try Repository(root:folder.appendingPathComponent("service-restore"))
                let restored=try Exporter.restore(package,repo:target)
                guard restored.features==h.features,restored.boundaries==h.boundaries,restored.connections.isEmpty else{return false}
                for value in ["2025-02-29","2024-02-30","2024-13-01","2024-1-01","0000-01-01","2024-02-29T00:00:00Z"] {
                    var bad=h;bad.features[0].service!.installationDate=value
                    do{try bad.validate();return false}catch{}
                }
                for fault in 0..<5 {
                    var bad=h
                    switch fault {
                    case 0:bad.features[0].service!.identityEvidence=" \n"
                    case 1:bad.features[0].service!.observedLabel=String(repeating:"é",count:2049)
                    case 2:bad.features[0].service!.port="bad\0port"
                    case 3:bad.features[0].service!.boundaryID=UUID()
                    default:bad.segments[0].stageID=h.stages[1].id
                    }
                    do{try bad.validate();return false}catch{}
                }
                h.features[0].service=ServiceDetails();try h.validate()
                return h.features[0].mesh==feature.mesh && h.connections.isEmpty
            }
            await check("Batch classification commits one reversible revision and refuses stale selected objects atomically") {
                let isolated=AppModel(root:folder.appendingPathComponent("batch-classification"))
                var h=House.empty("Batch classification contract")
                let source=Feature(name:"A",trade:.unknown,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.synthetic,mesh:Mesh(vertices:[V3(1,2,3)],triangles:[]),route:[V3(),V3(1,0,0)])
                var second=source;second.id=UUID();second.name="B";second.service=ServiceDetails(port:"P-24",confidence:.ownerConfirmed,identityEvidence:"Synthetic witnessed test")
                var untouched=source;untouched.id=UUID();untouched.name="C"
                h.features=[source,second,untouched];h.connections=[ServiceConnection(fromFeature:source.id,fromEnd:1,toFeature:second.id,toEnd:0,confirmed:true)]
                guard isolated.commit(h),let before=isolated.house else{return false}
                guard isolated.classifyFeatures([source,second],classification:.lowVoltage,trade:.lowVoltage,projectID:h.id),let saved=isolated.house else{return false}
                guard saved.revision==before.revision+1,saved.features[2]==untouched,saved.connections==before.connections,
                  saved.features[0].mesh==source.mesh,saved.features[0].route==source.route,saved.features[1].service?.port=="P-24",
                  saved.features[1].service?.confidence == .ownerConfirmed,saved.features[0].revision==source.revision+1 else{return false}
                guard !isolated.classifyFeatures([saved.features[0],second],classification:.power,trade:.electrical,projectID:h.id),isolated.house==saved else{return false}
                isolated.undo()
                guard isolated.house?.features==before.features,isolated.house?.connections==before.connections else{return false}
                return try isolated.repository!.all().first(where:{$0.id==h.id})==isolated.house
            }
            mark("Foreground fallback, resource cooldown and cancellation preserve saved work")
            do {
                let isolated=AppModel(root:folder.appendingPathComponent("continued-fallback"))
                isolated.create("Preserved project");let original=isolated.house
                isolated.setProcessingForeground(true)
                isolated.perform("Foreground-only operation") {try await Task.sleep(nanoseconds:5_000_000_000);return nil}
                isolated.setProcessingForeground(false)
                for _ in 0..<50 {if !isolated.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
                guard !isolated.busy,!isolated.continuedProcessing.granted,isolated.processingPause == .waitingForForeground,
                  isolated.status.contains("Waiting for the app"),isolated.house==original else{throw HouseError.message("Foreground fallback failed to pause and preserve the saved project.")}
                isolated.setProcessingForeground(true)
                isolated.perform("Resource constrained operation") {try await Task.sleep(nanoseconds:5_000_000_000);return nil}
                isolated.cancelOperation(reason:.waitingForResources)
                for _ in 0..<50 {if !isolated.busy {break};try await Task.sleep(nanoseconds:20_000_000)}
                guard !isolated.busy,isolated.processingPause == .waitingForResources,isolated.resourceRetryAfter>ProcessInfo.processInfo.systemUptime,
                  isolated.status.contains("Waiting for resources"),isolated.house==original else{throw HouseError.message("Resource pause did not retain its cooldown or originals.")}
                isolated.scheduleResourceRetry()
                guard isolated.resourceRetryTask != nil else{throw HouseError.message("Foreground resource retry was not scheduled.")}
                isolated.setProcessingForeground(false)
                guard isolated.resourceRetryTask==nil else{throw HouseError.message("Background transition retained a foreground retry timer.")}
                isolated.setProcessingForeground(true);isolated.resourceRetryAfter=ProcessInfo.processInfo.systemUptime+0.05
                isolated.scheduleResourceRetry()
                for _ in 0..<50 {if isolated.resourceRetryTask==nil {break};try await Task.sleep(nanoseconds:20_000_000)}
                guard isolated.resourceRetryTask==nil,!isolated.busy,isolated.house==original else{throw HouseError.message("Resource retry did not recheck the idle queue after cooldown.")}
                results.append(["test":"Foreground fallback, resource cooldown and cancellation preserve saved work","passed":true,"backgroundGPUAvailable":ContinuedProcessing.backgroundGPUAvailable,"physicalBackgroundExecutionQualified":false])
            }catch {results.append(["test":"Foreground fallback, resource cooldown and cancellation preserve saved work","passed":false,"error":error.localizedDescription])}
            await check("Durable capture rows recover without rewriting the project and survive a stale checkpoint") {
                let repo=try Repository(root:folder.appendingPathComponent("capture-rows"))
                var h=try SimulatedCapture.make(repo:repo);let original=h.observations;h.observations=[];try repo.save(h)
                let room=h.rooms[0],stage=h.stages.first{$0.id==h.segments[0].stageID}!,segment=h.segments[0]
                for o in original.prefix(2) {try repo.stageCapture(o,projectID:h.id,room:room,stage:stage,segment:segment)}
                let reopened=try Repository(root:repo.root)
                guard let restored=try reopened.all().first(where:{$0.id==h.id}),restored.observations==Array(original.prefix(2)) else{return false}
                // A checkpoint created before the second append must not erase it.
                h.observations=[original[0]];try repo.save(h)
                guard let after=try reopened.all().first(where:{$0.id==h.id}),after.observations==Array(original.prefix(2)) else{return false}
                try repo.save(after)
                guard try reopened.all().first(where:{$0.id==h.id})?.observations==after.observations else{return false}
                try repo.stageCapture(original[2],projectID:h.id,room:room,stage:stage,segment:segment)
                var conflicting=original[2];conflicting.note="Conflicting record"
                do {try repo.stageCapture(conflicting,projectID:h.id,room:room,stage:stage,segment:segment);return false}catch{return true}
            }
            await check("Reveal clips crossing triangles and rejects opposite wall and viewpoint") {
                let b=RevealBoundary(name:"Test",segmentID:UUID(),origin:V3(),horizontal:V3(1,0,0),vertical:V3(0,1,0),width:1,height:1,depth:0.2,finishOffset:0.01,sourceFingerprint:"test")
                var f=house.features[0];f.mesh=Mesh(vertices:[V3(-1,0.2,0.1),V3(2,0.2,0.1),V3(0.5,2,0.1)],triangles:[0,1,2]);f.uv=[UV(u:0,v:0),UV(u:1,v:0),UV(u:0.5,v:1)]
                let clipped=try RevealVolumes.clip(f,to:b)
                f.mesh.vertices=f.mesh.vertices.map{$0+V3(0,0,1)}
                let opposite=try RevealVolumes.clip(f,to:b)
                return b.valid && clipped.mesh.valid && !clipped.mesh.triangles.isEmpty && clipped.uv?.count==clipped.mesh.vertices.count && clipped.mesh.vertices.allSatisfy{let q=b.coordinates($0);return q.x >= -1e-9 && q.x<=1+1e-9 && q.y>=(-1e-9) && q.y<=1+1e-9 && q.z<=0.2} && opposite.mesh.vertices.isEmpty && b.viewedFromFront(V3(0,0,-1)) && !b.viewedFromFront(V3(0,0,1))
            }
            await check("Shared reference registration checks third board and invalidates dependencies") {
                var h=House.empty("Registration test");var anchor=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);anchor.registration=Rigid()
                var source=Segment(roomID:h.rooms[0].id,stageID:h.stages[1].id)
                for i in 0..<3 {let board=ReferenceBoard(name:"Board",image:"test.png",pdf:"test.pdf");h.references.append(board);var a=Rigid();a.values[3]=Double(i)*0.6;a.values[7]=1;a.values[11] = -2-Double(i)*0.2;var b=a;b.values[3]-=1;anchor.referencePoses.append(ReferencePose(boardID:board.id,matrix:a.values));source.referencePoses.append(ReferencePose(boardID:board.id,matrix:b.values))}
                h.segments=[anchor,source]
                let(t,residual,link)=try ReferenceRegistration.fit(source:source,anchor:anchor,house:h)
                guard (t.apply(V3())-V3(1,0,0)).length<1e-8,residual<1e-8 else{return false}
                source.registration=t;source.registrationLink=link;h.segments[1]=source
                h=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(h))
                guard h.segments[1].registrationLink==link else{return false}
                ReferenceRegistration.invalidateChangedInputs(&h);guard h.segments[1].registration != nil else{return false}
                h.segments[0].registration!.values[3]=0.1;ReferenceRegistration.invalidateChangedInputs(&h)
                guard h.segments[1].registration==nil else{return false}
                let third=link.boardIDs[2];let index=source.referencePoses.firstIndex{$0.boardID==third}!
                source.referencePoses[index].matrix[3]+=0.1
                do {_=try ReferenceRegistration.fit(source:source,anchor:anchor,house:h);return false}catch{return true}
            }
            mark("Chained session registration and independent controls")
            do {results.append(try registrationChainReport())}
            catch {results.append(["test":"Chained session registration preserves the house frame and invalidates descendants","passed":false,"error":error.localizedDescription])}
            await check("Display reduction uses bounded source points without perforated triangles") {
                let mesh=Mesh.box(center:V3(),size:V3(2,3,4)),uv=mesh.vertices.map{UV(u:$0.x,v:$0.y)}
                let reduced=DisplayGeometry.reduce(mesh,uv:uv,budget:9)
                guard reduced.0.valid,reduced.0.vertices.count<=9,reduced.0.triangles.isEmpty,reduced.1?.count==reduced.0.vertices.count else{return false}
                return zip(reduced.0.vertices,reduced.1!).allSatisfy{mesh.vertices.contains($0.0) && $0.1.u==$0.0.x && $0.1.v==$0.0.y} && mesh.vertices.count==8
            }
            await check("Spatial display tiles preserve source primitives, UVs, budgets and room movement") {
                var features:[Feature]=[]
                for i in 0..<80 {
                    var f=house.features[0];f.id=UUID();f.mesh = .box(center:V3(Double(i)-40,Double(i%4),0),size:V3(1,1,2))
                    f.uv=f.mesh.vertices.map{UV(u:$0.x,v:$0.y)};f.texture="texture-\(i).jpg";features.append(f)
                }
                let index=try SpatialDisplayIndex(features:features)
                guard index.tiles.reduce(0,{$0+$1.primitives.count})==80*12 else{return false}
                for i in features.indices {let references=index.tiles.filter{$0.feature==i}.flatMap{$0.primitives};guard references.count==12,Set(references).count==12 else{return false}}
                let near=index.plan(camera:V3(-40,0,1.6),budget:600,residents:20),far=index.plan(camera:V3(40,0,1.6),budget:600,residents:20)
                guard near.count<=20,near.reduce(0,{$0+$1.budget})<=600,near.first?.tile != far.first?.tile else{return false}
                let textures=Set(near.filter{$0.textured}.compactMap{index.features[index.tiles[$0.tile].feature].texture})
                guard textures.count<=24 else{return false}
                for a in near {
                    let (f,m,uv)=index.materialize(a)
                    guard m.valid,m.triangles.count<=a.budget,m.vertices.count<=a.budget,uv?.count==m.vertices.count else{return false}
                    guard zip(m.vertices,uv!).allSatisfy({f.mesh.vertices.contains($0.0) && $0.1.u==$0.0.x && $0.1.v==$0.0.y}) else{return false}
                }
                do {_=try SpatialDisplayIndex(features:features,primitiveLimit:10);return false}catch{return true}
            }
            await check("Traced annotation loses eligibility when source revision or registration changes") {
                var h=House.empty("Annotation inputs");var segment=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);segment.registration=Rigid();h.segments=[segment]
                var source=Feature(name:"Wall",trade:.structure,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.observed,mesh:.box(center:V3(),size:V3(2,0.1,3)),segmentID:segment.id)
                var annotation=source;annotation.id=UUID();annotation.name="Traced service";annotation.segmentID=nil
                annotation.annotationSources=[AnnotationDependency(featureID:source.id,revision:source.revision,segmentID:segment.id,registration:segment.registration)]
                h.features=[source,annotation];try h.validate()
                let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(h))
                let dimension=Dimension(name:"Wall size",a:V3(),b:V3(1,0,0),roomID:h.rooms[0].id,sourceRevision:h.revision,sourceGeometry:annotation.annotationSources)
                guard DerivedEvidence.currentIDs(restored).contains(annotation.id),DerivedEvidence.measurementIsCurrent(dimension,house:restored) else{return false}
                h.segments[0].registration!.values[3]=0.1
                guard !DerivedEvidence.currentIDs(h).contains(annotation.id),!DerivedEvidence.measurementIsCurrent(dimension,house:h) else{return false}
                h=restored;source.revision+=1;h.features[0]=source
                guard !DerivedEvidence.currentIDs(h).contains(annotation.id) else{return false}
                h=restored;h.features[0].artifactValid=false
                return !DerivedEvidence.currentIDs(h).contains(annotation.id)
            }
            await check("Reference placement distinguishes staggered controls from coplanar columns") {
                let flat=[V3(0,0,0),V3(0,0,1),V3(1,1,0),V3(1,1,1)]
                let staggered=[V3(0.45,1.8,-0.5),V3(1.15,1.8,0.65),V3(0.75,1.8,0.1),V3(2.05,1.2,-0.45),V3(2.05,0.55,0.65),V3(2.05,0.95,0.15)]
                let a=ReferenceLayout.assess(staggered),b=ReferenceLayout.assess(staggered.map{V3(-$0.y+17,$0.x-6,$0.z+8)})
                return !ReferenceLayout.assess(flat).distributed && a.distributed && b.distributed && zip(a.variances,b.variances).allSatisfy{abs($0-$1)<1e-10} && !ReferenceLayout.assess([V3(),V3(),V3(),V3()]).distributed
            }
            await check("Capture face labels preserve every triangle and isolate ceiling layers") {
                var h=House.empty("Face labels");let room=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:room.id,stageID:stage.id);h.segments=[segment]
                let mesh=Mesh(vertices:[V3(),V3(1,0,0),V3(0,1,0),V3(0,0,1)],triangles:[0,1,2,0,2,3,1,2,3])
                let anchor=UUID(),parts=MeshSemantics.partition(mesh,labels:["floor","ceiling","unsupported"],anchor:anchor,roomID:room.id,stage:stage,segmentID:segment.id)
                h.features=parts;try h.validate()
                guard parts.count==3,parts.reduce(0,{$0+$1.mesh.triangles.count})==9,parts.allSatisfy({$0.mesh.valid && $0.captureAnchorID==anchor}),Set(parts.map{$0.id}).count==3 else{return false}
                guard !SceneBuilder.features(h,options:SceneOptions()).contains(where:{$0.trade == .ceiling}),SceneBuilder.features(h,options:SceneOptions(ceilings:true)).contains(where:{$0.trade == .ceiling}) else{return false}
                return MeshSemantics.partition(mesh,labels:["floor","ceiling","unsupported"],anchor:anchor,roomID:room.id,stage:stage,segmentID:segment.id).map{$0.id}==parts.map{$0.id}
            }
            await check("Repeated classified capture snapshots keep identity and invalidate changed source geometry") {
                var h=House.empty("Capture updates");let room=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:room.id,stageID:stage.id);h.segments=[segment]
                let mesh=Mesh(vertices:[V3(),V3(1,0,0),V3(0,1,0)],triangles:[0,1,2]),anchor=UUID()
                let first=MeshSemantics.partition(mesh,labels:["floor"],anchor:anchor,roomID:room.id,stage:stage,segmentID:segment.id)
                MeshSemantics.publishCaptured(first,segmentID:segment.id,into:&h)
                h.features[0].name="Owner's renamed floor"
                let annotation=Feature(name:"Traced route",trade:.electrical,roomID:room.id,stageID:stage.id,kind:.observed,mesh:mesh,segmentID:segment.id,annotationSources:[AnnotationDependency(featureID:first[0].id,revision:1,segmentID:segment.id,registration:nil)])
                h.features.append(annotation)
                MeshSemantics.publishCaptured(first,segmentID:segment.id,into:&h);try h.validate()
                guard h.features.count==2,DerivedEvidence.currentIDs(h).contains(annotation.id) else{return false}
                var changed=first;changed[0].mesh.vertices[0].z=0.02
                MeshSemantics.publishCaptured(changed,segmentID:segment.id,into:&h);try h.validate()
                guard let floor=h.features.first(where:{$0.id==first[0].id}) else{return false}
                return h.features.count==2 && floor.name=="Owner's renamed floor" && floor.revision==2 && !DerivedEvidence.currentIDs(h).contains(annotation.id)
            }
            await check("Surface refinement retains supported ceiling labels and leaves conflicts unknown") {
                var h=House.empty("Classified surface");let room=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:room.id,stageID:stage.id);h.segments=[segment]
                let mesh=Mesh(vertices:[V3(0,0,2),V3(1,0,2),V3(0,1,2)],triangles:[0,1,2])
                let originals=MeshSemantics.partition(mesh,labels:["ceiling"],anchor:UUID(),roomID:room.id,stage:stage,segmentID:segment.id)
                var fused=Feature(name:"Renamed fusion",trade:.unknown,roomID:room.id,stageID:stage.id,kind:.synthetic,mesh:mesh,segmentID:segment.id,geometrySource:.depthFusion)
                fused.mesh.vertices=fused.mesh.vertices.map{$0+V3(0,0,0.015)}
                let parts=try MeshSemantics.transfer(fused,from:originals)
                guard parts.count==1,parts[0].trade == .ceiling,parts[0].mesh==fused.mesh else{return false}
                h.features=parts
                guard SceneBuilder.features(h,options:SceneOptions()).isEmpty,SceneBuilder.features(h,options:SceneOptions(ceilings:true)).count==1 else{return false}
                var conflict=originals[0];conflict.id=UUID();conflict.captureClassification="floor";conflict.trade = .floor
                let ambiguous=try MeshSemantics.transfer(fused,from:originals+[conflict])
                guard ambiguous.count==1,ambiguous[0].trade == .unknown else{return false}
                fused.mesh.vertices=fused.mesh.vertices.map{$0+V3(0,0,0.1)}
                let unsupported=try MeshSemantics.transfer(fused,from:originals)
                return unsupported.count==1 && unsupported[0].trade == .unknown && unsupported[0].mesh==fused.mesh
            }
            await check("Field evidence separates validation, preserves abstentions and never enables precision") {
                var h=House.empty("Field record")
                let dimension=Dimension(name:"Fixture width",a:V3(),b:V3(1.01,0,0),roomID:h.rooms[0].id,sourceRevision:1)
                let check=FieldCheck(split:.validation,kind:.distance,fixture:"Independent region",session:"Later session",conditions:"Fixture",device:"Synthetic test device",sourceBuild:"test",cameraMode:"synthetic",truthUncertainty:0.002,cameraDistance:1.5,measurement:dimension,referenceDistance:1,referencePoint:nil)
                var abstention=check;abstention.id=UUID();abstention.abstained=true;abstention.measurement=nil
                var calibration=check;calibration.id=UUID();calibration.split = .calibration;calibration.referenceDistance=0.5
                h.fieldChecks=[check,abstention,calibration];try h.validate()
                let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(h)),summary=FieldEvidence.summary(restored.fieldChecks,split:.validation)
                guard restored.fieldChecks==h.fieldChecks,summary.attempts==2,summary.accepted==1,abs((summary.p95Metres ?? 1)-0.01)<1e-9,!summary.precisionProfileEnabled else{return false}
                var invalid=check;invalid.referenceDistance = -1;return !invalid.valid
            }
            await check("Construction category survives arbitrary stage names") {
                var h=house;h.stages[0].name="After inspection";h.stages[0].phase = .rough;h.stages[1].name="Ready to paint";h.stages[1].phase = .finished
                let decoded=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(h))
                return SceneBuilder.eligibleStages(decoded,options:SceneOptions(mode:.rough))==[h.stages[0].id] && SceneBuilder.eligibleStages(decoded,options:SceneOptions(mode:.finished))==[h.stages[1].id]
            }
            await check("Ceres joint solver checks derivatives and rejects corrupt or disconnected evidence") {
                var error=0.0;let status=hx_bundle_selftest(&error)
                guard status==1 else{throw HouseError.message("Joint solver diagnostic failed at gate \(status).")};return error<0.003
            }
            await check("Image-track joint refinement survives save/reload without changing raw cameras") {
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                var capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let original=capture.observations
                capture.segments[0].poseSolution=try PoseGraph.build(house:capture,segment:capture.segments[0],repo:repo)
                let graph=capture.segments[0].poseSolution!,anchorID=graph.anchorObservationID!
                let result=try BundleRefinement.build(house:capture,segment:capture.segments[0],repo:repo)
                guard result.solution.anchorObservationID==anchorID,let before=graph.cameras[anchorID.uuidString],let after=result.solution.cameras[anchorID.uuidString],zip(before,after).allSatisfy({abs($0-$1)<1e-10}) else{return false}
                capture.segments[0].poseSolution=result.solution;capture.features=[result.feature]
                let decoded=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(capture));try decoded.validate()
                guard decoded.observations==original,decoded.segments[0].poseSolution==result.solution,(result.solution.bundleCheckRMS ?? 100)<2,DerivedEvidence.currentIDs(decoded).contains(result.feature.id),result.solution.landmarks?.count==result.solution.bundlePointCount else{return false}
                let map=try VisualMapping.build(house:decoded,segment:decoded.segments[0],repo:repo),optimized=Set(result.solution.landmarks!.map{$0.point})
                guard map.points.contains(where:{optimized.contains($0)}),let supportedIndex=result.solution.landmarks!.firstIndex(where:{map.points.contains($0.point)}) else{return false}
                var foreground=decoded
                foreground.segments[0].poseSolution!.landmarks![supportedIndex].point.y-=0.5
                let contradicted=try VisualMapping.build(house:foreground,segment:foreground.segments[0],repo:repo)
                guard contradicted.points.count<map.points.count,foreground.observations==original else{throw HouseError.message("A photograph landmark with contradictory background depth was silently relocated instead of excluded.")}
                var corrupted=decoded;corrupted.segments[0].poseSolution?.landmarks?[0].controls[0].observationID=UUID()
                do{try corrupted.validate();return false}catch{}
                var shifted=decoded;shifted.segments[0].poseSolution?.landmarks?[0].point.x+=0.01
                return try VisualMapping.fingerprint(house:shifted,segment:shifted.segments[0]) != VisualMapping.fingerprint(house:decoded,segment:decoded.segments[0])
            }
            await check("RGB-only multi-view triangulation retains independent point provenance") {
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                var capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                for i in capture.observations.indices {capture.observations[i].depth=nil;capture.observations[i].confidence=nil}
                let result=try PhotoReconstruction.build(house:capture,segment:capture.segments[0],repo:repo)
                capture.features=[result];try capture.validate()
                return result.mesh.vertices.count>=20 && result.pointTracks?.count==result.mesh.vertices.count && result.pointTracks!.allSatisfy{$0.controls.count>=3}
            }
            await check("One-photo annotations remain two-dimensional and preserve originals through archive restore") {
                var h=House.empty("2D-only photograph")
                let bytes=Data("unchanged single photograph original".utf8),key=try repo.put(bytes,ext:"jpg")
                let points=[UV(u:0.1,v:0.2),UV(u:0.8,v:0.7),UV(u:0.3,v:0.9)]
                let marks=[ImageAnnotation(kind:.point,points:[points[0]],label:"<script>unsafe</script> & endpoint",reviewed:true),
                           ImageAnnotation(kind:.box,points:Array(points.prefix(2)),label:"Box"),
                           ImageAnnotation(kind:.polygon,points:points,label:"Visible envelope"),
                           ImageAnnotation(kind:.curve,points:points,label:"Visible route only")]
                h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id,annotations:marks)]
                try h.validate();let input=try JSONEncoder().encode(h)
                let package=try Exporter.archive(h,repo:repo),target=try Repository(root:folder.appendingPathComponent("annotation-restore"))
                let entries=try StreamingArchive.index(package)
                guard let entry=entries["index.html"],let html=String(data:try StreamingArchive.read(entry,from:package),encoding:.utf8),
                      html.contains("&lt;script&gt;unsafe&lt;/script&gt; &amp; endpoint"),!html.contains("<script>unsafe</script>"),
                      html.contains("<circle"),html.contains("<rect"),html.contains("<polygon"),html.contains("<polyline") else{return false}
                let restored=try Exporter.restore(package,repo:target)
                guard restored.documentaryPhotos==h.documentaryPhotos,restored.features.isEmpty,restored.observations.isEmpty,
                      restored.dimensions.isEmpty,try target.read(key)==bytes,try repo.read(key)==bytes else{return false}
                var legacy=try JSONSerialization.jsonObject(with:input) as! [String:Any]
                var photos=legacy["documentaryPhotos"] as! [[String:Any]];photos[0].removeValue(forKey:"annotations");legacy["documentaryPhotos"]=photos
                let decoded=try JSONDecoder().decode(House.self,from:JSONSerialization.data(withJSONObject:legacy))
                guard decoded.documentaryPhotos[0].annotations==nil else{return false}
                for mode in 0..<7 {
                    var bad=h
                    switch mode {
                    case 0:bad.documentaryPhotos[0].annotations![0].points[0].u=1.1
                    case 1:bad.documentaryPhotos[0].annotations![1].points=[points[0],points[0]]
                    case 2:bad.documentaryPhotos[0].annotations![2].points=Array(points.prefix(2))
                    case 3:bad.documentaryPhotos[0].annotations![3].points=[points[0],points[0]]
                    case 4:bad.documentaryPhotos[0].annotations!.append(marks[0])
                    case 5:bad.documentaryPhotos[0].roomID=UUID()
                    default:bad.documentaryPhotos[0].annotations![0].label=String(repeating:"x",count:4097)
                    }
                    do{try bad.validate();return false}catch{}
                }
                return try JSONDecoder().decode(House.self,from:input)==h && repo.read(key)==bytes
            }
            await check("Incremental snapshots deduplicate originals and reject partial or corrupt restore") {
                let folder=repo.root.appendingPathComponent("incremental-test"),restoredRepo=try Repository(root:repo.root.appendingPathComponent("incremental-restore"))
                var h=House.empty("Snapshot test");let key=try repo.put(Data("original bytes".utf8),ext:"jpg");h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id)]
                let first=try IncrementalSnapshots.write(house:h,repo:repo,folder:folder);h.revision+=1;h.notes="Later note";_=try IncrementalSnapshots.write(house:h,repo:repo,folder:folder)
                let base=IncrementalSnapshots.root(folder),assets=try FileManager.default.contentsOfDirectory(at:base.appendingPathComponent("assets"),includingPropertiesForKeys:nil)
                let catalog=try IncrementalSnapshots.catalog(folder:folder),restored=try IncrementalSnapshots.restore(first,repo:restoredRepo,folder:folder)
                guard assets.count==1,catalog.count==2,restored.id != h.id,restored.notes.isEmpty,try restoredRepo.read(key)==Data("original bytes".utf8) else{return false}
                try Data("corrupt".utf8).write(to:assets[0],options:.atomic)
                do{_=try IncrementalSnapshots.restore(first,repo:restoredRepo,folder:folder);return false}catch{return true}
            }
            await check("Snapshot interruption never publishes incomplete revisions and missing arrivals preserve local projects") {
                let source=try Repository(root:folder.appendingPathComponent("snapshot-fault-source")),target=try Repository(root:folder.appendingPathComponent("snapshot-fault-target"))
                var h=House.empty("Snapshot interruption");let existing=House.empty("Existing local project")
                let key=try source.put(Data("immutable original".utf8),ext:"jpg")
                h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id)]
                try source.save(h);try target.save(existing)
                for phase in ["asset-verified","metadata-verified"] {
                    let destination=folder.appendingPathComponent("snapshot-fault-"+phase)
                    do{_=try IncrementalSnapshots.write(house:h,repo:source,folder:destination,checkpoint:{if $0==phase {throw CancellationError()}});return false}catch is CancellationError{}
                    guard try IncrementalSnapshots.catalog(folder:destination).isEmpty,try source.integrity(h)==1 else{return false}
                    let completed=try IncrementalSnapshots.write(house:h,repo:source,folder:destination)
                    guard try IncrementalSnapshots.catalog(folder:destination).count==1 else{return false}
                    let restored=try IncrementalSnapshots.restore(completed,repo:target,folder:destination)
                    guard restored.id != h.id,restored.documentaryPhotos==h.documentaryPhotos else{return false}
                    let remote=IncrementalSnapshots.root(destination).appendingPathComponent("assets").appendingPathComponent(key)
                    try FileManager.default.removeItem(at:remote)
                    do{_=try IncrementalSnapshots.restore(completed,repo:target,folder:destination);return false}catch{}
                    guard try target.all().map({$0.id})==[existing.id],try source.integrity(h)==1 else{return false}
                }
                let blocked=folder.appendingPathComponent("snapshot-folder-is-file")
                try Data("occupied destination".utf8).write(to:blocked)
                do{_=try IncrementalSnapshots.write(house:h,repo:source,folder:blocked);return false}catch{}
                return try source.integrity(h)==1 && target.all().map({$0.id})==[existing.id]
            }
            await check("Snapshot retry after commit preserves one revision and detects conflicting records") {
                let source=try Repository(root:folder.appendingPathComponent("snapshot-retry-source")),destination=folder.appendingPathComponent("snapshot-retry-destination")
                var h=House.empty("Retry after commit");let key=try source.put(Data("retry original".utf8),ext:"jpg")
                h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id)];try source.save(h)
                do{_=try IncrementalSnapshots.write(house:h,repo:source,folder:destination,checkpoint:{if $0=="revision-committed" {throw CancellationError()}});return false}catch is CancellationError{}
                let first=try IncrementalSnapshots.catalog(folder:destination);guard first.count==1 else{return false}
                let retried=try IncrementalSnapshots.write(house:h,repo:source,folder:destination)
                guard retried.id==first[0].id,retried.date==first[0].date,try IncrementalSnapshots.catalog(folder:destination).count==1 else{return false}
                // Content changes remain distinct even if an imported project
                // reused a revision number. A retry cannot silently lose them.
                h.notes="Changed metadata with the same revision number"
                let changed=try IncrementalSnapshots.write(house:h,repo:source,folder:destination)
                guard changed.id != retried.id,try IncrementalSnapshots.catalog(folder:destination).count==2 else{return false}
                let record=IncrementalSnapshots.root(destination).appendingPathComponent("revisions").appendingPathComponent(changed.id.uuidString+".json")
                var conflict=changed;conflict.metadata=retried.metadata
                let bytes=try JSONEncoder().encode(conflict);try bytes.write(to:record,options:.atomic)
                do{_=try IncrementalSnapshots.write(house:h,repo:source,folder:destination);return false}catch{}
                return try Data(contentsOf:record)==bytes && source.integrity(h)==1 && IncrementalSnapshots.catalog(folder:destination).count==2
            }
            await check("Snapshot catalog reports unreadable records while preserving available restores") {
                let destination=folder.appendingPathComponent("snapshot-catalog"),target=try Repository(root:folder.appendingPathComponent("snapshot-catalog-restore"))
                guard try IncrementalSnapshots.inspectCatalog(folder:destination).revisions.isEmpty else{return false}
                let h=House.empty("Catalog recovery"),good=try IncrementalSnapshots.write(house:h,repo:repo,folder:destination)
                let directory=IncrementalSnapshots.root(destination).appendingPathComponent("revisions")
                let truncated=directory.appendingPathComponent(UUID().uuidString+".json"),wrongName=directory.appendingPathComponent(UUID().uuidString+".json")
                try Data("{\"format\":".utf8).write(to:truncated)
                try JSONEncoder().encode(good).write(to:wrongName)
                var unsafe=good;unsafe.id=UUID();unsafe.assets=["../missing.jpg"]
                let unsupported=directory.appendingPathComponent(unsafe.id.uuidString+".json")
                try JSONEncoder().encode(unsafe).write(to:unsupported)
                try Data("unfinished copy".utf8).write(to:directory.appendingPathComponent("ignored.partial"))
                let catalog=try IncrementalSnapshots.inspectCatalog(folder:destination)
                guard catalog.revisions.map({$0.id})==[good.id],catalog.unreadableRecords.count==3,!catalog.message.isEmpty else{return false}
                let restored=try IncrementalSnapshots.restore(catalog.revisions[0],repo:target,folder:destination)
                guard restored.name==h.name+" · restored",try Data(contentsOf:truncated)==Data("{\"format\":".utf8) else{return false}
                for file in [truncated,wrongName,unsupported] {try FileManager.default.removeItem(at:file)}
                let retried=try IncrementalSnapshots.inspectCatalog(folder:destination)
                return retried.unreadableRecords.isEmpty && retried.revisions.map({$0.id})==[good.id]
            }
            await check("Chunked snapshots pack small originals, split large ones and reuse unchanged content") {
                let source=try Repository(root:folder.appendingPathComponent("chunk-source")),target=try Repository(root:folder.appendingPathComponent("chunk-target")),destination=folder.appendingPathComponent("chunk-snapshots")
                var h=House.empty("Chunk boundary workload")
                let large=try source.put(Data(repeating:71,count:ChunkedSnapshots.chunkLimit+12345),ext:"jpg")
                h.documentaryPhotos=[DocumentaryPhoto(image:large,roomID:h.rooms[0].id,stageID:h.stages[0].id)]
                for i in 0..<40 {let key=try source.put(Data(("small-\(i)-"+String(repeating:"x",count:997)).utf8),ext:"jpg");h.documentaryPhotos.append(DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id))}
                let device=UUID(),first=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:device)
                let base=IncrementalSnapshots.root(destination),m=try ChunkedSnapshots.manifest(first,base:base)
                let firstChunks=Set(m.assets.flatMap{$0.slices.map{$0.chunk}})
                guard firstChunks.count==2,m.assets.count==41,m.deviceID==device,m.parentMetadata==nil else{return false}
                let originalAssets=m.assets
                h.revision+=1;h.notes="New original only"
                let newKey=try source.put(Data("one newly imported original".utf8),ext:"jpg")
                h.documentaryPhotos.append(DocumentaryPhoto(image:newKey,roomID:h.rooms[0].id,stageID:h.stages[0].id))
                let second=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:device)
                let next=try ChunkedSnapshots.manifest(second,base:base)
                guard next.parentMetadata==first.metadata,originalAssets.allSatisfy({old in next.assets.contains(old)}),Set(next.assets.flatMap{$0.slices.map{$0.chunk}}).count==3 else{return false}
                let restored=try IncrementalSnapshots.restore(second,repo:target,folder:destination)
                guard restored.id != h.id,restored.documentaryPhotos==h.documentaryPhotos,try target.integrity(restored)==42 else{return false}
                let legacy=try IncrementalSnapshots.write(house:h,repo:source,folder:destination)
                let old=try IncrementalSnapshots.restore(legacy,repo:target,folder:destination)
                let revisions=try IncrementalSnapshots.catalog(folder:destination)
                return old.documentaryPhotos==h.documentaryPhotos && revisions.count==3
            }
            await check("Chunked snapshot commit, retry and partial arrival preserve healthy local projects") {
                let source=try Repository(root:folder.appendingPathComponent("chunk-fault-source")),target=try Repository(root:folder.appendingPathComponent("chunk-fault-target"))
                var h=House.empty("Chunk fault matrix");let key=try source.put(Data("immutable chunk original".utf8),ext:"jpg"),healthy=House.empty("Keep this project")
                h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id)];try source.save(h);try target.save(healthy)
                for phase in ["chunk-verified","metadata-verified","manifest-verified","revision-committed"] {
                    let destination=folder.appendingPathComponent("chunk-fault-"+phase),device=UUID()
                    do{_=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:device,checkpoint:{if $0==phase{throw CancellationError()}});return false}catch is CancellationError{}
                    guard try IncrementalSnapshots.catalog(folder:destination).count==(phase=="revision-committed" ? 1:0) else{return false}
                    let first=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:device),retried=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:UUID())
                    guard first.id==retried.id,first.date==retried.date,try IncrementalSnapshots.catalog(folder:destination).count==1 else{return false}
                    let base=IncrementalSnapshots.root(destination),m=try ChunkedSnapshots.manifest(first,base:base),chunk=base.appendingPathComponent("chunks").appendingPathComponent(m.assets[0].slices[0].chunk)
                    let saved=try Data(contentsOf:chunk);try FileManager.default.removeItem(at:chunk)
                    do{_=try IncrementalSnapshots.restore(first,repo:target,folder:destination);return false}catch{}
                    try Data("corrupt chunk".utf8).write(to:chunk)
                    do{_=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:device);return false}catch{}
                    try saved.write(to:chunk,options:.atomic)
                    let restored=try IncrementalSnapshots.restore(first,repo:target,folder:destination)
                    guard restored.documentaryPhotos==h.documentaryPhotos,try target.all().map({$0.id})==[healthy.id],try source.integrity(h)==1 else{return false}
                }
                return true
            }
            await check("Chunked snapshot range and manifest contradictions are refused without activation") {
                let source=try Repository(root:folder.appendingPathComponent("chunk-range-source")),target=try Repository(root:folder.appendingPathComponent("chunk-range-target")),destination=folder.appendingPathComponent("chunk-range-snapshots")
                var h=House.empty("Range refusal");let key=try source.put(Data("bounded immutable range".utf8),ext:"jpg"),healthy=House.empty("Healthy")
                h.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id)];try target.save(healthy)
                let revision=try ChunkedSnapshots.write(house:h,repo:source,folder:destination,deviceID:UUID()),base=IncrementalSnapshots.root(destination),m=try ChunkedSnapshots.manifest(revision,base:base)
                for fault in 0..<6 {
                    var changed=m,record=revision
                    switch fault {
                    case 0:changed.assets[0].slices[0].offset=Int.max
                    case 1:changed.assets[0].bytes=UInt64.max
                    case 2:changed.assets.append(changed.assets[0])
                    case 3:changed.assets[0].slices[0].chunk="../outside.chunk"
                    case 4:changed.parentMetadata=changed.metadata
                    default:changed.assets[0].slices[0].offset=1
                    }
                    record.chunkManifest=try ChunkedSnapshots.object(ChunkedSnapshots.encode(changed),kind:"manifests",extension:"json",base:base)
                    do{_=try IncrementalSnapshots.restore(record,repo:target,folder:destination);return false}catch{}
                }
                var future=revision;future.version=99
                do{_=try IncrementalSnapshots.restore(future,repo:target,folder:destination);return false}catch{}
                return try target.all().map({$0.id})==[healthy.id]
            }
            await check("Concurrent snapshot edits retain independent ancestry and restorable branches") {
                let a=try Repository(root:folder.appendingPathComponent("branch-a")),b=try Repository(root:folder.appendingPathComponent("branch-b")),target=try Repository(root:folder.appendingPathComponent("branch-restore"))
                let destination=folder.appendingPathComponent("branch-snapshots"),deviceA=UUID(),deviceB=UUID()
                var original=House.empty("Independent branch history")
                let bytes=Data("Shared immutable source".utf8),key=try a.put(bytes,ext:"jpg")
                guard try b.put(bytes,ext:"jpg")==key else{return false}
                original.documentaryPhotos=[DocumentaryPhoto(image:key,roomID:original.rooms[0].id,stageID:original.stages[0].id)]
                let root=try ChunkedSnapshots.write(house:original,repo:a,folder:destination,deviceID:deviceA)
                // Both devices read back the same starting revision before
                // independently editing it. The later writer cannot adopt A's
                // newly arrived metadata as B's parent just because it is newer.
                guard try ChunkedSnapshots.write(house:original,repo:b,folder:destination,deviceID:deviceB).id==root.id else{return false}
                var left=original,right=original;left.revision=1;right.revision=1;left.notes="Device A edit";right.notes="Device B edit"
                let first=try ChunkedSnapshots.write(house:left,repo:a,folder:destination,deviceID:deviceA)
                let second=try ChunkedSnapshots.write(house:right,repo:b,folder:destination,deviceID:deviceB)
                let base=IncrementalSnapshots.root(destination)
                guard try ChunkedSnapshots.manifest(first,base:base).parentMetadata==root.metadata,
                    try ChunkedSnapshots.manifest(second,base:base).parentMetadata==root.metadata else{return false}
                var catalog=try IncrementalSnapshots.inspectCatalog(folder:destination)
                var branches=try ChunkedSnapshots.branches(catalog,folder:destination)
                guard catalog.revisions.count==3,branches.branchedProjects==1,!branches.incomplete,branches.heads==Set([first.id,second.id]) else{return false}
                let restoredA=try IncrementalSnapshots.restore(first,repo:target,folder:destination),restoredB=try IncrementalSnapshots.restore(second,repo:target,folder:destination)
                guard restoredA.id != restoredB.id,restoredA.notes==left.notes,restoredB.notes==right.notes,try target.integrity(restoredA)==1,try target.integrity(restoredB)==1 else{return false}
                // A subsequent edit advances only A's tip, preserving B's tip.
                left.revision=2;left.notes="Device A later edit"
                let later=try ChunkedSnapshots.write(house:left,repo:a,folder:destination,deviceID:deviceA)
                guard try ChunkedSnapshots.manifest(later,base:base).parentMetadata==first.metadata else{return false}
                catalog=try IncrementalSnapshots.inspectCatalog(folder:destination);branches=try ChunkedSnapshots.branches(catalog,folder:destination)
                guard branches.heads==Set([later.id,second.id]),branches.branchedProjects==1 else{return false}
                // Missing manifest visibility cannot be reported as a merged
                // or complete history. A healthy older branch remains readable.
                let manifestURL=base.appendingPathComponent("manifests").appendingPathComponent(later.chunkManifest!)
                let manifestBytes=try Data(contentsOf:manifestURL);try FileManager.default.removeItem(at:manifestURL)
                guard try ChunkedSnapshots.branches(catalog,folder:destination).incomplete else{return false}
                try manifestBytes.write(to:manifestURL,options:.atomic)
                // Corrupt local ancestry is preserved, with no guessed parent
                // and no new remote revision committed.
                let lineage=ChunkedSnapshots.lineageURL(projectID:left.id,deviceID:deviceA,repo:a,folder:destination),savedLineage=try Data(contentsOf:lineage)
                try Data("incomplete local history".utf8).write(to:lineage,options:.atomic);left.revision=3
                do{_=try ChunkedSnapshots.write(house:left,repo:a,folder:destination,deviceID:deviceA);return false}catch{}
                guard try IncrementalSnapshots.catalog(folder:destination).count==4,try Data(contentsOf:lineage)==Data("incomplete local history".utf8) else{return false}
                try savedLineage.write(to:lineage,options:.atomic)
                return try a.integrity(original)==1 && b.integrity(original)==1 && !ChunkedSnapshots.branches(catalog,folder:destination).incomplete
            }
            await check("Snapshot transfer status never promotes a local readback or a partial upload") {
                let evidence=mainRepo.root.appendingPathComponent("incremental-v2"),device=UUID()
                var h=House.empty("Independent chunk handoff")
                for text in ["first independent original","second independent original"] {let key=try repo.put(Data(text.utf8),ext:"jpg");h.documentaryPhotos.append(DocumentaryPhoto(image:key,roomID:h.rooms[0].id,stageID:h.stages[0].id))}
                let revision=try ChunkedSnapshots.write(house:h,repo:repo,folder:evidence,deviceID:device),status=try ChunkedSnapshots.transfers(revision,folder:evidence)
                guard status.total==4,status.uploaded==0,status.unknown==4 else{return false}
                let waiting=ChunkedSnapshots.TransferSummary(total:4,uploaded:3,waiting:1)
                let complete=ChunkedSnapshots.TransferSummary(total:4,uploaded:4)
                let conflict=ChunkedSnapshots.TransferSummary(total:4,uploaded:3,conflicts:1)
                return !waiting.message.contains("reports all") && complete.message.contains("restore on another") && conflict.message.contains("needs attention")
            }
            await check("Observed coverage requires confident depth, separated good views and bounded sampled area") {
                var h=House.empty("Coverage confidence"),o:[Observation]=[]
                let room=h.rooms[0].id,stage=h.stages[0].id
                let segment=Segment(roomID:room,stageID:stage);h.segments=[segment]
                let image=try repo.put(Data("coverage metadata only".utf8),ext:"jpg")
                func plane(_ value:Float)throws->String {var data=Data();for _ in 0..<256 {data.float(value)};return try repo.put(data,ext:"depth32")}
                let depth=try plane(2),high=try repo.put(Data(repeating:2,count:256),ext:"confidence8")
                let low=try repo.put(Data(repeating:0,count:256),ext:"confidence8")
                for (i,x) in [-0.4,0.0,0.4].enumerated() {
                    var camera=Rigid().values;camera[3]=x
                    o.append(Observation(roomID:room,stageID:stage,segmentID:segment.id,timestamp:Double(i),image:image,depth:depth,confidence:high,depthWidth:16,depthHeight:16,width:640,height:480,camera:camera,intrinsics:[400,0,320,0,400,240,0,0,1],tracking:"synthetic",light:800,sharpness:0.1))
                }
                h.observations=o
                h.features=[Feature(name:"Captured wall",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,mesh:Mesh(vertices:[V3(-0.15,2,-0.1),V3(0.15,2,-0.1),V3(0,2,0.2)],triangles:[0,1,2]),segmentID:segment.id,geometrySource:.capturedMesh)]
                let good=try CoverageAnalyzer.analyze(house:h,segment:segment,repo:repo)
                guard good.sampledPatches==1,good.supportedPatches==1,abs(good.observedArea-0.045)<1e-9 else{return false}
                let foreground=try plane(1.95),absent=try plane(0)
                for fault in 0..<10 {
                    h.observations=o
                    for i in h.observations.indices {
                        switch fault {
                        case 0:h.observations[i].confidence=low
                        case 1:h.observations[i].confidence=nil
                        case 2:h.observations[i].depth=foreground
                        case 3:h.observations[i].depth=absent
                        case 4:h.observations[i].depth=nil
                        case 5:h.observations[i].camera[3]=0
                        case 6:h.observations[i].sharpness=0
                        case 7:h.observations[i].light=50
                        case 8:h.observations[i].confidence=try repo.put(Data([2]),ext:"confidence8")
                        default:h.observations[i].confidence=try repo.put(Data(repeating:255,count:256),ext:"confidence8")
                        }
                    }
                    guard try CoverageAnalyzer.analyze(house:h,segment:segment,repo:repo).supportedPatches==0 else{return false}
                }
                h.observations=Array(o.prefix(2))
                guard try CoverageAnalyzer.analyze(house:h,segment:segment,repo:repo).supportedPatches==0 else{return false}
                h.observations=o;h.observations[0].confidence=try repo.put(Data(repeating:2,count:257),ext:"confidence8")
                do{_=try CoverageAnalyzer.analyze(house:h,segment:segment,repo:repo);return false}catch{}
                guard try repo.read(high)==Data(repeating:2,count:256) else{return false}
                h.observations=o;h.features[0].mesh.triangles=(0..<5000).flatMap{_ in [Int32(0),1,2]}
                let sampled=try CoverageAnalyzer.analyze(house:h,segment:segment,repo:repo)
                return sampled.sampledPatches==2500 && sampled.supportedPatches==2500 && abs(sampled.observedArea-112.5)<1e-7
            }
            await check("Boundary coverage counts unseen and occluded nominal patches") {
                var h=try SimulatedCapture.make(repo:repo);let segment=h.segments[0]
                // Narrow-FOV planar depth diagnostic; RGB pixels are not consumed by coverage.
                for i in h.observations.indices {h.observations[i].intrinsics[0]*=2;h.observations[i].intrinsics[4]*=2;h.observations[i].sharpness=0.1}
                let fingerprint=try VisualMapping.fingerprint(house:h,segment:segment)
                let b=RevealBoundary(name:"Wall",segmentID:segment.id,origin:V3(-0.2,1.8,1.6),horizontal:V3(1,0,0),vertical:V3(0,0,-1),width:0.4,height:0.4,depth:0.2,finishOffset:0.01,sourceFingerprint:fingerprint)
                let supported=try BoundaryCoverage.analyze(house:h,boundary:b,repo:repo)
                var behind=b;behind.depth=0.5
                let blocked=try BoundaryCoverage.analyze(house:h,boundary:behind,repo:repo)
                var unseen=b;unseen.origin.x=100
                let unknown=try BoundaryCoverage.analyze(house:h,boundary:unseen,repo:repo)
                guard supported.supported>0 && blocked.supported==0 && blocked.states.contains(3) && unknown.states.allSatisfy({$0==0}) else{return false}
                for fault in 0..<2 {
                    for i in h.observations.indices {
                        let count=h.observations[i].depthWidth*h.observations[i].depthHeight
                        if fault==0 {h.observations[i].confidence=nil}
                        else {h.observations[i].confidence=try repo.put(Data(repeating:255,count:count),ext:"confidence8")}
                    }
                    var unverified=b;unverified.sourceFingerprint=try VisualMapping.fingerprint(house:h,segment:segment)
                    guard try BoundaryCoverage.analyze(house:h,boundary:unverified,repo:repo).supported==0 else{return false}
                }
                return true
            }
            await check("Coverage advice distinguishes lighting blur sampling baseline depth and obstruction without false completeness") {
                var baseline=try SimulatedCapture.make(repo:repo)
                for i in baseline.observations.indices {baseline.observations[i].intrinsics[0]*=2;baseline.observations[i].intrinsics[4]*=2;baseline.observations[i].sharpness=0.1}
                let segment=baseline.segments[0]
                func analyze(_ h:House,depth:Double=0.2,x:Double = -0.2)throws->BoundaryCoverageReport {
                    let b=RevealBoundary(name:"Confirmed analytic plane",segmentID:segment.id,origin:V3(x,1.8,1.6),horizontal:V3(1,0,0),vertical:V3(0,0,-1),width:0.4,height:0.4,depth:depth,finishOffset:0.01,sourceFingerprint:try VisualMapping.fingerprint(house:h,segment:h.segments[0]))
                    return try BoundaryCoverage.analyze(house:h,boundary:b,repo:repo)
                }
                let good=try analyze(baseline)
                guard good.supported==good.cells.count,good.cells.allSatisfy({$0.advice == .review}) else{return false}
                let expected:[BoundaryCoverageAdvice]=[.illuminate,.steady,.closer,.translate,.depth,.depth,.aroundObstruction,.visit]
                for fault in expected.indices {
                    var h=baseline
                    for i in h.observations.indices {
                        switch fault {
                        case 0:h.observations[i].light=20
                        case 1:h.observations[i].sharpness=0
                        case 2:h.observations[i].intrinsics[0]/=2;h.observations[i].intrinsics[4]/=2
                        case 3:h.observations[i].camera[3]=0
                        case 4:h.observations[i].depth=nil
                        case 5:h.observations[i].confidence=try repo.put(Data(repeating:0,count:192*144),ext:"confidence8")
                        default:break
                        }
                    }
                    let result=try analyze(h,depth:fault==6 ? 0.5:0.2,x:fault==7 ? 100 : -0.2)
                    guard result.supported==0,result.cells.allSatisfy({$0.advice==expected[fault]}) else{throw HouseError.message("Coverage advice fixture failed in condition \(fault).")}
                    if fault==4 {guard result.cameraCount==0,result.consideredCameraCount==9 else{return false}}
                }
                // Restoring good observations resolves the actionable states;
                // the test reconfirms the analytic plane for every input set.
                return try analyze(baseline).supported==good.cells.count
            }
            await check("Supported coverage retains independent obstruction missing-depth and quality counters") {
                var h=try SimulatedCapture.make(repo:repo);let segment=h.segments[0]
                for i in h.observations.indices {h.observations[i].intrinsics[0]*=2;h.observations[i].intrinsics[4]*=2;h.observations[i].sharpness=0.1}
                func plane(_ depth:Float)throws->String {var bytes=Data();for _ in 0..<(192*144){bytes.float(depth)};return try repo.put(bytes,ext:"depth32")}
                h.observations[1].light=20;h.observations[2].sharpness=0
                h.observations[3].depth=try plane(1);h.observations[5].depth=nil;h.observations[5].light=20;h.observations[5].sharpness=0
                h.observations[6].confidence=try repo.put(Data(repeating:0,count:192*144),ext:"confidence8")
                h.observations[7].depth=try plane(3)
                let b=RevealBoundary(name:"Mixed analytic support",segmentID:segment.id,origin:V3(-0.2,1.8,1.6),horizontal:V3(1,0,0),vertical:V3(0,0,-1),width:0.4,height:0.4,depth:0.2,finishOffset:0.01,sourceFingerprint:try VisualMapping.fingerprint(house:h,segment:segment))
                let result=try BoundaryCoverage.analyze(house:h,boundary:b,repo:repo)
                guard result.supported==result.cells.count,result.cameraCount==8,result.consideredCameraCount==9 else{return false}
                guard result.cells.allSatisfy({$0.projectedViews==9 && $0.matchingDepthViews==5 && $0.usefulViews==3 && $0.separatedViews==3 && $0.angularBaseline && $0.occludedViews==1 && $0.unavailableDepthViews==1 && $0.uncertainDepthViews==1 && $0.unmatchedDepthViews==1 && $0.darkViews==2 && $0.blurredViews==2}) else{return false}
                let report:[String:Any]=["passed":true,"analyticOnly":true,"oracleIsolatedQualification":false,"physicalQualification":false,"patches":result.cells.count,"projectedViewsPerPatch":9,"compatibleDepthCameras":result.cameraCount,"supportedPatches":result.supported,"usefulViewsPerPatch":3,"obstructedViewsPerPatch":1,"unavailableDepthViewsPerPatch":1,"uncertainDepthViewsPerPatch":1,"unmatchedDepthViewsPerPatch":1,"darkViewsPerPatch":2,"blurredViewsPerPatch":2,"semanticReviewQualified":false,"sourceRecordsPublished":false]
                try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:mainRepo.root.appendingPathComponent("native-coverage-guidance.json"))
                return true
            }
            await check("Disconnected photograph is excluded without inventing camera corrections") {
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                var capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                capture.observations[0].image=try repo.put(Data(contentsOf:resources.appendingPathComponent("vision-query-3.jpg")),ext:"jpg")
                let solution=try PoseGraph.build(house:capture,segment:capture.segments[0],repo:repo)
                guard solution.cameras[capture.observations[0].id.uuidString]==nil,(solution.excludedFrameCount ?? 0)>=1,solution.cameras.count>=3 else{return false}
                capture.segments[0].poseSolution=solution
                capture=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(capture))
                guard capture.segments[0].poseSolution==solution else{return false}
                return PoseGraph.selected(capture.observations,segment:capture.segments[0],house:capture)?.count==solution.cameras.count
            }
            await check("Recorded path follows stair height without jumping to another floor") {
                let edge=NavigationGeometry.PathEdge(a:V3(0,0,1.6),b:V3(1,0,2.1))
                guard let point=NavigationGeometry.followedHeight(from:V3(0,0,1.6),to:V3(0.1,0,1.6),paths:[edge]) else{return false}
                let upper=NavigationGeometry.PathEdge(a:V3(0,0,4.6),b:V3(1,0,4.6))
                return abs(point.z-1.65)<1e-9 && NavigationGeometry.followedHeight(from:V3(0,0,1.6),to:V3(0.1,0,1.6),paths:[upper])==nil
            }
            await check("Canonical AR basis"){V3(ar:SIMD3(1,2,3))==V3(1,-3,2)}
            await check("Identity rigid transform"){Rigid().valid && Rigid().apply(V3(2,3,4))==V3(2,3,4)}
            await check("Reject scale in rigid transform"){var t=Rigid();t.values[0]=2;return !t.valid}
            await check("Reject reflected transform"){var t=Rigid();t.values[0] = -1;return !t.valid}
            await check("Reference fit and held-out point"){let a=[V3(),V3(1,0,0),V3(0,1,0),V3(1,1,2)],b=a.map{V3(-$0.y+3,$0.x+4,$0.z+2)};guard let(t,e)=Rigid.register(source:Array(a.prefix(3)),target:Array(b.prefix(3))) else{return false};return e<1e-10 && (t.apply(a[3])-b[3]).length<1e-10}
            await check("Reject collinear controls"){Rigid.register(source:[V3(),V3(1),V3(2)],target:[V3(),V3(1),V3(2)])==nil}
            mark("Fifty-thousand photograph metadata search")
            do {results.append(try evidenceSearchReport())}
            catch {results.append(["test":"Fifty-thousand photograph metadata search","passed":false,"error":error.localizedDescription])}
            await check("Drawing overlays and dependent annotations follow exact sheet revisions") {
                var h=House.empty("Drawing provenance")
                let controls=[V3(),V3(1,0,0),V3(0,1,0),V3(1,1,0)]
                var drawing=Drawing(name:"Plan",asset:String(repeating:"a",count:64)+".pdf",metresPerPoint:0.01,roomID:h.rooms[0].id)
                drawing.alignment=DrawingAlignment(page:0,metresPerPoint:0.01,sheetPoints:controls,housePoints:controls,transform:Rigid(),fitMaximum:0,checkMaximum:0,sourceRevision:1)
                var overlay=Feature(name:"Sheet overlay",trade:.unknown,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.planned,mesh:Mesh(vertices:controls,triangles:[0,1,2]))
                overlay.sourceDrawingID=drawing.id;overlay.sourceDrawingFingerprint=try DrawingEvidence.fingerprint(drawing)
                h.drawings=[drawing];h.features=[overlay]
                var annotation=Feature(name:"Design annotation",trade:.electrical,roomID:overlay.roomID,stageID:overlay.stageID,kind:.planned,mesh:Mesh(vertices:[V3()],triangles:[]))
                annotation.annotationSources=DerivedEvidence.dependencies([overlay.id],house:h);h.features.append(annotation)
                let dimension=Dimension(name:"Design distance",a:V3(),b:V3(1,0,0),roomID:overlay.roomID,source:"Design sheet",sourceRevision:h.revision,sourceGeometry:annotation.annotationSources)
                guard DerivedEvidence.currentIDs(h)==Set([overlay.id,annotation.id]),DerivedEvidence.measurementIsCurrent(dimension,house:h) else{return false}
                for change in 0..<7 {
                    var altered=h
                    switch change {
                    case 0:altered.drawings[0].asset=String(repeating:"b",count:64)+".pdf"
                    case 1:altered.drawings[0].page=1
                    case 2:altered.drawings[0].metresPerPoint=0.02
                    case 3:altered.drawings[0].alignment!.transform.values[3]=0.1
                    case 4:altered.drawings[0].roomID=UUID()
                    case 5:altered.drawings=[]
                    default:altered.features[0].sourceDrawingFingerprint=nil
                    }
                    let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(altered))
                    guard DerivedEvidence.currentIDs(restored).isEmpty,!DerivedEvidence.measurementIsCurrent(dimension,house:restored),restored.features[0].mesh==overlay.mesh else{return false}
                }
                h.drawings[0].name="Renamed plan";h.drawings[0].notes="Reviewed drawing";h.revision += 1
                return DerivedEvidence.currentIDs(h)==Set([overlay.id,annotation.id])
            }
            await check("Checked registration rejects distorted fit despite matching held-out point"){
                let a=[V3(),V3(1,0,0),V3(0,1,0),V3(1,1,0)]
                var b=a;b[1]=V3(2,0,0)
                do{_=try CheckedRegistration.fit(source:a,target:b);return false}catch{return true}
            }
            await check("Drawing controls fit translated vertical plane and reject malformed coordinates"){
                let a=[V3(),V3(2,0,0),V3(0,3,0),V3(2,3,0)],b=a.map{V3($0.x+4,6,$0.y+1)}
                let(t,f,c)=try CheckedRegistration.fit(source:a,target:b)
                guard f<1e-10,c<1e-10,(t.apply(V3(1,2,0))-V3(5,6,3)).length<1e-10 else{return false}
                do{_=try CheckedRegistration.coordinates("1,garbage,2,3");return false}catch{return true}
            }
            await check("Rotated cropped PDF sheets retain unrotated alignment pixels and original rotation") {
                let data=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:240,height:140)).pdfData{context in
                    context.beginPage();UIColor.white.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:240,height:140))
                    UIColor.red.setFill();context.cgContext.fill(CGRect(x:30,y:20,width:60,height:30))
                    UIColor.blue.setFill();context.cgContext.fill(CGRect(x:140,y:70,width:50,height:40))
                }
                guard let page=PDFDocument(data:data)?.page(at:0) else{return false}
                page.setBounds(CGRect(x:20,y:10,width:200,height:120),for:.cropBox)
                let baseline=try DrawingTexture.normalizedThumbnail(page,maximumDimension:320)
                guard let expected=baseline.pngData(),let cg=baseline.cgImage,CaptureController.sharpness(cg)>0.002 else{throw HouseError.message("Drawing baseline was empty or could not encode.")}
                try expected.write(to:mainRepo.root.appendingPathComponent("drawing-baseline.png"))
                for angle in [90,180,270] {
                    page.rotation=angle
                    let image=try DrawingTexture.normalizedThumbnail(page,maximumDimension:320)
                    try image.pngData()?.write(to:mainRepo.root.appendingPathComponent("drawing-rotated-\(angle).png"))
                    guard page.rotation==angle else{throw HouseError.message("Rendering changed the original drawing rotation.")}
                    guard image.pngData()==expected else{throw HouseError.message("Drawing pixels changed at \(angle) degrees; baseline \(cg.width)×\(cg.height), candidate \(image.cgImage!.width)×\(image.cgImage!.height).")}
                    guard image.cgImage!.width<=320,image.cgImage!.height<=320 else{throw HouseError.message("Drawing exceeded the raster budget.")}
                }
                return true
            }
            await check("Measured service sections retain centerlines reject invented sizes and invalidate with their source") {
                var h=House.empty("Envelope geometry");h.isDemo=true
                let session=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);h.segments=[session]
                let line=[V3(0,0,1),V3(1,0,1)]
                let source=Feature(name:"Visible centerline",trade:.plumbing,roomID:session.roomID,stageID:session.stageID,kind:.synthetic,mesh:Mesh(vertices:line,triangles:[]),route:line,segmentID:session.id)
                h.features=[source]
                let round=try ServiceEnvelope.feature(source:source,interval:0,section:.round,width:0.05,height:nil,widthAxis:nil,tolerance:0.001,evidence:"Synthetic outer diameter measurement",house:h)
                let rectangle=try ServiceEnvelope.feature(source:source,interval:0,section:.rectangular,width:0.2,height:0.1,widthAxis:V3(0,1,0),tolerance:nil,evidence:"Synthetic width and height measurement",house:h)
                guard round.mesh.vertices.count==130,round.mesh.triangles.count==768,rectangle.mesh.vertices.count==10,rectangle.mesh.triangles.count==48,round.route==line,round.sourceIDs==source.sourceIDs else{return false}
                for vertex in round.mesh.vertices.prefix(128) {guard abs(hypot(vertex.y,vertex.z-1)-0.025)<1e-12 else{return false}}
                guard rectangle.mesh.vertices.map({$0.y}).max()==0.1,abs((rectangle.mesh.vertices.map{$0.z}.max() ?? 0)-1.05)<1e-12 else{return false}
                h.features += [round,rectangle];try h.validate()
                guard h.features[0]==source,DerivedEvidence.currentIDs(h).count==3 else{return false}
                var changed=h;changed.features[0].revision += 1
                guard DerivedEvidence.currentIDs(changed)==Set([source.id]) else{return false}
                changed=h;var moved=Rigid();moved.values[3]=1;changed.segments[0].registration=moved
                guard DerivedEvidence.currentIDs(changed)==Set([source.id]) else{return false}
                changed=h;changed.features[1].mesh.vertices[0].y += 0.01
                do{try changed.validate();return false}catch{}
                for width in [0,-1,Double.nan,4.1] {
                    do{_=try ServiceEnvelope.feature(source:source,interval:0,section:.round,width:width,height:nil,widthAxis:nil,tolerance:nil,evidence:"Recorded",house:h);return false}catch{}
                }
                do{_=try ServiceEnvelope.feature(source:source,interval:0,section:.rectangular,width:0.2,height:0.1,widthAxis:V3(1,0,0),tolerance:nil,evidence:"Recorded",house:h);return false}catch{}
                do{_=try ServiceEnvelope.feature(source:source,interval:0,section:.round,width:0.05,height:nil,widthAxis:nil,tolerance:nil,evidence:" ",house:h);return false}catch{}
                return true
            }
            await check("Measured envelope metadata geometry and source links survive archive GLB and CSV handoff") {
                var h=House.empty("Envelope interchange");h.isDemo=true
                let line=[V3(0,0,1),V3(1,0,1)]
                let source=Feature(name:"Visible centerline",trade:.plumbing,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.synthetic,mesh:Mesh(vertices:line,triangles:[]),route:line)
                h.features=[source]
                let round=try ServiceEnvelope.feature(source:source,interval:0,section:.round,width:0.05,height:nil,widthAxis:nil,tolerance:0.001,evidence:"=literal synthetic dimension evidence",house:h)
                let rectangle=try ServiceEnvelope.feature(source:source,interval:0,section:.rectangular,width:0.2,height:0.1,widthAxis:V3(0,1,0),tolerance:nil,evidence:"Synthetic duct section",house:h)
                h.features += [round,rectangle];try repo.save(h)
                let archive=try Exporter.archive(h,repo:repo),target=try Repository(root:folder.appendingPathComponent("envelope-restore")),restored=try Exporter.restore(archive,repo:target)
                guard restored.features==h.features,restored.rooms==h.rooms else{return false}
                try Data(contentsOf:archive).write(to:mainRepo.root.appendingPathComponent("service-envelopes.hxray"))
                try Data(contentsOf:Exporter.glb(h,options:SceneOptions())).write(to:mainRepo.root.appendingPathComponent("service-envelopes.glb"))
                try Data(contentsOf:Exporter.semanticCSV(h)).write(to:mainRepo.root.appendingPathComponent("service-envelopes.csv"))
                return true
            }
            await check("Drawing marks preserve suggestion provenance and refuse crossed boundaries or stale edits") {
                let raw=DrawingMarkTestFixture.pdf(),key=try repo.put(raw,ext:"pdf")
                var drawing=Drawing(name:"Plan.pdf",asset:key)
                let points=[UV(u:0.1,v:0.2),UV(u:0.5,v:0.4)]
                var mark=DrawingMark(sourceAsset:key,page:0,kind:.roomName,points:points,label:"Detected label",method:.visionText,originalPoints:points,originalLabel:"Detected label",profileHash:DrawingMark.profileHash,runtime:"Synthetic contract",rawScore:0.8)
                mark.label="Owner correction";mark.reviewed=true;drawing.marks=[mark]
                var source=House.empty("Drawing edits");source.drawings=[drawing]
                try source.validate()
                var current=source;current.drawings[0].notes="A concurrent source note"
                let saved=try DrawingMarkEdits.saving([mark],source:drawing,to:current)
                guard saved.drawings[0].notes==current.drawings[0].notes,saved.drawings[0].marks==[mark],saved.features==source.features,saved.rooms==source.rooms else{return false}
                for fault in 0..<5 {
                    var bad=mark
                    switch fault {
                    case 0:bad.page = -1
                    case 1:bad.profileHash=String(repeating:"0",count:64)
                    case 2:bad.rawScore = .infinity
                    case 3:bad.originalPoints=nil
                    default:bad.label=String(repeating:"é",count:2049)
                    }
                    guard !bad.valid else{return false}
                }
                let crossed=DrawingMark(sourceAsset:key,page:0,kind:.boundary,points:[UV(u:0,v:0),UV(u:1,v:1),UV(u:0,v:1),UV(u:0.8,v:0)],label:"Crossed")
                guard !crossed.valid else{return false}
                current.drawings[0].marks?[0].label="Another edit"
                do{_=try DrawingMarkEdits.saving([],source:drawing,to:current);return false}catch{}
                current=source;current.drawings[0].asset=try repo.put(Data("New source".utf8),ext:"pdf")
                guard !mark.current(for:current.drawings[0]),current.assets.contains(key) else{return false}
                do{_=try DrawingMarkEdits.saving([],source:drawing,to:current);return false}catch{}
                return true
            }
            await check("Native drawing OCR and rectangle proposals remain unreviewed and survive archive restore") {
                let raw=DrawingMarkTestFixture.pdf(),key=try repo.put(raw,ext:"pdf")
                guard let page=PDFDocument(data:raw)?.page(at:0),let image=try DrawingTexture.normalizedThumbnail(page).cgImage else{return false}
                let proposals=try DrawingSuggestions.detect(image,sourceAsset:key,page:0)
                let names=proposals.filter{$0.kind == .roomName},boundaries=proposals.filter{$0.kind == .boundary}
                guard names.contains(where:{$0.label.uppercased().contains("ROOM A")}),names.contains(where:{$0.label.uppercased().contains("ROOM B")}),boundaries.count>=2,
                  proposals.allSatisfy({$0.valid && !$0.reviewed && $0.originalPoints==$0.points && $0.originalLabel==$0.label}) else{throw HouseError.message("Drawing fixture missed required labels or two outlines: \(names.count) text candidates, \(boundaries.count) outlines.")}
                var source=House.empty("Drawing proposal fixture");source.drawings=[Drawing(name:"Plan.pdf",asset:key,marks:proposals)]
                try source.validate();try repo.save(source)
                let archive=try Exporter.archive(source,repo:repo),target=try Repository(root:folder.appendingPathComponent("drawing-mark-restore"))
                let restored=try Exporter.restore(archive,repo:target)
                guard restored.drawings==source.drawings,restored.rooms==source.rooms,restored.features.isEmpty,try target.read(key)==raw else{return false}
                let output=mainRepo.root.appendingPathComponent("drawing-marks.hxray")
                try? FileManager.default.removeItem(at:output);try FileManager.default.copyItem(at:archive,to:output)
                return try target.integrity(restored)==1
            }
            await check("Blank drawing proposals abstain without creating rooms or boundaries") {
                let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
                let image=UIGraphicsImageRenderer(size:CGSize(width:600,height:400),format:format).image{context in
                    UIColor.white.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:600,height:400))
                }
                guard let cg=image.cgImage else{return false}
                return try DrawingSuggestions.detect(cg,sourceAsset:String(repeating:"0",count:64)+".pdf",page:0).isEmpty
            }
            await check("Visual pose converts canonical saved frame into live AR frame"){
                var live=Rigid();live.values[3]=5;live.values[7]=6;live.values[11]=7
                let saved=Rigid(values:[1,0,0,2, 0,0,-1,-4, 0,1,0,3, 0,0,0,1])
                guard let overlay=VisualMapping.overlay(liveCamera:live,savedCanonicalCamera:saved) else{return false}
                return (overlay.apply(V3(2,3,4))-V3(5,6,7)).length<1e-10 && !VisualMapping.agree(live,saved)
            }
            await check("Visual grayscale retains raw top-to-bottom camera rows"){
                var pixels=Data(repeating:0,count:128*128);for y in 0..<64{for x in 0..<128{pixels[y*128+x]=255}}
                let cg=CGImage(width:128,height:128,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:pixels as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
                let encoded=NSMutableData();let destination=CGImageDestinationCreateWithData(encoded as CFMutableData,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(destination,cg,nil);CGImageDestinationFinalize(destination)
                let(gray,w,h)=try VisualMapping.image(encoded as Data)
                return w==128 && h==128 && gray[0]>240 && gray[127*128]<10
            }
            await check("Resized photographs preserve original camera pixel centres"){
                let width=2048,height=1536,centreX=723.25,centreY=511.75
                var pixels=Data(repeating:0,count:width*height)
                for y in 448..<576 {for x in 660..<788 {
                    let dx=Double(x)-centreX,dy=Double(y)-centreY
                    pixels[y*width+x]=UInt8((255*exp(-(dx*dx+dy*dy)/(2*12*12))).rounded())
                }}
                func centroid(_ data:Data,_ w:Int,_ h:Int,_ x:Double,_ y:Double)->(Double,Double) {
                    var weight=0.0,u=0.0,v=0.0
                    for row in max(0,Int(y)-64)..<min(h,Int(y)+65) {for col in max(0,Int(x)-64)..<min(w,Int(x)+65) {
                        let value=Double(data[row*w+col]);weight+=value;u+=Double(col)*value;v+=Double(row)*value
                    }}
                    return (u/weight,v/weight)
                }
                let original=centroid(pixels,width,height,centreX,centreY)
                let cg=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:CGDataProvider(data:pixels as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
                let encoded=NSMutableData();let destination=CGImageDestinationCreateWithData(encoded as CFMutableData,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(destination,cg,nil)
                guard CGImageDestinationFinalize(destination) else{return false}
                let (gray,w,h)=try VisualMapping.image(encoded as Data)
                guard w==1280,h==960 else{return false}
                let measured=centroid(gray,w,h,centreX*Double(w)/Double(width),centreY*Double(h)/Double(height))
                let raw=VisualMapping.Features(xy:[Float(measured.0/Double(w)),Float(measured.1/Double(h))],descriptors:Data(repeating:7,count:32),count:1)
                let restored=try VisualMapping.cameraFeatures(raw,imageWidth:w,imageHeight:h,cameraWidth:width,cameraHeight:height)
                let unchanged=try VisualMapping.cameraFeatures(raw,imageWidth:w,imageHeight:h,cameraWidth:w,cameraHeight:h)
                let errorX=abs(Double(restored.xy[0])*Double(width)-original.0),errorY=abs(Double(restored.xy[1])*Double(height)-original.1)
                let legacyX=abs(Double(raw.xy[0])*Double(width)-original.0),legacyY=abs(Double(raw.xy[1])*Double(height)-original.1)
                guard errorX<0.15,errorY<0.15,legacyX>0.2,legacyY>0.2 else{throw HouseError.message("Thumbnail pixel centres: restored errors \(errorX)/\(errorY), legacy errors \(legacyX)/\(legacyY) pixels.")}
                return restored.descriptors==raw.descriptors && unchanged.xy==raw.xy
            }
            await check("Rendered corner images localize held query viewpoints without pose input"){
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                let capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let map=try VisualMapping.build(house:capture,segment:capture.segments[0],repo:repo)
                let evaluator=try JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("vision-queries.json"))) as! [String:Any]
                var matched=0;var worst=0.0
                for query in evaluator["queries"] as! [[String:Any]] {
                    let features=try VisualMapping.detectImage(Data(contentsOf:resources.appendingPathComponent(query["image"] as! String)),cameraWidth:query["width"] as! Int,cameraHeight:query["height"] as! Int)
                    let result=VisualMapping.query(features,width:query["width"] as! Int,height:query["height"] as! Int,intrinsics:query["intrinsics"] as! [Double],map:map)
                    if query["shouldMatch"] as! Bool {
                        if let result {guard VisualMapping.competingMatch(features,width:query["width"] as! Int,height:query["height"] as! Int,intrinsics:query["intrinsics"] as! [Double],maps:[map]) else{throw HouseError.message("A duplicated visual room was not flagged as a competing match.")};let a=result.transform.values,b=query["expectedCamera"] as! [Double];let error=(V3(a[3],a[7],a[11])-V3(b[3],b[7],b[11])).length;worst=max(worst,error);matched+=1}
                    }else if result != nil {throw HouseError.message("Unrelated texture was incorrectly localized.")}
                }
                guard matched>=2,worst<0.03 else{throw HouseError.message("Image localization: \(matched)/3 held views, worst accepted position error \(worst) m, \(map.points.count) map features.")}
                return true
            }
            await check("Visual maps reject missing, weak, invalid and oversized depth confidence") {
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                let capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let segment=capture.segments[0],original=capture.observations
                let healthy=try VisualMapping.build(house:capture,segment:segment,repo:repo)
                guard healthy.valid else{return false}
                for fault in 0..<7 {
                    var changed=capture
                    for i in changed.observations.indices where changed.observations[i].segmentID==segment.id {
                        let o=changed.observations[i],count=o.depthWidth*o.depthHeight
                        guard let depthKey=o.depth,count>=9 else{continue}
                        switch fault {
                        case 0:changed.observations[i].confidence=nil
                        case 1:changed.observations[i].confidence=try repo.put(Data(repeating:1,count:count),ext:"confidence8")
                        case 2:
                            var confidence=Data(repeating:2,count:count)
                            for pixel in confidence.indices where (pixel/o.depthWidth+pixel%o.depthWidth)%2==1 {confidence[pixel]=1}
                            changed.observations[i].confidence=try repo.put(confidence,ext:"confidence8")
                        case 3:changed.observations[i].confidence=try repo.put(Data(repeating:255,count:count),ext:"confidence8")
                        case 4:changed.observations[i].confidence=try repo.put(Data(repeating:2,count:count-1),ext:"confidence8")
                        case 5:changed.observations[i].confidence=try repo.put(Data(repeating:2,count:count+1),ext:"confidence8")
                        default:
                            var depth=try repo.read(depthKey);depth.append(0)
                            changed.observations[i].depth=try repo.put(depth,ext:"depth32")
                        }
                    }
                    do {_=try VisualMapping.build(house:changed,segment:segment,repo:repo);return false}catch{}
                }
                // A bounded rejection must preserve original bytes and source
                // metadata so the healthy capture remains independently usable.
                for o in original where o.segmentID==segment.id {
                    guard let key=o.confidence,try repo.read(key,limit:o.depthWidth*o.depthHeight).count==o.depthWidth*o.depthHeight else{return false}
                }
                let fingerprint=try VisualMapping.fingerprint(house:capture,segment:segment)
                let assets=try repo.integrity(capture)
                return capture.observations==original && healthy.fingerprint==fingerprint && assets==capture.assets.count
            }
            await check("Derived surfaces are excluded when camera inputs change"){
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                var capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let segment=capture.segments[0]
                let feature=Feature(name:"Derived",trade:.unknown,roomID:segment.roomID,stageID:segment.stageID,kind:.synthetic,mesh:.box(center:V3(),size:V3(1,1,1)),segmentID:segment.id,sourceFingerprint:try VisualMapping.fingerprint(house:capture,segment:segment))
                capture.features=[feature]
                guard DerivedEvidence.currentIDs(capture).contains(feature.id) else{return false}
                capture.observations[0].camera[3]+=0.01
                return !DerivedEvidence.currentIDs(capture).contains(feature.id) && capture.features[0].mesh==feature.mesh
            }
            await check("Image depth graph removes injected camera translation drift"){
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                var capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let original=capture.observations
                for i in capture.observations.indices{capture.observations[i].camera[3]+=Double(i)*0.008}
                let solution=try PoseGraph.build(house:capture,segment:capture.segments[0],repo:repo)
                var worst=0.0
                for observation in original {if let pose=solution.cameras[observation.id.uuidString]{let a=observation.camera;worst=max(worst,(V3(pose[3],pose[7],pose[11])-V3(a[3],a[7],a[11])).length)}}
                guard solution.cameras.count>=3,worst<0.015 else{throw HouseError.message("Injected drift residual \(worst) m across \(solution.cameras.count) views.")}
                capture.segments[0].poseSolution=solution
                guard PoseGraph.selected(capture.observations,segment:capture.segments[0],house:capture) != nil else{return false}
                capture.observations[0].note += " changed input"
                return PoseGraph.selected(capture.observations,segment:capture.segments[0],house:capture)==nil
            }
            await check("Metric feature alignment and 120-camera pose graph closure"){
                var error=0.0;let status=hx_graph_selftest(&error)
                guard status==1 else{throw HouseError.message("Pose graph diagnostic failed at gate \(status).")};return error<0.0001
            }
            await check("Pose consensus excludes isolated source errors but rejects a competing hypothesis") {
                func pose(_ x:Double)->Rigid {var value=Rigid();value.values[3]=x;return value}
                let positions=(0..<7).map{V3(Double($0)*0.2,0,0)}
                let isolated=[0.0,0.003,0.006,0.008,0.5].map(pose)
                guard VisualMapping.consensus(isolated,positions:Array(positions.prefix(5)))==[0,1,2,3] else{return false}
                let competing=[0.0,0.003,0.006,0.008,0.009,0.5,0.503].map(pose)
                guard VisualMapping.consensus(competing,positions:positions).isEmpty else{return false}
                guard VisualMapping.consensus([pose(0),pose(0.01)],positions:[V3(),V3(0.2,0,0)])==[0,1] else{return false}
                return VisualMapping.consensus([pose(0),pose(0.01)],positions:[V3(),V3(0.01,0,0)]).isEmpty
            }
            await check("Repeated-feature camera baseline is invariant to capture order") {
                let point=V3(1,2,3),positions=[V3(),V3(-0.1,0,0),V3(0.1,0,0)]
                let permutations=[[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
                for order in permutations {
                    let sources=order.map{VisualMapping.SourceMatches(id:UUID(),position:positions[$0],matches:[7:point])}
                    let fused=VisualMapping.fusedPoints(sources)
                    guard fused.count==1,fused[0].0==7,(fused[0].1-point).length<1e-12 else{return false}
                }
                guard VisualMapping.hasSourceBaseline([V3(),V3(0.15,0,0)]),
                    !VisualMapping.hasSourceBaseline([V3(),V3(0.14999,0,0)]),
                    !VisualMapping.hasSourceBaseline([V3(),V3(),V3()]),
                    !VisualMapping.hasSourceBaseline([V3(),V3(.nan,0,0)]) else{return false}
                let narrow=[-0.04,0,0.04].map{VisualMapping.SourceMatches(id:UUID(),position:V3($0,0,0),matches:[7:point])}
                guard VisualMapping.fusedPoints(narrow).isEmpty else{return false}
                // A spatially inconsistent landmark cannot supply the baseline.
                let outlier=narrow+[VisualMapping.SourceMatches(id:UUID(),position:V3(0.3,0,0),matches:[7:V3(8,8,8)])]
                return VisualMapping.fusedPoints(outlier).isEmpty
            }
            await check("Native visual feature matching and robust PnP diagnostics"){
                var error=0.0;var falseAccepts:UInt32=0
                let status=hx_vision_selftest(&error,&falseAccepts)
                guard status==1 else{throw HouseError.message("Vision diagnostic failed at gate \(status), max position error \(error), false accepts \(falseAccepts).")}
                return error<=0.02 && falseAccepts==0
            }
            await check("Fixture has three independent rooms and paired stages"){try house.validate();return house.rooms.count==3 && house.stages.count==2 && house.features.allSatisfy{$0.kind == .synthetic}}
            await check("Finish switch preserves stable geometry"){let rough=house.features.filter{SceneBuilder.visible($0,SceneOptions(mode:.rough))},finish=house.features.filter{SceneBuilder.visible($0,SceneOptions(mode:.finished,ceilings:true))};return !rough.isEmpty && !finish.isEmpty && rough.allSatisfy{$0.trade != .finish} && finish.contains{$0.trade == .ceiling}}
            #if DEBUG
            await check("Store migration rollback, verified snapshot and future-version refusal") {
                let root=folder.appendingPathComponent("migration-check"),id=try StoreMigrationDiagnostics.legacyFixture(at:root)
                do{_=try Repository(root:root,migrationCheckpoint:{throw HouseError.message("Injected migration interruption")});return false}catch{}
                let interrupted=try StoreMigrationDiagnostics.state(at:root)
                guard interrupted.0==1,interrupted.1==0 else{return false}
                let snapshots=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("metadata-snapshots"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="sqlite"}
                guard snapshots.count==1 else{return false}
                let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:snapshots[0].appendingPathExtension("json"))) as! [String:Any]
                guard try StreamingArchive.digest(snapshots[0]).sha==(manifest["sha256"] as? String) else{return false}
                var migrated:Repository?=try Repository(root:root)
                guard let restored=try migrated!.all().first(where:{$0.id==id}),try migrated!.integrity(restored)>0 else{return false}
                let complete=try StoreMigrationDiagnostics.state(at:root)
                guard complete.0==Repository.storeVersion,complete.1==1 else{return false}
                migrated=nil
                try StoreMigrationDiagnostics.setVersion(at:root,version:999)
                do{_=try Repository(root:root);return false}catch{}
                return try StoreMigrationDiagnostics.state(at:root).0==999
            }
            #endif
            await check("Project reader upgrades legacy metadata without rewriting it and refuses unknown future schemas") {
                let data=try JSONEncoder().encode(house);var json=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                json["schema"]=1;json.removeValue(forKey:"references")
                let old=try JSONSerialization.data(withJSONObject:json),before=old
                let decoded=try JSONDecoder().decode(House.self,from:old)
                guard decoded.schema==House.currentSchema,decoded.id==house.id,decoded.references.isEmpty,decoded.features==house.features,old==before else{return false}
                let upgraded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(decoded)) as! [String:Any]
                guard upgraded["schema"] as? Int==House.currentSchema else{return false}
                for version in 2..<House.currentSchema {
                    json["schema"]=version
                    let previous=try JSONDecoder().decode(House.self,from:JSONSerialization.data(withJSONObject:json))
                    guard previous.schema==House.currentSchema,previous.features==house.features else{return false}
                }
                for version in [0,House.currentSchema+1,999] {
                    json["schema"]=version
                    do{_=try JSONDecoder().decode(House.self,from:JSONSerialization.data(withJSONObject:json));return false}catch{}
                }
                return true
            }
            await check("Stage composition isolates unfinished and finished session frames"){
                var h=House.empty("Stages");let a=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id),b=Segment(roomID:h.rooms[0].id,stageID:h.stages[1].id);h.segments=[a,b]
                for segment in h.segments{h.features.append(Feature(name:"Surface",trade:.unknown,roomID:segment.roomID,stageID:segment.stageID,kind:.observed,mesh:.box(center:V3(),size:V3(1,1,1)),segmentID:segment.id))}
                return SceneBuilder.features(h,options:SceneOptions(mode:.rough)).map{$0.segmentID}==[a.id] && SceneBuilder.features(h,options:SceneOptions(mode:.finished)).map{$0.segmentID}==[b.id] && SceneBuilder.features(h,options:SceneOptions(mode:.ghost)).count==1
            }
            await check("Observation provenance rejects a different segment stage"){
                var h=House.empty("Provenance");let segment=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);h.segments=[segment]
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                let capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                var o=capture.observations[0];o.roomID=h.rooms[0].id;o.segmentID=segment.id;o.stageID=h.stages[1].id;h.observations=[o]
                do{try h.validate();return false}catch{return true}
            }
            await check("Local store roundtrip"){try repo.save(house);return try repo.all().first(where:{$0.id==house.id})==house}
            await check("Revision recovery"){let original=house;house.revision+=1;house.name="Edited";try repo.save(house);return try repo.previous(house.id)==original}
            await check("Failed candidate does not replace committed evidence"){
                let before=try repo.all();var bad=house;bad.features[0].mesh.triangles=[0,1,Int32.max]
                do{try repo.save(bad);return false}catch{return try repo.all()==before}
            }
            await check("Corrupt project is isolated without hiding healthy projects"){
                let isolated=try Repository(root:folder.appendingPathComponent("corrupt-row"));let good=House.empty("Healthy"),bad=House.empty("Corrupt");try isolated.save(good);try isolated.save(bad)
                var db:OpaquePointer?;guard sqlite3_open(isolated.root.appendingPathComponent("house.sqlite").path,&db)==SQLITE_OK else{return false};defer{sqlite3_close(db)}
                guard sqlite3_exec(db,"UPDATE projects SET json='broken' WHERE id='\(bad.id.uuidString)'",nil,nil,nil)==SQLITE_OK else{return false}
                let remaining=try isolated.all();return remaining.map{$0.id}==[good.id] && isolated.recoveryWarnings.count==1 && FileManager.default.fileExists(atPath:isolated.root.appendingPathComponent("recovery/"+bad.id.uuidString+".json").path)
            }
            await check("Capture journal replays before commit and is idempotent after commit"){
                let store=try Repository(root:folder.appendingPathComponent("journal"));var h=House.empty("Recovery")
                let segment=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);h.segments=[segment];try store.save(h)
                let key=try store.put(Data("original camera bytes".utf8),ext:"jpg")
                let o=Observation(roomID:segment.roomID,stageID:segment.stageID,segmentID:segment.id,timestamp:1,image:key,width:64,height:64,camera:Rigid().values,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1)
                try store.journalCapture(projectID:h.id,observation:o)
                let reopened=AppModel(root:store.root)
                guard reopened.house?.observations==[o],try store.recoverPendingCaptures().isEmpty,let recovered=try store.all().first,recovered.observations==[o] else{return false}
                try store.journalCapture(projectID:h.id,observation:o)
                guard try store.recoverPendingCaptures().isEmpty,try store.all().first?.observations==[o] else{return false}
                let bad=store.captureJournal.appendingPathComponent("broken.json");try Data("broken".utf8).write(to:bad)
                return try !store.recoverPendingCaptures().isEmpty && FileManager.default.fileExists(atPath:bad.path)
            }
            await check("Background capture save targets its original project without switching selection"){
                let app=AppModel(root:folder.appendingPathComponent("project-routing"));let a=House.empty("A"),b=House.empty("B")
                guard app.commit(a),app.commit(b),app.selected==b.id,app.edit(projectID:a.id,{$0.notes="capture belongs to A"}) else{return false}
                return app.selected==b.id && app.houses.first(where:{$0.id==a.id})?.notes=="capture belongs to A" && app.house?.notes==""
            }
            await check("Asset hash identity"){let a=try repo.put(Data("original".utf8),ext:"txt"),b=try repo.put(Data("original".utf8),ext:"txt");let read=try repo.read(a);return a==b && read==Data("original".utf8)}
            await check("Unsafe paths rejected"){do{_=try repo.assetURL("../escape");return false}catch{return true}}
            await check("Invalid mesh indices rejected"){!Mesh(vertices:[V3()],triangles:[0,1,2]).valid}
            await check("Empty routes remain empty without invalid ranges"){Mesh.route([],radius:0.01).vertices.isEmpty && Mesh.route([V3()],radius:0.01).vertices.isEmpty}
            await check("Reject nonfinite mesh"){!Mesh(vertices:[V3(.nan,0,0)],triangles:[]).valid}
            await check("Archive directory corruption cannot masquerade as a complete restore") {
                let source=folder.appendingPathComponent("directory-source.bin"),archive=folder.appendingPathComponent("directory-valid.zip")
                try Data("original".utf8).write(to:source)
                _ = try StreamingArchive.write([.init(name:"entry.bin",url:source)],to:archive)
                let records=try StreamingArchive.index(archive)
                guard let entry=records["entry.bin"],try StreamingArchive.read(entry,from:archive)==Data("original".utf8) else{return false}
                let original=try Data(contentsOf:archive),central=Int(entry.offset+entry.size)
                for index in [central+16,central+42,original.count-12,original.count-34] {
                    var bytes=original;bytes[index] ^= 1
                    let damaged=folder.appendingPathComponent("directory-damaged-\(index).zip");try bytes.write(to:damaged)
                    do {_ = try StreamingArchive.index(damaged);return false}catch{}
                }
                return true
            }
            await check("Archive handoff verifies viewer and photo-index hashes and retains legacy compatibility") {
                let original=try Exporter.archive(house,repo:repo),records=try StreamingArchive.index(original)
                let entries=try records.values.sorted{$0.name<$1.name}.map{StoredZip.Entry(name:$0.name,data:try StreamingArchive.read($0,from:original))}
                let manifestIndex=entries.firstIndex{$0.name=="manifest.json"}!
                var manifest=try JSONSerialization.jsonObject(with:entries[manifestIndex].data) as! [String:Any]
                var hashes=manifest["sha256"] as! [String:String]
                guard hashes["index.html"] != nil,hashes["viewer.html"] != nil else{return false}
                let target=try Repository(root:folder.appendingPathComponent("handoff-restore")),before=try target.all()
                for name in ["viewer.html","index.html"] {
                    var damaged=entries;let i=damaged.firstIndex{$0.name==name}!;damaged[i].data.append(Data("changed sidecar".utf8))
                    let url=folder.appendingPathComponent("changed-"+name+".hxray");try StoredZip.write(damaged,to:url)
                    do{_=try Exporter.restore(url,repo:target);return false}catch{}
                    guard try target.all()==before else{return false}
                }
                hashes.removeValue(forKey:"index.html");manifest["sha256"]=hashes
                var legacy=entries;legacy[manifestIndex].data=try JSONSerialization.data(withJSONObject:manifest)
                let url=folder.appendingPathComponent("legacy-unhashed-index.hxray");try StoredZip.write(legacy,to:url)
                let restored=try Exporter.restore(url,repo:target)
                return restored.features==house.features && restored.id != house.id
            }
            await check("ZIP64 indexing preserves offsets beyond four GiB without reading payload") {
                let source=folder.appendingPathComponent("zip64-source.bin"),small=folder.appendingPathComponent("zip64-small.zip"),large=folder.appendingPathComponent("zip64-sparse.zip")
                try Data("small".utf8).write(to:source)
                _ = try StreamingArchive.write([.init(name:"entry.bin",url:source)],to:small)
                guard let record=try StreamingArchive.index(small)["entry.bin"] else{return false}
                let bytes=try Data(contentsOf:small),oldCentral=Int(record.offset+record.size),size=UInt64(UInt32.max)+124,newCentral=record.offset+size
                var header=Data(bytes.prefix(Int(record.offset))),tail=Data(bytes.dropFirst(oldCentral))
                func replace(_ data:inout Data,_ offset:Int,_ value:UInt64) {var b=Data();b.le(value);data.replaceSubrange(offset..<(offset+8),with:b)}
                let nameCount="entry.bin".utf8.count
                replace(&header,30+nameCount+4,size);replace(&header,30+nameCount+12,size)
                replace(&tail,46+nameCount+4,size);replace(&tail,46+nameCount+12,size)
                let tailCount=tail.count
                replace(&tail,tailCount-98+48,newCentral)
                replace(&tail,tailCount-42+8,newCentral+UInt64(tailCount-98))
                FileManager.default.createFile(atPath:large.path,contents:nil)
                let output=try FileHandle(forWritingTo:large)
                defer{try? output.close();try? FileManager.default.removeItem(at:large)}
                try output.write(contentsOf:header);try output.seek(toOffset:newCentral);try output.write(contentsOf:tail);try output.close()
                guard let indexed=try StreamingArchive.index(large)["entry.bin"],indexed.offset==record.offset,indexed.size==size else{return false}
                do {_ = try StreamingArchive.read(indexed,from:large);return false}catch{}
                return true
            }
            await check("Archive metadata and original roundtrip"){let key=try repo.put(Data("source drawing".utf8),ext:"txt");house.drawings.append(Drawing(name:"source.txt",asset:key));let url=try Exporter.archive(house,repo:repo);try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("test.hxray"));try FileManager.default.copyItem(at:url,to:mainRepo.root.appendingPathComponent("test.hxray"));let fresh=try Repository(root:folder.appendingPathComponent("restore"));let restored=try Exporter.restore(url,repo:fresh);let verified=try fresh.integrity(restored);return restored.id != house.id && restored.features==house.features && restored.assets==house.assets && verified==1}
            await check("Coordinated folder snapshot is independently restorable"){
                let folder=repo.root.appendingPathComponent("snapshots",isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                _=try SnapshotStorage.write(house:house,repo:repo,folder:folder);let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil);guard let archive=files.first(where:{$0.pathExtension=="hxray"}),!files.contains(where:{$0.pathExtension=="partial"}) else{return false}
                let restored=try Exporter.restore(archive,repo:repo);return restored.assets==house.assets && restored.features==house.features
            }
            await check("Corrupt archive rejected"){let url=try Exporter.archive(house,repo:repo);var bytes=try Data(contentsOf:url);bytes[60]^=0xff;let broken=folder.appendingPathComponent("broken.hxray");try bytes.write(to:broken);do{_=try Exporter.restore(broken,repo:repo);return false}catch{return true}}
            await check("GLB framing and length"){let url=try Exporter.glb(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.glb"));return d.uint32(0)==0x46546c67 && d.uint32(4)==2 && Int(d.uint32(8))==d.count}
            await check("Model export admits unique texture bytes and rejects missing, corrupt or oversized selections") {
                let bytes=Data([137,80,78,71,1,2,3]),key=try repo.put(bytes,ext:"png")
                var feature=house.features[0];feature.texture=key;feature.uv=feature.mesh.vertices.map{_ in UV(u:0,v:0)}
                let root=repo.root.appendingPathComponent("assets")
                let assets=try Exporter.exportAssets([feature,feature],textGeometry:false,root:root)
                guard assets.count==1,try Exporter.verifiedTexture(key,assets:assets)==bytes else{return false}
                do{_=try Exporter.exportAssets([feature],textGeometry:false,root:root,budget:1);return false}catch{}
                var labels=feature;labels.texture=nil;labels.uv=nil
                labels.service=ServiceDetails(observedLabel:String(repeating:"\u{1}",count:4096))
                guard labels.service!.valid else{return false}
                do{_=try Exporter.exportAssets([labels],textGeometry:false,root:root,budget:65_536);return false}catch{}
                _=try Exporter.exportAssets([labels],textGeometry:true,root:root,budget:65_536)
                var missing=feature;missing.texture=String(repeating:"0",count:64)+".png"
                do{_=try Exporter.exportAssets([missing],textGeometry:false,root:root);return false}catch{}
                let original=try repo.assetURL(key);try Data([1,2,3]).write(to:original)
                do{_=try Exporter.verifiedTexture(key,assets:assets);return false}catch{}
                try bytes.write(to:original)
                return true
            }
            await check("PLY native parser roundtrip"){let url=try Exporter.meshText(house,options:SceneOptions(),ply:true);let mesh=try PLYReader.read(Data(contentsOf:url));return mesh.valid && mesh.vertices.count==Exporter.canonicalFeatures(house,options:SceneOptions()).reduce(0){$0+$1.mesh.vertices.count}}
            await check("PLY import requires explicit units and axes, preserves the original and never assumes house alignment") {
                let raw=Data("ply\nformat ascii 1.0\nelement vertex 1\nproperty double x\nproperty double y\nproperty double z\nend_header\n1 2 3\n".utf8)
                let key=try repo.put(raw,ext:"ply"),drawing=Drawing(name:"Source.ply",asset:key)
                var original=House.empty("Declared source coordinates");original.drawings=[drawing];try repo.save(original)
                let candidate=PointCloudImport(projectID:original.id,drawing:drawing,mesh:try PLYReader.read(raw)),room=original.rooms[0].id
                let cases:[(ImportedUnit,V3)]=[(.metres,V3(1,2,3)),(.millimetres,V3(0.001,0.002,0.003)),(.centimetres,V3(0.01,0.02,0.03)),(.feet,V3(0.3048,0.6096,0.9144)),(.inches,V3(0.0254,0.0508,0.0762))]
                for (unit,expected) in cases {for upright in ImportedAxis.allCases {
                    let imported=try candidate.applying(unit:unit,upright:upright,roomID:room,to:original)
                    let target=upright == .zUp ? expected:V3(expected.x,-expected.z,expected.y)
                    guard imported.features.count==1,(imported.features[0].mesh.vertices[0]-target).length<1e-12,
                      imported.segments.count==1,imported.segments[0].registration==nil,!imported.segments[0].approved,
                      imported.stages.last?.kind == .documentary,imported.features[0].importedCoordinates==ImportedCoordinateDeclaration(unit:unit,upright:upright),
                      imported.drawings==original.drawings,DerivedEvidence.currentIDs(imported).contains(imported.features[0].id) else{return false}
                }}
                for (unit,axis) in [(Optional<ImportedUnit>.none,Optional(ImportedAxis.zUp)),(Optional(ImportedUnit.metres),Optional<ImportedAxis>.none)] {
                    do{_=try candidate.applying(unit:unit,upright:axis,roomID:room,to:original);return false}catch{}
                }
                var stale=original;stale.drawings[0].notes="Source changed"
                do{_=try candidate.applying(unit:.metres,upright:.zUp,roomID:room,to:stale);return false}catch{}
                let imported=try candidate.applying(unit:.millimetres,upright:.yUp,roomID:room,to:original)
                do{_=try candidate.applying(unit:.millimetres,upright:.yUp,roomID:room,to:imported);return false}catch{}
                let archive=try Exporter.archive(imported,repo:repo),target=try Repository(root:folder.appendingPathComponent("declared-ply-restore"))
                let restored=try Exporter.restore(archive,repo:target)
                var changed=imported;changed.features[0].importedCoordinates!.unit = .metres
                guard !DerivedEvidence.currentIDs(changed).contains(changed.features[0].id) else{return false}
                return try restored.features==imported.features && restored.segments==imported.segments && repo.read(key)==raw && target.integrity(restored)==1
            }
            await check("IFC source dependency preserves a separate design frame and refuses stale publication") {
                guard let path=Bundle.main.url(forResource:"IFC",withExtension:nil)?.appendingPathComponent("test-block.ifc") else{return false}
                let raw=try Data(contentsOf:path),key=try repo.put(raw,ext:"ifc"),drawing=Drawing(name:"Source.ifc",asset:key)
                var original=House.empty("IFC source frame");original.drawings=[drawing]
                let stage=Stage(name:"Imported IFC design",kind:.planned,phase:.other),room=original.rooms[0].id
                original.stages.append(stage)
                let geometry=Feature(name:"Converted design",trade:.structure,roomID:room,stageID:stage.id,kind:.planned,mesh:Mesh.box(center:V3(10,20,30),size:V3(1,2,3)))
                let imported=try IFCSourceEvidence.applying([geometry],source:drawing,stage:stage,roomID:room,to:original)
                guard imported.features.count==1,imported.features[0].mesh==geometry.mesh,imported.features[0].sourceDrawingID==drawing.id,
                  imported.segments.count==1,imported.segments[0].registration==nil,!imported.segments[0].approved,
                  imported.features[0].segmentID==imported.segments[0].id,DerivedEvidence.currentIDs(imported).contains(geometry.id) else{return false}
                for fault in 0..<4 {
                    var changed=original
                    if fault==0{changed.drawings[0].asset=try repo.put(Data("changed IFC source".utf8),ext:"ifc")}
                    if fault==1{changed.stages.removeAll{$0.id==stage.id}}
                    if fault==2{changed.rooms=[]}
                    if fault==3{changed=imported}
                    do{_=try IFCSourceEvidence.applying([geometry],source:drawing,stage:stage,roomID:room,to:changed);return false}catch{}
                }
                var changed=imported;changed.drawings[0].asset=try repo.put(Data("replacement source".utf8),ext:"ifc")
                guard !DerivedEvidence.currentIDs(changed).contains(geometry.id) else{return false}
                let archive=try Exporter.archive(imported,repo:repo),target=try Repository(root:folder.appendingPathComponent("ifc-source-restore"))
                let restored=try Exporter.restore(archive,repo:target)
                return try restored.features==imported.features && restored.segments==imported.segments && restored.drawings==original.drawings && target.read(key)==raw && target.integrity(restored)==1
            }
            await check("Reversible IFC source metadata survives archive GLB CSV and dependency invalidation") {
                let reference=IFCCoordinateReference(sourceSchema:"IFC4",sourceLengthUnit:"MILLI METRE",originMetres:V3(1000000,0,0),mapConversions:[IFCMapReference(expressID:32,values:["Eastings":500000.25,"Northings":4200000.5,"OrthogonalHeight":12,"Scale":0.001],targetCRS:["Name":"EPSG:32632","MapUnit":"METRE"])])
                var source=House.empty("Reversible IFC frame")
                let raw=Data("Synthetic IFC original for metadata roundtrip".utf8),key=try repo.put(raw,ext:"ifc"),drawing=Drawing(name:"Far source.ifc",asset:key)
                let room=source.rooms[0].id,stage=Stage(name:"Imported design",kind:.planned,phase:.other)
                source.drawings=[drawing];source.stages.append(stage)
                let geometry=Feature(name:"Far design",trade:.structure,roomID:room,stageID:stage.id,kind:.planned,mesh:.box(center:V3(0,20,31.5),size:V3(1,2,3)))
                let imported=try IFCSourceEvidence.applying([geometry],source:drawing,stage:stage,roomID:room,coordinates:reference,to:source)
                guard imported.drawings[0].ifcCoordinates==reference,DerivedEvidence.currentIDs(imported).contains(geometry.id),imported.segments[0].registration==nil else{return false}
                var altered=imported;altered.drawings[0].ifcCoordinates?.originMetres.x += 1
                guard !DerivedEvidence.currentIDs(altered).contains(geometry.id) else{return false}
                altered=imported;altered.drawings[0].ifcCoordinates?.mapConversions[0].values["Scale"]=1
                guard !DerivedEvidence.currentIDs(altered).contains(geometry.id) else{return false}
                var bad=reference;bad.originMetres.x=1e10
                do{_=try IFCSourceEvidence.applying([geometry],source:drawing,stage:stage,roomID:room,coordinates:bad,to:source);return false}catch{}
                let archive=try Exporter.archive(imported,repo:repo),target=try Repository(root:folder.appendingPathComponent("ifc-coordinate-restore"))
                let restored=try Exporter.restore(archive,repo:target)
                guard restored.drawings==imported.drawings,restored.features==imported.features,try target.read(key)==raw else{return false}
                var options=SceneOptions();options.stage=stage.id
                let glb=try Data(contentsOf:Exporter.glb(imported,options:options))
                let jsonEnd=20+Int(glb.uint32(12))
                let payload=try JSONSerialization.jsonObject(with:glb.subdata(in:20..<jsonEnd)) as! [String:Any]
                let extras=payload["extras"] as! [String:Any],references=extras["ifcSourceCoordinates"] as! [[String:Any]]
                guard references.count==1,let encoded=references[0]["coordinates"],try JSONDecoder().decode(IFCCoordinateReference.self,from:JSONSerialization.data(withJSONObject:encoded))==reference else{return false}
                let csv=try Data(contentsOf:Exporter.semanticCSV(imported))
                try glb.write(to:mainRepo.root.appendingPathComponent("ifc-source.glb"))
                try csv.write(to:mainRepo.root.appendingPathComponent("ifc-source.csv"))
                try JSONEncoder().encode(imported).write(to:mainRepo.root.appendingPathComponent("ifc-source.json"))
                var registered=imported;registered.segments[0].registration=Rigid(values:[0,-1,0,7,1,0,0,-3,0,0,1,2,0,0,0,1])
                let aligned=try Data(contentsOf:Exporter.glb(registered,options:options))
                try aligned.write(to:mainRepo.root.appendingPathComponent("ifc-registered.glb"))
                return String(decoding:csv,as:UTF8.self).contains("ifcSourceCoordinates")
            }
            await check("PLY preserves fields and rejects malformed records without coordinate shifts") {
                let header="ply\nformat ascii 1.0\nelement vertex 3\nproperty double x\nproperty double y\nproperty double z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n"
                let body="0 0 0\n1 0 0\n0 2 0\n3 0 1 2\n"
                let valid=try PLYReader.read(Data((header+body).replacingOccurrences(of:"\n",with:"\r\n").utf8))
                guard valid.vertices==[V3(),V3(1,0,0),V3(0,2,0)],valid.triangles==[0,1,2] else{return false}
                let invalid=[
                    header+body.replacingOccurrences(of:"0 0 0",with:"bad 0 0 9"),
                    header+body.replacingOccurrences(of:"3 0 1 2",with:"3 bad 0 1 2"),
                    header+body.replacingOccurrences(of:"3 0 1 2",with:"3 0 1 2 1"),
                    header+body.replacingOccurrences(of:"3 0 1 2",with:"3 0 1 99"),
                    header+body.replacingOccurrences(of:"0 0 0",with:"nan 0 0"),
                    header+body+"0 0 0\n",
                    header.replacingOccurrences(of:"element face 1",with:"element face -1")+body,
                    header.replacingOccurrences(of:"property double y",with:"property double x")+body,
                    header.replacingOccurrences(of:"property double y",with:"property list uchar int y")+body,
                    header.replacingOccurrences(of:"element vertex 3",with:"element edge 3")+body,
                    header.replacingOccurrences(of:"format ascii 1.0",with:"comment format ascii 1.0")+body
                ]
                for text in invalid {do{_=try PLYReader.read(Data(text.utf8));return false}catch{}}
                let tabbed=try PLYReader.read(Data((header+body.replacingOccurrences(of:" ",with:"\t")).utf8))
                return tabbed==valid
            }
            await check("PLY and OBJ retain asymmetric registered geometry for independent readers") {
                var fixture=House.empty("Interchange axes fixture")
                let room=fixture.rooms[0].id,stage=fixture.stages[0].id
                let segment=Segment(roomID:room,stageID:stage,registration:Rigid(values:[0,-1,0,4, 1,0,0,-2, 0,0,1,3, 0,0,0,1]))
                fixture.segments=[segment]
                let a=Feature(id:UUID(uuidString:"11111111-1111-4111-8111-111111111111")!,name:"Asymmetric tetrahedron",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,mesh:Mesh(vertices:[V3(),V3(1,0,0),V3(0,2,0),V3(0,0,3)],triangles:[0,2,1,0,1,3,0,3,2,1,2,3]))
                var b=Feature(id:UUID(uuidString:"22222222-2222-4222-8222-222222222222")!,name:"Registered triangle",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,mesh:Mesh(vertices:[V3(-1,0,0),V3(0,2,0),V3(0,0,1)],triangles:[0,1,2]))
                b.segmentID=segment.id
                var hidden=a;hidden.id=UUID();hidden.hidden=true;hidden.mesh.vertices=[V3(100,100,100)];hidden.mesh.triangles=[]
                fixture.features=[a,b,hidden]
                for ply in [true,false] {
                    let url=try Exporter.meshText(fixture,options:SceneOptions(),ply:ply)
                    try Data(contentsOf:url).write(to:mainRepo.root.appendingPathComponent(ply ? "interchange.ply":"interchange.obj"))
                }
                return true
            }
            await check("Semantic CSV preserves frames and relationships with bounded failure cleanup") {
                var fixture=House.empty("CSV synthetic fixture")
                let room=fixture.rooms[0].id,stage=fixture.stages[0].id
                fixture.rooms[0].name="Kitchen, café\nNorth";fixture.rooms[0].level = -1
                fixture.stages[0].date=Date(timeIntervalSince1970:1_700_000_000)
                let registered=Segment(roomID:room,stageID:stage,registration:Rigid(values:[0,-1,0,4, 1,0,0,-2, 0,0,1,3, 0,0,0,1]),approved:true)
                let separate=Segment(roomID:room,stageID:stage)
                fixture.segments=[registered,separate]
                var a=Feature(id:UUID(uuidString:"11111111-1111-4111-8111-111111111111")!,name:"=1+1",trade:.plumbing,roomID:room,stageID:stage,kind:.synthetic,mesh:Mesh(),route:[V3(-1,2,3),V3(4,5,6)],notes:"Quoted \"valve\", next\r\nline",endpoint:"Sink, \"cold\"")
                a.segmentID=registered.id;a.hidden=true;a.reviewed=true
                a.service=ServiceDetails(classification:.supply,observedLabel:"=literal valve label",panelReference:"Panel, café",port:"P-24",pipeDuctEnvelope:"20 mm recorded",installationDate:"2024-02-29",confidence:.ownerConfirmed,identityEvidence:"Synthetic witnessed test, not field evidence")
                var b=a;b.id=UUID(uuidString:"22222222-2222-4222-8222-222222222222")!;b.segmentID=separate.id;b.name="'literal";b.hidden=false
                var c=a;c.id=UUID(uuidString:"33333333-3333-4333-8333-333333333333")!;c.segmentID=nil;c.name="House route";c.route=[V3(),V3(0,0,2)]
                fixture.features=[a,b,c]
                fixture.dimensions=[Dimension(name:"Measured span",a:V3(-1,2,3),b:V3(2,6,3),roomID:room,date:Date(timeIntervalSince1970:1_700_000_000),sourceRevision:1,segmentID:separate.id)]
                fixture.connections=[ServiceConnection(fromFeature:a.id,fromEnd:1,toFeature:b.id,toEnd:0,confirmed:true,notes:"\t=HYPERLINK()",date:Date(timeIntervalSince1970:1_700_000_000))]
                let url=try Exporter.semanticCSV(fixture)
                let data=try Data(contentsOf:url)
                try data.write(to:mainRepo.root.appendingPathComponent("semantic.csv"))
                try Data(contentsOf:Exporter.metadata(fixture)).write(to:mainRepo.root.appendingPathComponent("semantic-source.json"))
                let directory=url.deletingLastPathComponent()
                let before=Set(try FileManager.default.contentsOfDirectory(atPath:directory.path))
                for budget in [1,data.count/2] {
                    do{_=try Exporter.semanticCSV(fixture,maximumBytes:budget);return false}catch{}
                    guard Set(try FileManager.default.contentsOfDirectory(atPath:directory.path))==before else{return false}
                }
                return !data.isEmpty
            }
            await check("USDZ stored and 64-byte aligned"){let url=try Exporter.usdz(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.usdz"));let entries=try StoredZip.read(url);let start=30+Int(d.uint16(26))+Int(d.uint16(28));return start%64==0 && entries.first?.name=="house.usda"}
            await check("No tour across absent captured rooms"){let empty=House.empty("Uncaptured");let plan=TourDirector.plan(empty);return plan.shots.isEmpty && plan.excluded.count==1}
            await check("Before-after and service tours retain stage identity and exact frame timeline") {
                for preset in [TourPreset.beforeAfter,.services] {
                    let plan=TourDirector.plan(house,duration:10,preset:preset)
                    guard !plan.shots.isEmpty,plan.shots.allSatisfy({$0.duration<=5 && $0.layerMode != nil && $0.tradeNames != nil}),plan.shots.reduce(0,{ $0+Int(($1.duration*30).rounded()) })==300 else{return false}
                    if preset == .beforeAfter {guard Set(plan.shots.compactMap{$0.layerMode})==Set([ViewMode.rough.rawValue,ViewMode.finished.rawValue]) else{return false}}
                }
                return true
            }
            await check("Deterministic tour source revision"){let a=try JSONEncoder().encode(TourDirector.plan(house)),b=try JSONEncoder().encode(TourDirector.plan(house));let p=try JSONDecoder().decode(TourPlan.self,from:a),q=try JSONDecoder().decode(TourPlan.self,from:b);return Set(p.shots.map{$0.roomID}).count==3 && p.shots.allSatisfy{$0.duration<=5} && p.sourceRevision==q.sourceRevision && p.shots.map{$0.position}==q.shots.map{$0.position}}
            await check("Clearance handles parallel rays and rejects incomplete indexes"){
                let box=SpatialClearance.Bounds(low:V3(),high:V3(1,1,1))
                let f=Feature(name:"wall",trade:.structure,roomID:UUID(),stageID:UUID(),kind:.synthetic,mesh:.box(center:V3(),size:V3(1,1,1)))
                let limited=SpatialClearance(features:[f],limit:1)
                return box.intersects(V3(-1,0.5,0.5),V3(2,0.5,0.5),radius:0) && !box.intersects(V3(-1,2,0.5),V3(2,2,0.5),radius:0) && !limited.complete && !limited.isClear(from:V3(5),to:V3(6),radius:0.15)
            }
            await check("Local clearance covers crossing triangles, refuses unchecked movement and retains dense limits") {
                // The triangle centre lies far outside the local region; its full bounds cross it.
                let mesh=Mesh(vertices:[V3(-1,1,-1),V3(100,1,-1),V3(-1,1,100)],triangles:[0,1,2])
                let f=Feature(name:"Long wall",trade:.structure,roomID:UUID(),stageID:UUID(),kind:.synthetic,mesh:mesh)
                let index=try SpatialDisplayIndex(features:[f]),local=try SpatialClearance(index:index,camera:V3())
                let dense=try SpatialClearance(index:index,camera:V3(),limit:0)
                let empty=try SpatialClearance(index:SpatialDisplayIndex(features:[]),camera:V3())
                return local.complete && local.primitiveCount==1 && local.isClear(from:V3(),to:V3(0.2,0,0),radius:0.15)
                  && !local.isClear(from:V3(),to:V3(0,2,0),radius:0.15)
                  && !local.isClear(from:V3(),to:V3(4,0,0),radius:0.15)
                  && !dense.complete && !dense.isClear(from:V3(),to:V3(0.1,0,0),radius:0.15)
                  && empty.isClear(from:V3(),to:V3(1,0,0),radius:0.15)
                  && !empty.isClear(from:V3(),to:V3(5,0,0),radius:0.15)
            }
            await check("Walking checks full body height, narrow openings and the complete local coverage volume") {
                func obstacle(_ centre:V3,_ size:V3)->Feature {
                    Feature(name:"Walk obstruction",trade:.structure,roomID:UUID(),stageID:UUID(),kind:.synthetic,mesh:.box(center:centre,size:size))
                }
                let a=V3(0,0,1.6),b=V3(1,0,1.6)
                let knee=SpatialClearance(features:[obstacle(V3(0.5,0,0.4),V3(0.1,1,0.2))])
                let beam=SpatialClearance(features:[obstacle(V3(0.5,0,1.82),V3(0.1,1,0.04))])
                guard knee.isClear(from:a,to:b,radius:0.15),!knee.isWalkClear(from:a,to:b),
                  beam.isClear(from:a,to:b,radius:0.15),!beam.isWalkClear(from:a,to:b) else{return false}
                let floor=obstacle(V3(0.5,0,-0.1),V3(3,3,0.2))
                guard SpatialClearance(features:[floor]).isWalkClear(from:a,to:b) else{return false}
                func doorway(_ width:Double)->SpatialClearance {
                    SpatialClearance(features:[floor,obstacle(V3(0.5,-1-width/2,1),V3(0.1,2,2)),obstacle(V3(0.5,1+width/2,1),V3(0.1,2,2))])
                }
                guard doorway(0.8).isWalkClear(from:a,to:b),!doorway(0.35).isWalkClear(from:a,to:b) else{return false}
                let local=try SpatialClearance(index:SpatialDisplayIndex(features:[]),camera:a,radius:2)
                return local.isWalkClear(from:a,to:V3(0.5,0,1.6))
                  && !local.isWalkClear(from:a,to:V3(1.5,0,1.6))
                  && !local.isWalkClear(from:a,to:V3(Double.nan,0,1.6))
            }
            await check("Step navigation shares floor and wall collision, clamps input, snaps look and clears continuous movement") {
                var h=House.empty("Step controls");h.isDemo=true
                h.rooms[0].origin=V3();h.rooms[0].size=V3(6,6,3)
                let room=h.rooms[0].id,stage=h.stages[0].id
                h.features=[Feature(name:"Floor",trade:.floor,roomID:room,stageID:stage,kind:.synthetic,mesh:.box(center:V3(3,3,-0.1),size:V3(6,6,0.2))),
                  Feature(name:"Blocking wall",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,mesh:.box(center:V3(3,3.5,1.5),size:V3(6,0.1,3)))]
                let controller=WalkController();defer{controller.stop()}
                controller.load(h,SceneOptions());controller.camera.simdPosition=V3(3,3,1.6).render;controller.yaw=0;controller.pitch=0
                controller.move=SIMD2(1,1);controller.vertical=1;controller.stepMove(SIMD2(0,10))
                let first=V3(ar:controller.camera.simdPosition)
                guard (first-V3(3,3.2,1.6)).length<1e-5,controller.move == .zero,controller.vertical==0 else{return false}
                controller.stepMove(SIMD2(0,1))
                guard (V3(ar:controller.camera.simdPosition)-first).length<1e-5 else{return false}
                var hidden=SceneOptions();hidden.trades=[];hidden.ceilings=false
                controller.load(h,hidden)
                guard SceneBuilder.features(h,options:hidden).isEmpty,NavigationGeometry.collisionFeatures(h,options:hidden).count==2 else{return false}
                controller.stepMove(SIMD2(0,1))
                guard (V3(ar:controller.camera.simdPosition)-first).length<1e-5 else{return false}
                let index=try SpatialDisplayIndex(features:NavigationGeometry.collisionFeatures(h,options:hidden))
                guard try SpatialClearance(index:index,camera:first).walkingDestination(from:first,toward:V3(3,3.4,1.6))==nil else{return false}
                h.features[1].hidden=true;h.revision+=1;controller.load(h,hidden);controller.stepMove(SIMD2(0,1))
                guard NavigationGeometry.collisionFeatures(h,options:hidden).count==2,(V3(ar:controller.camera.simdPosition)-first).length<1e-5 else{return false}
                controller.stepLook(yaw:Float.pi/12,pitch:Float.pi/12)
                guard abs(controller.yaw-Float.pi/12)<1e-6,abs(controller.pitch-Float.pi/12)<1e-6 else{return false}
                controller.flying=true;controller.stepMove(SIMD2(0,1))
                guard (V3(ar:controller.camera.simdPosition)-first).length>0.19 else{return false}
                let before=controller.camera.simdPosition;controller.stepMove(SIMD2(Float.nan,0))
                controller.move=SIMD2(1,1);controller.setOrbit(true);controller.stepMove(SIMD2(0,1))
                guard controller.orbit,controller.view.allowsCameraControl,controller.move == .zero,controller.camera.simdPosition==before else{return false}
                controller.setOrbit(false)
                guard !controller.orbit,!controller.view.allowsCameraControl,controller.view.pointOfView===controller.camera else{return false}
                controller.move=SIMD2(1,1);controller.vertical=1;controller.stop()
                return controller.camera.simdPosition==before && controller.move == .zero && controller.vertical==0
            }
            await check("Unsafe bookmarks relocate without motion and an unsupported stage explicitly falls back to Free fly") {
                var h=House.empty("Safe viewpoints");h.isDemo=true;h.rooms[0].size=V3(6,6,3)
                let room=h.rooms[0].id,stage=h.stages[0].id
                h.features=[Feature(name:"Floor",trade:.floor,roomID:room,stageID:stage,kind:.synthetic,mesh:.box(center:V3(3,3,-0.1),size:V3(6,6,0.2))),
                  Feature(name:"Wall",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,mesh:.box(center:V3(3,3.5,1.5),size:V3(6,0.1,3)))]
                let controller=WalkController();defer{controller.stop()};controller.load(h,SceneOptions())
                controller.bookmark(Bookmark(name:"Blocked",position:V3(3,3.5,1.6),yaw:0,pitch:0,roomID:room))
                guard !controller.flying,(V3(ar:controller.camera.simdPosition)-V3(3,3,1.6)).length<1e-5 else{return false}
                var unsupported=SceneOptions();unsupported.stage=h.stages[1].id
                controller.load(h,unsupported)
                return controller.flying && controller.navigationNotice.contains("No checked walking viewpoint") && h.features.count==2
            }
            await check("Observed floor walking preserves capture height, climbs checked steps and refuses holes or low headroom") {
                func floor(_ centre:V3,_ size:V3)->Feature {Feature(name:"Observed floor fixture",trade:.floor,roomID:UUID(),stageID:UUID(),kind:.synthetic,mesh:.box(center:centre,size:size))}
                let ground=floor(V3(0,0,-0.1),V3(4,3,0.2)),low=V3(0,0,1.1),target=V3(0.5,0,1.1)
                let flat=SpatialClearance(features:[ground])
                guard !flat.isWalkClear(from:low,to:target),let result=flat.walkingDestination(from:low,toward:target),(result.position-target).length<1e-9 else{return false}
                let beam=Feature(name:"Low beam",trade:.structure,roomID:UUID(),stageID:UUID(),kind:.synthetic,mesh:.box(center:V3(0.4,0,1.7),size:V3(0.2,2,0.15)))
                guard SpatialClearance(features:[ground,beam]).walkingDestination(from:low,toward:target)==nil else{return false}
                let gap=[floor(V3(-0.3,0,-0.1),V3(1.4,2,0.2)),floor(V3(1.3,0,-0.1),V3(1.4,2,0.2))]
                guard SpatialClearance(features:gap).walkingDestination(from:low,toward:V3(1,0,1.1))==nil else{return false}
                var stairs=[floor(V3(-0.4,0,-0.1),V3(1.2,2,0.2))]
                for i in 1...5 {let top=Double(i)*0.18;stairs.append(floor(V3(Double(i)*0.4,0,(top-0.1)/2),V3(0.4,2,top+0.1)))}
                let stair=SpatialClearance(features:stairs),start=V3(-0.5,0,1.3)
                guard let up=stair.walkingDestination(from:start,toward:V3(1.4,0,1.3)),up.position.z>1.8,
                  let down=stair.walkingDestination(from:up.position,toward:start,eyeHeight:up.eyeHeight),(down.position-start).length<1e-8 else{return false}
                let tall=[stairs[0],floor(V3(0.4,0,0.125),V3(0.4,2,0.45))]
                guard SpatialClearance(features:tall).walkingDestination(from:start,toward:V3(0.4,0,1.3))==nil else{return false}
                let local=try SpatialClearance(index:SpatialDisplayIndex(features:[ground]),camera:low,radius:1)
                return local.walkingDestination(from:low,toward:target)==nil
            }
            await check("Observed ramps use exact swept floors and keep stacked levels distinct") {
                func surface(_ x0:Double,_ x1:Double,_ z0:Double,_ z1:Double)->Feature {
                    Feature(name:"Observed ramp fixture",trade:.floor,roomID:UUID(),stageID:UUID(),kind:.synthetic,
                      mesh:Mesh(vertices:[V3(x0,-1,z0),V3(x1,-1,z1),V3(x1,1,z1),V3(x0,1,z0)],triangles:[0,1,2,0,2,3]))
                }
                let features=[surface(-2,0,0,0),surface(0,2,0,0.5),surface(2,4,0.5,0.5),surface(-2,4,3,3)]
                let clearance=SpatialClearance(features:features),start=V3(-0.5,0,1.3)
                guard clearance.primitiveCount==8,
                  let middle=clearance.walkingDestination(from:start,toward:V3(1.5,0,1.3)),
                  let top=clearance.walkingDestination(from:middle.position,toward:V3(2.8,0,1.3),eyeHeight:middle.eyeHeight),
                  abs(top.position.z-1.8)<1e-8,
                  let back=clearance.walkingDestination(from:top.position,toward:V3(1,0,1.3),eyeHeight:top.eyeHeight),
                  let bottom=clearance.walkingDestination(from:back.position,toward:start,eyeHeight:back.eyeHeight),
                  (bottom.position-start).length<1e-8 else{return false}
                // A request above the next level cannot teleport through its
                // floor; walking remains attached to the observed lower one.
                guard let lower=clearance.walkingDestination(from:start,toward:V3(-0.4,0,4.3)),lower.position.z<2 else{return false}
                guard !clearance.isClear(from:V3(1,0,1),to:V3(1,0,-1),radius:0.1),
                  clearance.isClear(from:V3(0.3,0,0.6),to:V3(0.6,0,0.6),radius:0.1) else{return false}
                let lowCeiling=SpatialClearance(features:features+[surface(0,2,1.7,2.2)])
                guard lowCeiling.walkingDestination(from:start,toward:V3(1.5,0,1.3))==nil else{return false}
                let local=try SpatialClearance(index:SpatialDisplayIndex(features:features),camera:V3(1,0,1.5),radius:4)
                guard local.primitiveCount==8,let indexed=local.walkingDestination(from:start,toward:V3(1.5,0,1.3)),(indexed.position-middle.position).length<1e-8 else{return false}
                let limited=SpatialClearance(features:features,limit:7)
                return !limited.complete && limited.walkingDestination(from:start,toward:V3(0,0,1.3))==nil
            }
            await check("Tour path rejects observed wall and accepts supported camera corridor"){
                var h=House.empty("Path test");let r=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:r.id,stageID:stage.id);h.segments=[segment]
                for i in 0..<2 {var m=Rigid().values;m[3]=Double(i)*0.5;m[7]=1.6;h.observations.append(Observation(roomID:r.id,stageID:stage.id,segmentID:segment.id,timestamp:Double(i),image:"camera.jpg",width:64,height:64,camera:m,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1))}
                h.features=[Feature(name:"Captured floor",trade:.floor,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:V3(0,0,-0.1),size:V3(3,3,0.1)),segmentID:segment.id)]
                let a=V3(0,0,1.6),b=V3(0.5,0,1.6),options=SceneOptions()
                guard TourDirector.clearPath(a,b,house:h,options:options,clearance:SpatialClearance(features:Exporter.canonicalFeatures(h,options:options))),TourDirector.plan(h).shots.contains(where:{$0.endPosition != nil}) else{return false}
                h.features=[Feature(name:"Blocking wall",trade:.structure,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:V3(0.25,0,1.6),size:V3(0.1,2,2)),segmentID:segment.id)]
                return !TourDirector.clearPath(a,b,house:h,options:options,clearance:SpatialClearance(features:Exporter.canonicalFeatures(h,options:options))) && TourDirector.plan(h).shots.allSatisfy{$0.endPosition==nil}
            }
            await check("Stationary tour fallback selects a clear captured pose or explicitly omits the room") {
                var h=House.empty("Stationary clearance");let r=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:r.id,stageID:stage.id);h.segments=[segment]
                for i in 0..<2 {var m=Rigid().values;m[3]=Double(i)*0.5;m[7]=1.6;h.observations.append(Observation(roomID:r.id,stageID:stage.id,segmentID:segment.id,timestamp:Double(i),image:"camera.jpg",width:64,height:64,camera:m,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1))}
                func obstruction(_ x:Double)->Feature {Feature(name:"Recorded obstruction",trade:.structure,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:V3(x,0,1.6),size:V3(0.1,2,2)),segmentID:segment.id)}
                h.features=[obstruction(0.5)]
                let fallback=TourDirector.plan(h,duration:5)
                guard !fallback.shots.isEmpty,fallback.shots.allSatisfy({$0.position==V3(0,0,1.6) && $0.endPosition==nil}) else{return false}
                h.features.append(obstruction(0))
                let omitted=TourDirector.plan(h,duration:5)
                guard omitted.shots.isEmpty,omitted.excluded.count==1,omitted.excluded[0].contains("camera clearance") else{return false}
                h.isDemo=true;h.observations=[];h.features=[Feature(name:"Blocked demo entry",trade:.structure,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:r.origin+V3(r.size.x/2,r.size.y/2,1.6),size:V3(0.1,2,2)))]
                let demo=TourDirector.plan(h,duration:5)
                return demo.shots.isEmpty && demo.excluded.count==1
            }
            await check("Tour duration preserves frame totals while bounding within-shot speed acceleration and rotation") {
                let fast=TourShot(roomID:UUID(),position:V3(),yaw:0,pitch:0,caption:"Observed path",duration:0.2,endPosition:V3(1,0,0),endYaw:0,endPitch:0)
                let cut=TourDirector.boundedMotion([fast])
                guard cut.cuts==1,cut.shots[0].duration==fast.duration,cut.shots[0].endPosition==nil,cut.shots[0].position==fast.position else{return false}
                var slow=fast;slow.duration=3;slow.endYaw=0.3
                guard TourDirector.boundedMotion([slow]).cuts==0 else{return false}
                var spin=slow;spin.endYaw=Double.pi
                guard TourDirector.boundedMotion([spin]).cuts==1 else{return false}
                for duration in [1.0/30,0.5,2,5] {
                    let still=TourShot(roomID:UUID(),position:V3(),yaw:0,pitch:0,caption:"Stationary",duration:duration)
                    let dt=duration/200
                    let angles=(0...200).map{TourDirector.camera(still,phase:Double($0)/200).1}
                    let rates=(1...200).map{(angles[$0]-angles[$0-1])/dt}
                    guard rates.allSatisfy({abs($0)<=0.600001}),
                      (1..<rates.count).allSatisfy({abs((rates[$0]-rates[$0-1])/dt)<=1.200001}) else{return false}
                }
                let chunks=TourDirector.chunk([slow])
                guard abs(chunks.reduce(0){$0+$1.duration}-slow.duration)<1e-12 else{return false}
                var plan=TourPlan(sourceRevision:1,synthetic:true,shots:[slow],excluded:[])
                guard plan.motionProfile=="camera-motion-v1" else{return false}
                plan.motionProfile=nil
                return try JSONDecoder().decode(TourPlan.self,from:JSONEncoder().encode(plan)).motionProfile==nil
            }
            await check("Moving tour uses short-angle interpolation and endpoint continuity"){
                let shot=TourShot(roomID:UUID(),position:V3(),yaw:179*Double.pi/180,pitch:0,caption:"test",duration:5,endPosition:V3(1,0,0),endYaw: -179*Double.pi/180,endPitch:0.2)
                let a=TourDirector.camera(shot,phase:0),m=TourDirector.camera(shot,phase:0.5),b=TourDirector.camera(shot,phase:1)
                return a.0==V3() && b.0==V3(1,0,0) && abs(m.0.x-0.5)<1e-10 && abs(m.1-Double.pi)<1e-10 && abs(m.2-0.1)<1e-10
            }
            await check("Tour sightlines use exact triangles and framing rejects near offscreen and behind-camera subjects") {
                let h=House.empty("Sightline fixture"),triangle=Mesh(vertices:[V3(-2,2,-2),V3(2,2,-2),V3(-2,2,2)],triangles:[0,1,2])
                let feature=Feature(name:"Diagonal face",trade:.structure,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.synthetic,mesh:triangle)
                let sightlines=TourSightlines(features:[feature],house:h),limited=TourSightlines(features:[feature],house:h,limit:0)
                guard sightlines.visible(from:V3(),to:V3(1.5,3,1.5)),!sightlines.visible(from:V3(),to:V3(-1,3,-1)),
                  sightlines.visible(from:V3(),to:V3(-0.5,2,-0.5)),!limited.visible(from:V3(),to:V3(1.5,3,1.5)) else{return false}
                let camera=(V3(),0.0,0.0)
                guard TourFraming.inFrame(V3(0,1,0),camera:camera),TourFraming.inFrame(V3(0.4,1,0),camera:camera),
                  !TourFraming.inFrame(V3(0.4,1,0),camera:camera,aspect:0.5),
                  ![V3(0,-1,0),V3(0,0.2,0),V3(2,1,0),V3(0,1,1),V3(0,31,0)].contains(where:{TourFraming.inFrame($0,camera:camera)}) else{return false}
                guard TourFraming.inFrame(V3(-2,0,0),camera:(V3(),Double.pi/2,0)),TourFraming.inFrame(V3(0,1,1),camera:(V3(),0,Double.pi/4)) else{return false}
                // Near-camera clutter must not consume the bounded candidate
                // search before a useful farther subject is considered.
                var crowded=House.empty("Subject search budget");crowded.isDemo=true
                for _ in 0..<30 {crowded.features.append(Feature(name:"Near points",trade:.unknown,roomID:crowded.rooms[0].id,stageID:crowded.stages[0].id,kind:.synthetic,mesh:Mesh(vertices:Array(repeating:V3(0,0.1,0),count:8),triangles:[])))}
                let distant=Feature(name:"Useful point",trade:.unknown,roomID:crowded.rooms[0].id,stageID:crowded.stages[0].id,kind:.synthetic,mesh:Mesh(vertices:[V3(0,2,0)],triangles:[]))
                crowded.features.append(distant)
                let shot=TourShot(roomID:crowded.rooms[0].id,position:V3(),yaw:0,pitch:0,caption:"Budget fixture",duration:5)
                let selected=TourFraming.apply([shot],house:crowded,options:SceneOptions())
                return selected.shots.count==1 && selected.shots[0].subject?.featureID==distant.id
            }
            await check("Automatic tours retain a source-linked visible subject for every output frame") {
                let h=try SimulatedCapture.make(repo:repo),plan=TourDirector.plan(h,duration:10)
                guard plan.framingProfile==TourFraming.profile,!plan.shots.isEmpty,plan.shots.reduce(0,{$0+Int(($1.duration*30).rounded())})==300 else{return false}
                let sightlines=TourSightlines(features:SceneBuilder.features(h,options:SceneOptions()),house:h)
                for shot in plan.shots {
                    guard let subject=shot.subject,h.features.contains(where:{$0.id==subject.featureID && $0.revision==subject.featureRevision}),
                      TourFraming.check(shot,sightlines:sightlines,steps:max(1,Int((shot.duration*30).rounded()))) else{return false}
                }
                let decoded=try JSONDecoder().decode(TourPlan.self,from:JSONEncoder().encode(plan))
                guard decoded.shots.map({$0.subject})==plan.shots.map({$0.subject}) else{return false}
                var planned=h;planned.features[0].kind = .planned
                let design=TourDirector.plan(planned,duration:5)
                guard !design.shots.isEmpty,design.shots.allSatisfy({$0.includesPlannedGeometry==true}) else{return false}
                let report:[String:Any]=["passed":true,"analyticOnly":true,"physicalQualification":false,"frames":300,"shots":plan.shots.count,"allRenderedFrameSubjectsVisible":true,"sourceLinked":true,"rawTargetRecordsPublished":false,"fullRoomCoverageQualified":false]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:mainRepo.root.appendingPathComponent("native-tour-framing.json"))
                return true
            }
            await check("Moving subject occlusion requires a cut and overly close geometry does not produce a blank tour") {
                var h=try SimulatedCapture.make(repo:repo)
                let obstacle=Feature(name:"Foreground obstacle",trade:.structure,roomID:h.rooms[0].id,stageID:h.stages[0].id,kind:.synthetic,mesh:.box(center:V3(0,1,1.4),size:V3(0.1,0.02,0.5)))
                let sightlines=TourSightlines(features:[obstacle],house:h)
                let subject=TourSubject(featureID:h.features[0].id,featureRevision:h.features[0].revision,point:V3(0,2,1.4))
                let moving=TourFraming.framed(TourShot(roomID:h.rooms[0].id,position:V3(-0.4,0,1.4),yaw:0,pitch:0,caption:"Occluded move",duration:5,endPosition:V3(0.4,0,1.4),endYaw:0,endPitch:0),subject:subject)
                guard !TourFraming.check(moving,sightlines:sightlines,steps:150),TourFraming.check(TourFraming.held(moving),sightlines:sightlines,steps:150) else{return false}
                for i in h.observations.indices {h.observations[i].camera[3]=0}
                h.features[0].mesh = .box(center:V3(0,0.2,1.4),size:V3(0.01,0.01,0.01))
                let plan=TourDirector.plan(h,duration:5)
                return plan.shots.isEmpty && plan.excluded.contains(where:{$0.contains("framing and distance limits")})
            }
            await check("Tour cache separates layers and projects"){let plan=TourDirector.plan(house);let a=try MovieExporter.cacheKey(house:house,plan:plan,options:SceneOptions());let b=try MovieExporter.cacheKey(house:house,plan:plan,options:SceneOptions(mode:.finished));var other=house;other.id=UUID();let c=try MovieExporter.cacheKey(house:other,plan:plan,options:SceneOptions());return a != b && a != c}
            await check("Walk collision and explicit doorway"){NavigationGeometry.allowed(V3(3,2,1.6),house:house) && !NavigationGeometry.allowed(V3(3,-0.1,1.6),house:house) && NavigationGeometry.allowed(V3(6.1,2.2,1.6),house:house) && !NavigationGeometry.allowed(V3(6.1,1,1.6),house:house)}
            await check("SceneKit offscreen render"){let scene=SceneBuilder.scene(house,options:SceneOptions());let camera=SceneBuilder.camera(at:V3(13,-12,12));camera.look(at:SCNVector3(4,1,-2));scene.rootNode.addChildNode(camera);let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;let image=renderer.snapshot(atTime:0,with:CGSize(width:480,height:320),antialiasingMode:.none);try image.pngData()?.write(to:mainRepo.root.appendingPathComponent("test-render.png"));return image.cgImage.map{CaptureController.sharpness($0)>0.002} ?? false}
            await check("Two-reference drift correction and inconsistent-board rejection"){
                var h=House.empty("Reference checks");let a=ReferenceBoard(name:"A",image:"a.png",pdf:"a.pdf",width:0.18),b=ReferenceBoard(name:"B",image:"b.png",pdf:"b.pdf",width:0.18);h.references=[a,b]
                var fixedA=Rigid().values,fixedB=Rigid().values;fixedA[3] = -0.5;fixedB[3]=0.5
                var s=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);s.referencePoses=[ReferencePose(boardID:a.id,matrix:fixedA),ReferencePose(boardID:b.id,matrix:fixedB)]
                var movedA=fixedA,movedB=fixedB,camera=Rigid().values;movedA[3]+=0.1;movedB[3]+=0.1;camera[3]=0.1
                var o=Observation(roomID:s.roomID,stageID:s.stageID,segmentID:s.id,timestamp:0,image:"a.jpg",width:64,height:64,camera:camera,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1,referenceObservations:[ReferencePose(boardID:a.id,matrix:movedA),ReferencePose(boardID:b.id,matrix:movedB)])
                guard let corrected=PoseRefinement.refine(o,segment:s,house:h),abs(corrected.observation.camera[3])<1e-9,o.camera[3]==0.1 else{return false}
                movedB[3]+=0.2;o.referenceObservations=[ReferencePose(boardID:a.id,matrix:movedA),ReferencePose(boardID:b.id,matrix:movedB)]
                return PoseRefinement.refine(o,segment:s,house:h)==nil
            }
            await check("Reference correction preserves nontrivial camera rotation"){
                var h=House.empty("Rotated controls");let a=ReferenceBoard(name:"A",image:"a.png",pdf:"a.pdf",width:0.18),b=ReferenceBoard(name:"B",image:"b.png",pdf:"b.pdf",width:0.18);h.references=[a,b]
                let angle=0.07,c=cos(angle),sn=sin(angle);let drift=PoseRefinement.matrix([c,-sn,0,0.1,sn,c,0,-0.05,0,0,1,0.02,0,0,0,1])!
                let truth=[cos(0.3),0,sin(0.3),1,0,1,0,0.3,-sin(0.3),0,cos(0.3),2,0,0,0,1.0]
                var fixedA=Rigid().values,fixedB=Rigid().values;fixedA[3] = -0.5;fixedA[11] = -2;fixedB[3]=0.5;fixedB[11] = -2.5
                var s=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);s.referencePoses=[ReferencePose(boardID:a.id,matrix:fixedA),ReferencePose(boardID:b.id,matrix:fixedB)]
                let o=Observation(roomID:s.roomID,stageID:s.stageID,segmentID:s.id,timestamp:0,image:"a.jpg",width:64,height:64,camera:PoseRefinement.array(drift*PoseRefinement.matrix(truth)!),intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1,referenceObservations:[ReferencePose(boardID:a.id,matrix:PoseRefinement.array(drift*PoseRefinement.matrix(fixedA)!)),ReferencePose(boardID:b.id,matrix:PoseRefinement.array(drift*PoseRefinement.matrix(fixedB)!))])
                guard let corrected=PoseRefinement.refine(o,segment:s,house:h,maximumCorrection:.infinity) else{return false}
                let error=zip(corrected.observation.camera,truth).map{abs($0-$1)}.max() ?? .infinity;h.references[1].valid=false
                return error<1e-9 && PoseRefinement.refine(o,segment:s,house:h)==nil
            }
            await check("Projection and occlusion rejection"){
                var depth=Data();for _ in 0..<64*64{depth.float(1)}
                let o=Observation(roomID:house.rooms[0].id,stageID:house.stages[0].id,segmentID:UUID(),timestamp:0,image:"fixture.jpg",width:64,height:64,camera:Rigid().values,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"normal",light:1000,sharpness:0.1)
                guard let (uv,z)=TextureBuilder.project(V3(0,1,0),through:o) else{return false}
                var withDepth=o;withDepth.depthWidth=64;withDepth.depthHeight=64
                let camera=TextureBuilder.Camera(observation:withDepth,depth:depth,confidence:Data(repeating:2,count:64*64))
                for invalid in [Data?.none,Data(repeating:255,count:64*64),Data(repeating:1,count:64*64)] {
                    guard !TextureBuilder.visible(uv,z:z,camera:TextureBuilder.Camera(observation:withDepth,depth:depth,confidence:invalid)) else{return false}
                }
                return abs(uv.u-0.5)<1e-9 && abs(uv.v-0.5)<1e-9 && TextureBuilder.visible(uv,z:z,camera:camera) && !TextureBuilder.visible(uv,z:2,camera:camera)
            }
            await check("IFC total geometry budget and complete transaction boundary") {
                let room=UUID(),stage=UUID()
                let valid:[String:Any]=["name":"Triangle","guid":"fixture","object":["expressID":22,"typeName":"IFCBUILDINGELEMENTPROXY","guid":"fixture","guidStatus":"malformed"],"vertices":[[0.0,0,0],[1.0,0,0],[0.0,1,0]],"indices":[Int32(0),1,2]]
                let feature=try IFCImporter.decodeMesh(valid,roomID:room,stageID:stage,currentVertices:199997,currentIndices:1199997)
                guard feature.kind == .planned,feature.mesh.vertices[2]==V3(0,0,1) else{return false}
                for counts in [(10000,0),(-1,0),(0,16_000_000),(0,-1)] {
                    do {_ = try IFCImporter.decodeMesh(valid,roomID:room,stageID:stage,currentVertices:0,currentIndices:0,currentParts:counts.0,currentMetadataBytes:counts.1);return false}catch{}
                }
                _ = try IFCImporter.decodeMesh(valid,roomID:room,stageID:stage,currentVertices:0,currentIndices:0,currentParts:9999,currentMetadataBytes:16_000_000-IFCImporter.metadataCost(feature))
                for counts in [(199998,0),(0,1199998),(-1,0),(0,-1)] {
                    do {_ = try IFCImporter.decodeMesh(valid,roomID:room,stageID:stage,currentVertices:counts.0,currentIndices:counts.1);return false}catch{}
                }
                for field in ["vertices","indices","name","guid","object"] {
                    var malformed=valid;malformed.removeValue(forKey:field)
                    do {_ = try IFCImporter.decodeMesh(malformed,roomID:room,stageID:stage,currentVertices:0,currentIndices:0);return false}catch{}
                }
                var invalid=valid;invalid["indices"]=[Int32(0),1,3]
                do {_ = try IFCImporter.decodeMesh(invalid,roomID:room,stageID:stage,currentVertices:0,currentIndices:0);return false}catch{}
                invalid=valid;invalid["vertices"]=[[Double.nan,0,0],[1.0,0,0],[0.0,1,0]]
                do {_ = try IFCImporter.decodeMesh(invalid,roomID:room,stageID:stage,currentVertices:0,currentIndices:0);return false}catch{}
                let done:[String:Any]=["parts":1,"vertices":3,"indices":3]
                return IFCImporter.complete(done,parts:1,vertices:3,indices:3)
                    && !IFCImporter.complete(done,parts:2,vertices:3,indices:3)
                    && !IFCImporter.complete(done,parts:1,vertices:4,indices:3)
                    && !IFCImporter.complete(done,parts:1,vertices:3,indices:6)
                    && !IFCImporter.complete([:],parts:0,vertices:0,indices:0)
            }
            var ifcCase="Bundled IFC2x3 conversion and axes"
            do {
                guard let path=Bundle.main.url(forResource:"IFC",withExtension:nil)?.appendingPathComponent("test-block.ifc") else{throw HouseError.message("IFC test fixture missing.")}
                let importer=IFCImporter(),input=try Data(contentsOf:path),roomID=house.rooms[0].id,stageID=house.stages[0].id
                let cancelled=Task {try await importer.load(input,roomID:roomID,stageID:stageID)}
                await Task.yield();cancelled.cancel()
                do{_=try await cancelled.value;throw HouseError.message("Cancelled IFC import unexpectedly published geometry.")}catch is CancellationError{}
                let features=try await importer.load(input,roomID:roomID,stageID:stageID)
                let points=features.flatMap{$0.mesh.vertices};let extent=V3((points.map{$0.x}.max() ?? 0)-(points.map{$0.x}.min() ?? 0),(points.map{$0.y}.max() ?? 0)-(points.map{$0.y}.min() ?? 0),(points.map{$0.z}.max() ?? 0)-(points.map{$0.z}.min() ?? 0))
                results.append(["test":"Bundled IFC2x3 conversion and axes","passed":abs(extent.x-1)<0.001 && abs(extent.y-2)<0.001 && abs(extent.z-3)<0.001 && importer.phases==["created","initializing","source","parsing","geometry","complete"],"extent":[extent.x,extent.y,extent.z],"phases":importer.phases])
                let source=try String(contentsOf:path,encoding:.utf8)
                ifcCase="IFC4 millimetres and nested placement";mark(ifcCase)
                let millimetres=source.replacingOccurrences(of:"IFC2X3",with:"IFC4").replacingOccurrences(of:".ELEMENT.",with:".NOTDEFINED.").replacingOccurrences(of:".LENGTHUNIT.,$,.METRE.",with:".LENGTHUNIT.,.MILLI.,.METRE.").replacingOccurrences(of:"#17,1.,2.",with:"#17,1000.,2000.").replacingOccurrences(of:"#18,#9,#7,3.",with:"#18,#9,#7,3000.").replacingOccurrences(of:"$,$,#15,#21",with:"$,$,#25,#21").replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:"#23=IFCCARTESIANPOINT((10000.,20000.,30000.));\n#24=IFCAXIS2PLACEMENT3D(#23,#7,#8);\n#25=IFCLOCALPLACEMENT(#15,#24);\nENDSEC;\nEND-ISO")
                let converted=try await importer.load(Data(millimetres.utf8),roomID:house.rooms[0].id,stageID:house.stages[0].id)
                let vertices=converted.flatMap{$0.mesh.vertices};let low=V3(vertices.map{$0.x}.min() ?? 0,vertices.map{$0.y}.min() ?? 0,vertices.map{$0.z}.min() ?? 0),high=V3(vertices.map{$0.x}.max() ?? 0,vertices.map{$0.y}.max() ?? 0,vertices.map{$0.z}.max() ?? 0)
                results.append(["test":"IFC4 millimetres and nested placement","passed":(low-V3(9.5,19,30)).length<0.001 && (high-V3(10.5,21,33)).length<0.001,"lower":[low.x,low.y,low.z],"upper":[high.x,high.y,high.z]])
                ifcCase="IFC rotated nested placement preserves metric axes";mark(ifcCase)
                let rotated=millimetres.replacingOccurrences(of:"#24=IFCAXIS2PLACEMENT3D(#23,#7,#8);",with:"#24=IFCAXIS2PLACEMENT3D(#23,#7,#26);\n#26=IFCDIRECTION((0.,1.,0.));")
                let turned=try await importer.load(Data(rotated.utf8),roomID:roomID,stageID:stageID)
                let turnedVertices=turned.flatMap{$0.mesh.vertices}
                let turnedLow=V3(turnedVertices.map{$0.x}.min() ?? 0,turnedVertices.map{$0.y}.min() ?? 0,turnedVertices.map{$0.z}.min() ?? 0)
                let turnedHigh=V3(turnedVertices.map{$0.x}.max() ?? 0,turnedVertices.map{$0.y}.max() ?? 0,turnedVertices.map{$0.z}.max() ?? 0)
                results.append(["test":"IFC rotated nested placement preserves metric axes","passed":(turnedLow-V3(9,19.5,30)).length<0.001 && (turnedHigh-V3(11,20.5,33)).length<0.001])
                ifcCase="IFC far-origin rebasing recovers project metres without house alignment";mark(ifcCase)
                let distant=millimetres.replacingOccurrences(of:"((10000.,20000.,30000.))",with:"((1000000000.,20000.,30000.))")
                let far=try await importer.load(Data(distant.utf8),roomID:roomID,stageID:stageID)
                guard let farReference=importer.coordinateReference else{throw HouseError.message("Missing reversible IFC source frame.")}
                let farPoints=far.flatMap{$0.mesh.vertices}.map{$0+farReference.originMetres}
                let farLow=V3(farPoints.map{$0.x}.min() ?? 0,farPoints.map{$0.y}.min() ?? 0,farPoints.map{$0.z}.min() ?? 0)
                let farHigh=V3(farPoints.map{$0.x}.max() ?? 0,farPoints.map{$0.y}.max() ?? 0,farPoints.map{$0.z}.max() ?? 0)
                results.append(["test":"IFC far-origin rebasing recovers project metres without house alignment","passed":farReference.valid && farReference.rebased && farReference.sourceLengthUnit=="MILLI METRE" && (farLow-V3(999999.5,19,30)).length<0.001 && (farHigh-V3(1000000.5,21,33)).length<0.001 && far.allSatisfy{$0.mesh.valid}])
                ifcCase="IFC CRS rotation scale and offsets are retained without altering project geometry";mark(ifcCase)
                let georeferenced=distant.replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:"#30=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n#31=IFCPROJECTEDCRS('EPSG:32632','Synthetic CRS','WGS84',$,'UTM','32N',#30);\n#32=IFCMAPCONVERSION(#10,#31,500000.25,4200000.5,12.,0.,1.,0.001);\nENDSEC;\nEND-ISO")
                let mapped=try await importer.load(Data(georeferenced.utf8),roomID:roomID,stageID:stageID)
                guard let reference=importer.coordinateReference,let conversion=reference.mapConversions.first else{throw HouseError.message("Missing IFC georeference metadata.")}
                results.append(["test":"IFC CRS rotation scale and offsets are retained without altering project geometry","passed":reference.mapConversions.count==1 && conversion.expressID==32 && conversion.values["Eastings"]==500000.25 && conversion.values["Northings"]==4200000.5 && conversion.values["Scale"]==0.001 && conversion.values["XAxisAbscissa"]==0 && conversion.values["XAxisOrdinate"]==1 && conversion.targetCRS["Name"]=="EPSG:32632" && conversion.targetCRS["MapUnit"]=="METRE" && mapped.map{$0.mesh}==far.map{$0.mesh} && reference.originMetres==farReference.originMetres])
                ifcCase="IFC4.3 scaled CRS stays documentary and preserves source metric geometry";mark(ifcCase)
                var scaledPassed=true
                for schema in ["IFC4X3","IFC4X3_ADD2"] {
                    let scaled=georeferenced.replacingOccurrences(of:"IFC4",with:schema).replacingOccurrences(of:"IFCMAPCONVERSION(#10,#31,500000.25,4200000.5,12.,0.,1.,0.001)",with:"IFCMAPCONVERSIONSCALED(#10,#31,500000.25,4200000.5,12.,0.,1.,0.001,0.9996,1.0004,1.002)")
                    let output=try await importer.load(Data(scaled.utf8),roomID:roomID,stageID:stageID)
                    guard let coordinates=importer.coordinateReference,let conversion=coordinates.mapConversions.first,let properties=importer.propertyGraph else{throw HouseError.message("Missing IFC4.3 conversion metadata.")}
                    let decoded=try JSONDecoder().decode(IFCCoordinateReference.self,from:JSONEncoder().encode(coordinates))
                    let graph=try JSONSerialization.jsonObject(with:properties.data) as! [String:Any]
                    let points=output.flatMap{$0.mesh.vertices}.map{$0+coordinates.originMetres}
                    let low=V3(points.map{$0.x}.min() ?? 0,points.map{$0.y}.min() ?? 0,points.map{$0.z}.min() ?? 0)
                    let high=V3(points.map{$0.x}.max() ?? 0,points.map{$0.y}.max() ?? 0,points.map{$0.z}.max() ?? 0)
                    scaledPassed = scaledPassed && coordinates.valid && decoded==coordinates && coordinates.sourceSchema==schema && graph["sourceSchema"] as? String==schema && coordinates.mapConversions.count==1 && conversion.values["FactorX"]==0.9996 && conversion.values["FactorY"]==1.0004 && conversion.values["FactorZ"]==1.002 && conversion.values["Scale"]==0.001 && conversion.targetCRS["MapUnit"]=="METRE" && (low-V3(999999.5,19,30)).length<0.001 && (high-V3(1000000.5,21,33)).length<0.001
                }
                results.append(["test":ifcCase,"passed":scaledPassed,"schemaCases":2,"crsAppliedToGeometry":false])
                ifcCase="IFC out-of-envelope coordinates refuse atomically and importer recovers";mark(ifcCase)
                var refused=false
                let excessive=distant.replacingOccurrences(of:"1000000000.,20000.",with:"10000000000000.,20000.")
                do {_ = try await importer.load(Data(excessive.utf8),roomID:roomID,stageID:stageID)}catch{refused=true}
                let recovered=try await importer.load(input,roomID:roomID,stageID:stageID)
                let retainedInput=try Data(contentsOf:path)
                results.append(["test":"IFC out-of-envelope coordinates refuse atomically and importer recovers","passed":refused && !recovered.isEmpty && retainedInput==input])

                ifcCase="IFC raw properties storeys and source unit graph";mark(ifcCase)
                let additions="""
                #40=IFCBUILDINGSTOREY('2J$yPqHBD2TuLf$X2etp$2',#5,'Upper storey',$,$,#15,$,$,.ELEMENT.,3000.);
                #41=IFCRELCONTAINEDINSPATIALSTRUCTURE('3J$yPqHBD2TuLf$X2etp$3',#5,$,$,(#22),#40);
                #42=IFCPROPERTYSINGLEVALUE('Circuit',$,IFCLABEL('=literal source label'),$);
                #43=IFCPROPERTYSINGLEVALUE('NominalDiameter',$,IFCLENGTHMEASURE(25.),#11);
                #44=IFCPROPERTYSET('0J$yPqHBD2TuLf$X2etp$4',#5,'Pset_HouseXray',$,(#42,#43));
                #45=IFCRELDEFINESBYPROPERTIES('1J$yPqHBD2TuLf$X2etp$5',#5,$,$,(#22),#44);
                """
                let withProperties=millimetres.replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:additions+"\nENDSEC;\nEND-ISO")
                var propertyHouse=House.empty("IFC property handoff")
                let propertyRoom=propertyHouse.rooms[0].id,propertyStage=Stage(name:"Source design",kind:.planned,phase:.other)
                propertyHouse.stages.append(propertyStage)
                let propertyInput=Data(withProperties.utf8),propertyFeatures=try await importer.load(propertyInput,roomID:propertyRoom,stageID:propertyStage.id)
                guard let graph=importer.propertyGraph,let propertyCoordinates=importer.coordinateReference else{throw HouseError.message("Missing source property graph.")}
                let document=try JSONSerialization.jsonObject(with:graph.data) as! [String:Any],records=document["records"] as! [[String:Any]]
                let rawDiameter=(records.first{$0["expressID"] as? Int==43}?["fields"] as? [String:Any])?["NominalValue"] as? [String:Any]
                let storeys=document["storeys"] as! [[String:Any]]
                results.append(["test":"Pinned IFC properties preserve raw units storeys relationships and source object identity","passed":graph.summary.products==2 && graph.summary.convertedProducts==1 && graph.summary.representedProducts==1 && graph.summary.storeys==1 && graph.matches(propertyFeatures) && rawDiameter?["value"] as? Double==25 && storeys.first?["elevation"] as? Double==3000 && records.contains{$0["expressID"] as? Int==41} && records.contains{$0["expressID"] as? Int==45} && propertyFeatures.allSatisfy{$0.ifcObject?.expressID==22}])
                await check("IFC property boundary refuses forged summaries references identities and byte budgets") {
                    for fault in 0..<9 {
                        var bad=document
                        if fault==0 {var summary=bad["summary"] as! [String:Any];summary["convertedProducts"]=99;bad["summary"]=summary}
                        if fault==1 {var rows=bad["records"] as! [[String:Any]];rows.append(rows[0]);bad["records"]=rows}
                        if fault==2 {bad["sourceSHA256"]=String(repeating:"0",count:64)}
                        if fault==3 {var products=bad["products"] as! [[String:Any]];products[0]["guidStatus"]="duplicate";bad["products"]=products}
                        if fault==4 {var rows=bad["records"] as! [[String:Any]];rows[0]["fields"]=["Missing":["type":5,"value":99999]];bad["records"]=rows}
                        if fault==5 {bad["extra"]=String(repeating:"é",count:2049)}
                        if fault>=6 {
                            var rows=bad["records"] as! [[String:Any]]
                            let index=rows.firstIndex{$0["expressID"] as? Int==11}!
                            if fault==6 {rows[index]["derivedFields"]=[] as [String]}
                            if fault==7 {var fields=rows[index]["fields"] as! [String:Any];fields["Dimensions"]=["type":5,"value":99999];rows[index]["fields"]=fields}
                            if fault==8 {rows[index]["typeName"]="IfcOtherType"}
                            bad["records"]=rows
                        }
                        do{_=try IFCProperties.decode(bad,sourceSHA256:graph.sourceSHA256);return false}catch{}
                    }
                    var changed=propertyFeatures;changed[0].ifcObject?.expressID=40
                    return !graph.matches(changed) && graph.matches(propertyFeatures)
                }
                await check("IFC property sidecars survive archive source edits and independent semantic handoff") {
                    let originalKey=try repo.put(propertyInput,ext:"ifc"),propertyReference=try graph.store(in:repo)
                    let drawing=Drawing(name:"Properties.ifc",asset:originalKey)
                    propertyHouse.drawings=[drawing]
                    let imported=try IFCSourceEvidence.applying(propertyFeatures,source:drawing,stage:propertyStage,roomID:propertyRoom,coordinates:propertyCoordinates,properties:propertyReference,to:propertyHouse)
                    try repo.save(imported)
                    let archive=try Exporter.archive(imported,repo:repo),target=try Repository(root:folder.appendingPathComponent("ifc-property-restore")),restored=try Exporter.restore(archive,repo:target)
                    guard restored.drawings==imported.drawings,restored.features==imported.features,try target.read(originalKey)==propertyInput,try target.read(propertyReference.asset)==graph.data,try target.integrity(restored)==2 else{return false}
                    var changed=imported;changed.drawings[0].ifcProperties?.asset=String(repeating:"0",count:64)+".json"
                    guard DerivedEvidence.currentIDs(changed).isDisjoint(with:Set(imported.features.map{$0.id})) else{return false}
                    do{try repo.verifyIFCProperties(changed);return false}catch{}
                    changed=imported;changed.features[0].ifcObject?.expressID=40
                    do{try repo.verifyIFCProperties(changed);return false}catch{}
                    changed=imported;changed.drawings[0].notes="Owner source note"
                    try repo.save(changed)
                    guard try repo.read(propertyReference.asset)==graph.data else{return false}
                    var options=SceneOptions();options.stage=propertyStage.id
                    try Data(contentsOf:archive).write(to:mainRepo.root.appendingPathComponent("ifc-properties.hxray"))
                    try Data(contentsOf:Exporter.glb(imported,options:options)).write(to:mainRepo.root.appendingPathComponent("ifc-properties.glb"))
                    try Data(contentsOf:Exporter.semanticCSV(imported)).write(to:mainRepo.root.appendingPathComponent("ifc-properties.csv"))
                    return true
                }
                let omitted="""
                #47=IFCBUILDINGELEMENTPROXY('1J$yPqHBD2TuLf$X2etp$1',#5,'Point-only source product',$,$,#15,#48,$,.NOTDEFINED.);
                #48=IFCPRODUCTDEFINITIONSHAPE($,$,(#50));
                #49=IFCGEOMETRICSET((#6));
                #50=IFCSHAPEREPRESENTATION(#10,'Body','GeometricSet',(#49));
                """
                ifcCase="IFC point-only representations and duplicate GUIDs remain distinct source products";mark(ifcCase)
                let partial=withProperties.replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:omitted+"\nENDSEC;\nEND-ISO")
                let partialFeatures=try await importer.load(Data(partial.utf8),roomID:propertyRoom,stageID:propertyStage.id)
                guard let partialGraph=importer.propertyGraph else{throw HouseError.message("Missing partial-conversion census.")}
                results.append(["test":"IFC point-only representations and duplicate GUIDs remain distinct source products","passed":partialGraph.summary.products==3 && partialGraph.summary.representedProducts==2 && partialGraph.summary.convertedProducts==1 && partialGraph.summary.unconvertedRepresentedProducts==1 && partialGraph.summary.duplicateGUIDs==2 && partialGraph.matches(partialFeatures) && partialGraph.objects[22]?.guidStatus=="duplicate" && partialGraph.objects[47]?.guidStatus=="duplicate"])
                ifcCase="IFC malformed and missing GUIDs retain EXPRESS identities without merging";mark(ifcCase)
                var warningsPassed=true
                for (replacement,status) in [("'bad-guid'","malformed"),("$","missing")] {
                    let malformed=partial.replacingOccurrences(of:"'1J$yPqHBD2TuLf$X2etp$1'",with:replacement)
                    let output=try await importer.load(Data(malformed.utf8),roomID:propertyRoom,stageID:propertyStage.id)
                    warningsPassed = warningsPassed && importer.propertyGraph?.objects[22]?.guidStatus==status && importer.propertyGraph?.objects[47]?.guidStatus==status && !output.isEmpty
                }
                results.append(["test":"IFC malformed and missing GUIDs retain EXPRESS identities without merging","passed":warningsPassed])
                ifcCase="IFC conversion-based feet and inches retain raw factors and produce metric geometry";mark(ifcCase)
                var conversionUnitsPassed=true
                for (name,factor) in [("foot",0.3048),("inch",0.0254)] {
                    let units="""
                    #51=IFCDIMENSIONALEXPONENTS(1,0,0,0,0,0,0);
                    #52=IFCMEASUREWITHUNIT(IFCLENGTHMEASURE(\(factor)),#11);
                    #53=IFCCONVERSIONBASEDUNIT(#51,.LENGTHUNIT.,'\(name)',#52);
                    """
                    let convertedSource=source.replacingOccurrences(of:"IFC2X3",with:"IFC4").replacingOccurrences(of:".ELEMENT.",with:".NOTDEFINED.").replacingOccurrences(of:"IFCUNITASSIGNMENT((#11,#12))",with:"IFCUNITASSIGNMENT((#53,#12))").replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:units+"\nENDSEC;\nEND-ISO")
                    let unitFeatures=try await importer.load(Data(convertedSource.utf8),roomID:propertyRoom,stageID:propertyStage.id)
                    let points=unitFeatures.flatMap{$0.mesh.vertices},size=V3((points.map{$0.x}.max() ?? 0)-(points.map{$0.x}.min() ?? 0),(points.map{$0.y}.max() ?? 0)-(points.map{$0.y}.min() ?? 0),(points.map{$0.z}.max() ?? 0)-(points.map{$0.z}.min() ?? 0))
                    guard let unitGraph=importer.propertyGraph else{throw HouseError.message("Missing conversion-based source units.")}
                    let unitDocument=try JSONSerialization.jsonObject(with:unitGraph.data) as! [String:Any],unitRecords=unitDocument["records"] as! [[String:Any]]
                    let retainedFactor=(unitRecords.first{$0["expressID"] as? Int==52}?["fields"] as? [String:Any])?["ValueComponent"] as? [String:Any]
                    conversionUnitsPassed = conversionUnitsPassed && (size-V3(factor,2*factor,3*factor)).length<0.00001 && importer.coordinateReference?.sourceLengthUnit==name && retainedFactor?["value"] as? Double==factor
                }
                results.append(["test":"IFC conversion-based feet and inches retain raw factors and produce metric geometry","passed":conversionUnitsPassed])

            }catch{results.append(["test":ifcCase,"passed":false,"error":error.localizedDescription])}
            do {
                let fixture=try SimulatedCapture.make(repo:mainRepo)
                await check("Photo triangulation uses an independent third view and rejects disagreement"){
                    let expected=V3(0,2,1.1)
                    var controls=try [0,4,8].map {index -> PhotoControl in
                        let o=fixture.observations[index];guard let projected=TextureBuilder.project(expected,through:o) else{throw HouseError.message("Synthetic point outside image.")}
                        return PhotoControl(observationID:o.id,u:projected.0.u,v:projected.0.v)
                    }
                    let result=try PhotoTriangulation.locate(controls,house:fixture,segment:fixture.segments[0])
                    guard (result-expected).length<1e-8 else{return false}
                    controls[2].v+=0.1
                    do{_=try PhotoTriangulation.locate(controls,house:fixture,segment:fixture.segments[0]);return false}catch{return true}
                }
                await check("Photo-traced foreground curves ignore background depth and preserve independent source tracks") {
                    var curveHouse=fixture;var registration=Rigid();registration.values[3]=0.3;registration.values[7]=0.2;registration.values[11]=0.1
                    curveHouse.segments[0].registration=registration
                    let expected=[V3(-0.3,1.2,1),V3(0,1.25,1.2),V3(0.3,1.2,1.4)]
                    let tracks=try expected.map{point in try [0,4,8].map{index -> PhotoControl in
                        let o=fixture.observations[index];guard let uv=CameraProjection.project(point,through:o)?.0 else{throw HouseError.message("Curve fixture outside image")}
                        return PhotoControl(observationID:o.id,u:uv.u,v:uv.v)
                    }}
                    var feature=try PhotoTriangulation.curve(tracks,house:curveHouse,segment:curveHouse.segments[0],name:"Foreground curve",trade:.lowVoltage,visibleIntervalsConfirmed:true)
                    feature.service=ServiceDetails(classification:.lowVoltage,observedLabel:"=literal café label",port:"P-24",installationDate:"2024-02-29",confidence:.unconfirmed)
                    guard feature.isPhotoCurve,feature.mesh.triangles.isEmpty,zip(feature.route,expected).allSatisfy({($0.0-$0.1).length<1e-8}),feature.pointTracks?.map({$0.controls})==tracks else{return false}
                    curveHouse.features=[feature];try curveHouse.validate()
                    let bytes=try JSONEncoder().encode(curveHouse)
                    let package=try Exporter.archive(curveHouse,repo:mainRepo),targetRepo=try Repository(root:folder.appendingPathComponent("curve-restore"))
                    let restored=try Exporter.restore(package,repo:targetRepo)
                    try ArchiveViewer.html(curveHouse).write(to:mainRepo.root.appendingPathComponent("photo-curve-viewer.html"))
                    guard restored.features==curveHouse.features,restored.connections.isEmpty,restored.observations==fixture.observations else{return false}
                    let line=SceneBuilder.geometry(feature.mesh,connectedLine:true)
                    guard line.elements.count==1,line.elements[0].primitiveType == .line,line.elements[0].primitiveCount==2 else{return false}
                    let canonical=Exporter.canonicalFeatures(curveHouse,options:SceneOptions())
                    guard canonical.count==1,canonical[0].isPhotoCurve,zip(canonical[0].route,expected).allSatisfy({($0.0-registration.apply($0.1)).length<1e-8}) else{return false}
                    let glb=try Exporter.glb(curveHouse,options:SceneOptions()),target=mainRepo.root.appendingPathComponent("photo-curve.glb")
                    try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:glb,to:target)
                    for mode in 0..<5 {
                        var samples=tracks,changed=curveHouse
                        if mode==0{samples[1][2].v+=0.1}
                        if mode==1{samples=[tracks[0]]}
                        if mode==2{changed.observations[0].tracking="limited"}
                        if mode==4{samples[1]=try [1,5,7].map{index -> PhotoControl in
                            let o=fixture.observations[index];guard let uv=CameraProjection.project(expected[1],through:o)?.0 else{throw HouseError.message("Alternate curve view outside image")}
                            return PhotoControl(observationID:o.id,u:uv.u,v:uv.v)
                        }}
                        do{_=try PhotoTriangulation.curve(samples,house:changed,segment:changed.segments[0],name:"Invalid",trade:.unknown,visibleIntervalsConfirmed:mode != 3);return false}catch{}
                    }
                    return try JSONDecoder().decode(House.self,from:bytes)==curveHouse && mainRepo.integrity(fixture)==fixture.assets.count
                }
                await check("Photograph point provenance refuses missing and cross-session originals") {
                    let controls=[0,4,8].map{PhotoControl(observationID:fixture.observations[$0].id,u:0.5,v:0.5)}
                    var candidate=fixture
                    candidate.features=[Feature(name:"Provenance contract",trade:.unknown,roomID:fixture.rooms[0].id,stageID:fixture.segments[0].stageID,kind:.synthetic,
                        mesh:Mesh(vertices:[V3(0,2,1)],triangles:[]),sourceIDs:controls.map{$0.observationID},segmentID:fixture.segments[0].id,pointTracks:[PointTrack(controls:controls)])]
                    try candidate.validate()
                    let bytes=try JSONEncoder().encode(candidate)
                    for fault in 0..<3 {
                        var changed=try JSONDecoder().decode(House.self,from:bytes)
                        if fault==0 {
                            let missing=UUID();changed.features[0].sourceIDs.append(missing)
                            changed.features[0].pointTracks![0].controls[0].observationID=missing
                        }else if fault==1 {
                            var other=changed.segments[0];other.id=UUID();changed.segments.append(other)
                            changed.observations[0].segmentID=other.id
                        }else {changed.features[0].sourceIDs=[]}
                        do{try changed.validate();return false}catch{}
                    }
                    let restored=try JSONDecoder().decode(House.self,from:bytes);try restored.validate()
                    return restored.features==candidate.features && restored.observations==fixture.observations
                }
                let feature=try await Reconstruction.fuse(house:fixture,segment:fixture.segments[0],repo:mainRepo){_ in}
                let surface=try await SurfaceReconstruction.build(house:fixture,segment:fixture.segments[0],repo:mainRepo){_ in}
                let resumedSurface=try await SurfaceReconstruction.build(house:fixture,segment:fixture.segments[0],repo:mainRepo){_ in}
                results.append(["test":"Native surface checkpoint reload produces identical geometry","passed":resumedSurface.mesh==surface.mesh && resumedSurface.sourceIDs==surface.sourceIDs])
                let surfaceError=surface.mesh.vertices.map{abs($0.y-2)}.max() ?? .infinity
                results.append(["test":"Native signed-distance surface fusion","passed":surface.mesh.valid && surface.mesh.triangles.count>300 && surfaceError<0.003,"vertices":surface.mesh.vertices.count,"maxPlaneErrorMetres":surfaceError,"syntheticOnly":true])
                var pointHouse=fixture;pointHouse.features=[feature]
                let pointGLB=try Exporter.glb(pointHouse,options:SceneOptions()),pointUSD=try Exporter.usdz(pointHouse,options:SceneOptions())
                for (from,name) in [(pointGLB,"points.glb"),(pointUSD,"points.usdz")]{let target=mainRepo.root.appendingPathComponent(name);try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:from,to:target)}
                let error=feature.mesh.vertices.map{abs($0.y-2)}.max() ?? .infinity
                var renamed=fixture;renamed.features[0].name="Renamed construction surface";renamed.features[0].hidden=true
                let coverage=try CoverageAnalyzer.analyze(house:renamed,segment:renamed.segments[0],repo:mainRepo)
                let textured=try TextureBuilder.build(house:renamed,segment:renamed.segments[0],repo:mainRepo)
                var candidate=fixture;candidate.features=textured
                let glb=try Exporter.glb(candidate,options:SceneOptions());try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("textured.glb"));try FileManager.default.copyItem(at:glb,to:mainRepo.root.appendingPathComponent("textured.glb"))
                let usd=try Exporter.usdz(candidate,options:SceneOptions());try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("textured.usdz"));try FileManager.default.copyItem(at:usd,to:mainRepo.root.appendingPathComponent("textured.usdz"))
                results.append(["test":"Simulated camera to fusion and photo texture pipeline","passed":feature.mesh.vertices.count>100 && error<0.003 && coverage.sampledPatches>0 && textured.allSatisfy{!$0.hidden && $0.resolvedGeometrySource == .photoTexture} && textured.contains{$0.texture != nil},"points":feature.mesh.vertices.count,"maxPlaneErrorMetres":error,"syntheticOnly":true])
                mark("Integrated capture processing and interrupted publication")
                try mainRepo.save(fixture)
                var interrupted=false
                do {_ = try await CaptureProcessing.build(house:fixture,segmentID:fixture.segments[0].id,repo:mainRepo,checkpoint:{stage in if stage=="surfaces-prepared" {throw CancellationError()}}){label,_ in mark("Interrupted pipeline: "+label)}}
                catch is CancellationError {interrupted=true}
                let before=try mainRepo.all().first{$0.id==fixture.id}
                let processed=try await CaptureProcessing.build(house:fixture,segmentID:fixture.segments[0].id,repo:mainRepo){label,_ in mark("Integrated pipeline: "+label)}
                let report=processed.processingReports.last!
                let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(processed));try restored.validate()
                results.append(["test":"Integrated capture processing retains originals and does not publish an interrupted candidate","passed":interrupted && before?.observations==fixture.observations && before?.features==fixture.features && processed.observations==fixture.observations && restored.processingReports==processed.processingReports && report.steps.count==6 && report.steps.contains{$0.name=="Triangle surfaces" && $0.passed} && report.steps.contains{$0.name=="Photo textures" && $0.passed},"steps":report.steps.map{["name":$0.name,"passed":$0.passed,"detail":$0.detail] as [String:Any]}])
                await check("Capture queue recovers running work, preserves owner pause and deduplicates published results") {
                    let queue=try Repository(root:folder.appendingPathComponent("capture-queue"));try queue.save(fixture)
                    let signature=try CaptureWork.fingerprint(house:fixture,segmentID:fixture.segments[0].id)
                    var work=CaptureWork(projectID:fixture.id,segmentID:fixture.segments[0].id,inputFingerprint:signature)
                    work.state = .running;work.attempts=1;try work.save(queue)
                    let interrupted=try CaptureWork.restore(repo:queue,houses:[fixture])
                    guard interrupted.count==1,interrupted[0].state == .waitingForForeground else{return false}
                    work.state = .paused;try work.save(queue)
                    guard try CaptureWork.restore(repo:queue,houses:[fixture])[0].state == .paused else{return false}
                    var published=processed;published.processingReports[0].jobID=work.id
                    try queue.save(published);work.state = .running;try work.save(queue)
                    let recovered=AppModel(root:queue.root)
                    guard recovered.captureJobs.count==1,[CaptureWork.State.succeeded,.needsAttention].contains(recovered.captureJobs[0].state),!recovered.busy else{return false}
                    guard try CaptureWork.fingerprint(house:published,segmentID:work.segmentID)==signature else{return false}
                    recovered.processCapture(projectID:fixture.id,segmentID:work.segmentID,automatic:true)
                    guard recovered.captureJobs.count==1,recovered.captureJobs[0].id==work.id else{return false}
                    recovered.processCapture(projectID:fixture.id,segmentID:work.segmentID)
                    guard recovered.captureJobs.count==1,recovered.captureJobs[0].id != work.id,recovered.captureJobs[0].state == .waitingForForeground else{return false}
                    let replacement=recovered.captureJobs[0].id
                    recovered.pauseCaptureJob(replacement)
                    return AppModel(root:queue.root).captureJobs.first?.state == .paused
                }


            }catch{results.append(["test":"Simulated camera to fusion and photo texture pipeline","passed":false,"error":error.localizedDescription])}
            do {
                guard let bundle=Bundle.main.url(forResource:"IFC",withExtension:nil) else{throw HouseError.message("Simulation bundle missing.")}
                let simulated=try Exporter.restore(bundle.appendingPathComponent("synthetic-house.hxray"),repo:mainRepo)
                let entries=try StreamingArchive.index(bundle.appendingPathComponent("synthetic-house.hxray"))
                results.append(["test":"Paired three-room camera archive without oracle geometry","passed":simulated.rooms.count==3 && simulated.stages.count==2 && simulated.observations.count==144 && simulated.features.isEmpty && entries["oracle.json"]==nil,"syntheticOnly":true])
                let first=simulated.segments[0];let surface=try await SurfaceReconstruction.build(house:simulated,segment:first,repo:mainRepo){_ in}
                var candidate=simulated;candidate.features=[surface]
                let url=try Exporter.glb(candidate,options:SceneOptions(room:first.roomID));let target=mainRepo.root.appendingPathComponent("house-surface.glb");try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:url,to:target)
                results.append(["test":"Noisy simulated house capture to native surface","passed":surface.mesh.valid && surface.mesh.triangles.count>300,"vertices":surface.mesh.vertices.count,"precisionQualified":false])
            }catch{results.append(["test":"Paired simulated house integration","passed":false,"error":error.localizedDescription])}
            mark("Direct Metal movie target, color order, orientation and depth")
            do {results.append(try await movieTargetReport(root:mainRepo.root))}
            catch {results.append(["test":"Direct Metal movie target, color order, orientation and depth","passed":false,"error":error.localizedDescription])}
            await check("Developer tour command uses production planning, verified originals and deterministic output") {
                let directory=folder.appendingPathComponent("developer-tour"),input=directory.appendingPathComponent("input")
                try FileManager.default.createDirectory(at:input.appendingPathComponent("assets"),withIntermediateDirectories:true)
                let sample=DemoFactory.make(),encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                let bytes=try encoder.encode(sample),hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                try DurableFiles.write(bytes,to:input.appendingPathComponent("house.json"))
                var request=DeveloperCommands.Request(schema:1,command:"tour",houseSHA256:hash,preset:"before-after",duration:5)
                try DurableFiles.write(try encoder.encode(request),to:directory.appendingPathComponent("request.json"))
                let report=try DeveloperCommands.execute(folder:directory)
                let first=try Data(contentsOf:directory.appendingPathComponent("output/tour.json"))
                let decoded=try JSONDecoder().decode(TourPlan.self,from:first)
                let expected=TourDirector.plan(sample,duration:5,preset:.beforeAfter)
                guard (report["passed"] as? Bool)==true,(report["frames"] as? Int)==150,
                    try encoder.encode(decoded)==encoder.encode(expected),
                    let previews=report["previews"] as? [String],!previews.isEmpty,
                    previews.allSatisfy({UIImage(contentsOfFile:directory.appendingPathComponent("output/"+$0).path)?.size==CGSize(width:640,height:360)}) else{return false}
                request.houseSHA256=String(repeating:"0",count:64)
                try DurableFiles.write(try encoder.encode(request),to:directory.appendingPathComponent("request.json"))
                do {_=try DeveloperCommands.execute(folder:directory);return false}catch{}
                let emptyFolder=folder.appendingPathComponent("developer-tour-empty"),emptyInput=emptyFolder.appendingPathComponent("input")
                try FileManager.default.createDirectory(at:emptyInput.appendingPathComponent("assets"),withIntermediateDirectories:true)
                let empty=try encoder.encode(House.empty("No observed viewpoint"))
                request.houseSHA256=SHA256.hash(data:empty).map{String(format:"%02x",$0)}.joined()
                try DurableFiles.write(empty,to:emptyInput.appendingPathComponent("house.json"))
                try DurableFiles.write(try encoder.encode(request),to:emptyFolder.appendingPathComponent("request.json"))
                let refused=try DeveloperCommands.execute(folder:emptyFolder)
                guard (refused["passed"] as? Bool)==false,let exclusions=refused["excluded"] as? [String],!exclusions.isEmpty else{return false}
                return try Data(contentsOf:input.appendingPathComponent("house.json"))==bytes && Data(contentsOf:directory.appendingPathComponent("output/tour.json"))==first
            }
            mark("Native reconstruction command")
            do {
                let directory=folder.appendingPathComponent("developer-reconstruction"),input=directory.appendingPathComponent("input")
                let source=try Repository(root:input),fixture=try SimulatedCapture.make(repo:source),verified=try source.integrity(fixture)
                let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
                let bytes=try encoder.encode(fixture),hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                try DurableFiles.write(bytes,to:input.appendingPathComponent("house.json"))
                let request=DeveloperCommands.ReconstructionRequest(schema:1,command:"reconstruct",houseSHA256:hash,kind:"points",segmentID:fixture.segments[0].id)
                try DurableFiles.write(try encoder.encode(request),to:directory.appendingPathComponent("request.json"))
                let report=try await DeveloperCommands.reconstruct(folder:directory)
                let restoredRepo=try Repository(root:folder.appendingPathComponent("developer-reconstruction-restored"))
                let restored=try Exporter.restore(directory.appendingPathComponent("output/reconstruction.hxray"),repo:restoredRepo)
                guard (report["passed"] as? Bool)==true,restored.id != fixture.id,restored.observations==fixture.observations,
                    restored.features.count==fixture.features.count+1,restored.features.last?.resolvedGeometrySource == .depthPoints,
                    restored.features.last?.mesh.vertices.isEmpty==false,try source.integrity(fixture)==verified,
                    try Data(contentsOf:input.appendingPathComponent("house.json"))==bytes else{throw HouseError.message("Native reconstruction command lost original evidence or failed its separate restore.")}
                // Private CI input for the actual command-process test. It is
                // deliberately absent from the public artifact copy list.
                let archive=try Exporter.archive(fixture,repo:source),target=mainRepo.root.appendingPathComponent("command-capture.hxray")
                try? FileManager.default.removeItem(at:target);try FileManager.default.moveItem(at:archive,to:target)
                results.append(["test":"Native reconstruction command preserves originals and exports a separately restorable candidate","passed":true,"originalAssetsVerified":verified,"vertices":restored.features.last!.mesh.vertices.count,"physicalQualification":false])
            }catch {results.append(["test":"Native reconstruction command preserves originals and exports a separately restorable candidate","passed":false,"error":error.localizedDescription])}
            if includeMovie || ProcessInfo.processInfo.arguments.contains("--video-test") {
                mark("100-space scene capacity")
                do{results.append(try await largeSceneReport(repo:mainRepo))}
                catch{results.append(["test":"100-space two-stage capacity and native streamed render","passed":false,"error":error.localizedDescription])}
                var encoderRecoveries:[[String:Any]]=[]
                do {
                    mark("1080p30 movie encode and cache reuse")
                    let started=ProcessInfo.processInfo.systemUptime
                    let movie=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:10,width:1920,height:1080,encoderRecovery:{encoderRecoveries.append($0.diagnostics)}){model.progress=$0}
                    if let issue=await MovieExporter.clipIssue(movie,frames:300,width:1920,height:1080,decodeAllFrames:true) {throw HouseError.message("Complete movie decode: "+issue)}
                    let directory=repo.root.appendingPathComponent("tours"),all=FileManager.default.enumerator(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])!
                    var dates:[URL:Date]=[:]
                    for case let url as URL in all where url.pathExtension=="mp4" {dates[url]=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate}
                    _=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:10,width:1920,height:1080){_ in}
                    let reused=try !dates.isEmpty && dates.allSatisfy{try $0.key.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate==$0.value}
                    let target=mainRepo.root.appendingPathComponent("test-tour.mp4");try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:movie,to:target)
                    let generator=AVAssetImageGenerator(asset:AVURLAsset(url:target));let frame=try await generator.image(at:CMTime(seconds:1,preferredTimescale:30))
                    try UIImage(cgImage:frame.image).pngData()?.write(to:mainRepo.root.appendingPathComponent("test-tour-frame.png"))
                    results.append(["test":"1080p30 MP4 encode, decode and verified chunk reuse","passed":reused,"width":1920,"height":1080,"durationSeconds":10,"decodedFrames":300,"seconds":ProcessInfo.processInfo.systemUptime-started,"recoveredEncoderStalls":encoderRecoveries])
                }catch{
                    var failure:[String:Any]=["test":"1080p30 MP4 encode, decode and verified chunk reuse","passed":false,"error":error.localizedDescription]
                    if let timeout=error as? MovieEncoderTimeout {failure["encoderDiagnostics"]=timeout.diagnostics}
                    failure["encoderRetryEvents"]=encoderRecoveries
                    results.append(failure)
                }
                mark("Movie interruption and final-publication recovery")
                do {results.append(try await movieRecoveryReport(repo:Repository(root:folder.appendingPathComponent("movie-recovery"))))}
                catch{results.append(["test":"Movie interruption and final-publication recovery","passed":false,"error":error.localizedDescription])}
                mark("Bounded movie encoder retry")
                do {results.append(try await movieEncoderRetryReport(root:folder.appendingPathComponent("movie-encoder-retry")))}
                catch{results.append(["test":"Movie encoder retries one unfinished shot and stops after a second stall","passed":false,"error":error.localizedDescription])}
            }
        }catch{results.append(["test":"Test harness setup","passed":false,"error":error.localizedDescription])}
        #if targetEnvironment(simulator)
        let platform="iPhone simulator"
        #else
        let platform="physical iPhone"
        #endif
        let report:[String:Any]=["deviceModel":UIDevice.current.model,"systemVersion":UIDevice.current.systemVersion,"physicalMemoryBytes":ProcessInfo.processInfo.physicalMemory,"processMemory":memorySample(),"elapsedSeconds":ProcessInfo.processInfo.systemUptime-runStarted,"sourceRevision":Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "local","platform":platform,"date":ISO8601DateFormatter().string(from:Date()),"tests":results,"passed":results.allSatisfy{($0["passed"] as? Bool)==true},"fieldAccuracyValidated":false,"precisionProfileEnabled":false]
        mark("Native diagnostics","completed")
        do{let bytes=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try bytes.write(to:mainRepo.root.appendingPathComponent("self-test.json"),options:.atomic)}catch{model.error=error.localizedDescription}
        try? FileManager.default.removeItem(at:folder)
    }
}

extension SelfTests {
    static func registrationChainReport() throws->[String:Any] {
        var house=House.empty("Analytic chained-session registration")
        let adapter=simd_double4x4(columns:(SIMD4(1,0,0,0),SIMD4(0,0,1,0),SIMD4(0,-1,0,0),SIMD4(0,0,0,1)))
        var expected:[simd_double4x4]=[],segments:[Segment]=[]
        for index in 0..<20 {
            let angle=Double(index)*0.37,axis=simd_normalize(SIMD3<Double>(1,2,3))
            var transform=simd_double4x4(simd_quatd(angle:angle,axis:axis))
            transform.columns.3=SIMD4(Double(index%4)*4.3,Double(index/4)*3.1,Double(index/4)*2.8,1)
            expected.append(transform)
            var segment=Segment(roomID:house.rooms[0].id,stageID:house.stages[index%2].id)
            if index==0 {segment.registration=Rigid(values:PoseRefinement.array(transform))}
            segments.append(segment)
        }
        var groups:[[UUID]]=[]
        for index in 1..<segments.count {
            var ids:[UUID]=[]
            for number in 0..<4 {
                let board=ReferenceBoard(name:"Analytic control",image:"test.png",pdf:"test.pdf")
                house.references.append(board);ids.append(board.id)
                var boardWorld=simd_double4x4(simd_quatd(angle:Double(number)*0.8,axis:SIMD3<Double>(0,0,1)))
                let centre=expected[index].columns.3
                let offset=SIMD4<Double>(Double(number%2)*2,Double(number/2)*1.5,Double(number)*0.7,0)
                boardWorld.columns.3=centre+offset
                for session in [index-1,index] {
                    let local=simd_inverse(adapter)*simd_inverse(expected[session])*boardWorld
                    segments[session].referencePoses.append(ReferencePose(boardID:board.id,matrix:PoseRefinement.array(local)))
                }
            }
            groups.append(ids)
        }
        house.segments=segments
        let witnesses=[V3(),V3(7,-3,2),V3(-5,4,6),V3(2,8,-1)]
        var worst=0.0,refused=0,scaleRefused=0
        for index in 1..<segments.count {
            let source=house.segments[index],anchor=house.segments[index-1]
            let (transform,residual,link)=try ReferenceRegistration.fit(source:source,anchor:anchor,house:house)
            let truth=Rigid(values:PoseRefinement.array(expected[index]))
            for point in witnesses {worst=max(worst,(transform.apply(point)-truth.apply(point)).length)}
            guard residual<1e-9 else{throw HouseError.message("Exact session controls acquired a registration residual.")}
            // The withheld board must not be fitted away, even after a long
            // chain of rotations and floor offsets has already been registered.
            var moved=source
            let check=link.boardIDs[2],position=moved.referencePoses.firstIndex{$0.boardID==check}!
            moved.referencePoses[position].matrix[3]+=0.08
            do {_=try ReferenceRegistration.fit(source:moved,anchor:anchor,house:house)}catch{refused+=1}
            var scaled=source
            let origin=source.referencePoses[0].matrix
            for pose in scaled.referencePoses.indices {for axis in [3,7,11] {
                scaled.referencePoses[pose].matrix[axis]=origin[axis]+(source.referencePoses[pose].matrix[axis]-origin[axis])*1.1
            }}
            do {_=try ReferenceRegistration.fit(source:scaled,anchor:anchor,house:house)}catch{scaleRefused+=1}
            house.segments[index].registration=transform;house.segments[index].registrationResidual=residual
            house.segments[index].registrationLink=link
        }
        guard worst<1e-8,refused==19,scaleRefused==19 else{throw HouseError.message("Chained registration changed the house frame or accepted moved/scaled controls.")}
        house=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(house))
        ReferenceRegistration.invalidateChangedInputs(&house)
        guard house.segments.allSatisfy({$0.registration != nil}) else{throw HouseError.message("Unchanged session registrations did not survive reload.")}
        // Change one original print dimension. Its child and all descendants
        // must lose the derived frame while every original pose remains intact.
        let originalPoses=house.segments.map{$0.referencePoses}
        let changed=house.references.firstIndex{$0.id==groups[0][0]}!
        house.references[changed].width+=0.01
        ReferenceRegistration.invalidateChangedInputs(&house)
        guard house.segments[0].registration != nil,
          house.segments.dropFirst().allSatisfy({$0.registration==nil && $0.registrationLink==nil}),
          house.segments.map({$0.referencePoses})==originalPoses else{throw HouseError.message("A changed reference retained stale descendant frames or altered original poses.")}
        return ["test":"Chained session registration preserves the house frame and invalidates descendants","passed":true,
            "sessions":20,"independentlyMovedControlsRefused":refused,"incorrectScaleRefused":scaleRefused,"descendantsInvalidated":19,
            "maximumAnalyticWitnessErrorMetres":worst,"physicalDeviceQualified":false,
            "limitations":"Exact analytic reference poses; not image-based house, sensor-scale or physical precision qualification."]
    }
    static func movieEncoderRetryReport(root:URL) async throws->[String:Any] {
        let repo=try Repository(root:root.appendingPathComponent("recover")),house=DemoFactory.make()
        func completedShots(_ repository:Repository)throws->[URL:String] {
            guard let files=FileManager.default.enumerator(at:repository.root.appendingPathComponent("tours"),includingPropertiesForKeys:[.contentModificationDateKey]) else{return [:]}
            var result:[URL:String]=[:]
            for case let url as URL in files where url.pathExtension=="mp4" && !url.lastPathComponent.contains("partial") {
                let date=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate!
                result[url]=try StreamingArchive.digest(url).sha+"|"+String(date.timeIntervalSince1970)
            }
            return result
        }
        func timeout()->MovieEncoderTimeout {
            // Inject the failure after real frame submission; no artificial
            // 15-second sleep or claim of observed encoder latency is needed.
            MovieEncoderTimeout(shot:1,frame:3,expectedFrames:50,width:320,height:180,writerStatus:AVAssetWriter.Status.writing.rawValue,waitedSeconds:15)
        }
        var finished=0,frames=0,retries=0,injected=false,retained:[URL:String]=[:]
        let movie=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:5,width:320,height:180,checkpoint:{phase in
            if phase=="shot-committed" {finished+=1;if finished==1 {retained=try completedShots(repo)}}
            if phase=="frame-encoded",finished==1 {
                frames+=1
                if frames==3 && !injected {injected=true;throw timeout()}
            }
        },encoderRecovery:{_ in retries+=1}){_ in}
        let after=try completedShots(repo)
        guard injected,retries==1,retained.count==1,retained.allSatisfy({after[$0.key]==$0.value}),
          await MovieExporter.clipIssue(movie,frames:150,width:320,height:180,decodeAllFrames:true)==nil else{throw HouseError.message("Encoder retry failed or rewrote a completed shot.")}
        try FileManager.default.removeItem(at:movie)
        try FileManager.default.removeItem(at:movie.deletingPathExtension().appendingPathExtension("json"))
        let damaged=after.keys.sorted{$0.path<$1.path}[0]
        try DurableFiles.write(Data(repeating:65,count:65),to:damaged.appendingPathExtension("sha256"))
        var repairedFrames=0
        let repaired=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:5,width:320,height:180,
            checkpoint:{if $0=="frame-encoded" {repairedFrames+=1}}){_ in}
        let repairedShots=try completedShots(repo)
        let repairedChecksum=try DurableFiles.read(damaged.appendingPathExtension("sha256"),limit:64)
        guard repairedFrames>0,repairedFrames<150,
          after.filter({$0.key != damaged}).allSatisfy({repairedShots[$0.key]==$0.value}),
          String(data:repairedChecksum,encoding:.utf8)==(try StreamingArchive.digest(damaged).sha) else{throw HouseError.message("Invalid movie checksum did not rebuild only the affected shot.")}
        try FileManager.default.removeItem(at:repaired)
        try FileManager.default.removeItem(at:repaired.deletingPathExtension().appendingPathExtension("json"))
        let exhausted=try Repository(root:root.appendingPathComponent("exhausted"))
        let exports=Exporter.destination("probe").deletingLastPathComponent()
        let originalExports=Set(try FileManager.default.contentsOfDirectory(atPath:exports.path))
        var attempts=0,exhaustedRetries=0,refused=false
        do {
            _=try await MovieExporter.render(house,repo:exhausted,options:SceneOptions(),duration:5,width:320,height:180,checkpoint:{phase in
                if phase=="frame-encoded" {attempts+=1;throw timeout()}
            },encoderRecovery:{_ in exhaustedRetries+=1}){_ in}
        }catch is MovieEncoderTimeout {refused=true}
        guard refused,attempts==2,exhaustedRetries==1,try completedShots(exhausted).isEmpty,
          Set(try FileManager.default.contentsOfDirectory(atPath:exports.path))==originalExports else{throw HouseError.message("A repeated encoder stall did not stop after one retry without publishing output.")}
        if let files=FileManager.default.enumerator(at:exhausted.root.appendingPathComponent("tours"),includingPropertiesForKeys:nil) {
            for case let url as URL in files where url.pathExtension=="mp4" {throw HouseError.message("A failed encoder retained an unfinished movie.")}
        }
        return ["test":"Movie encoder retries one unfinished shot and stops after a second stall","passed":true,
            "injectedFailures":3,"successfulRetryCount":retries,"persistentFailureAttempts":attempts,
            "completedShotsPreserved":retained.count,"corruptChecksumRebuiltFrames":repairedFrames,"physicalDeviceQualified":false]
    }
    static func movieRecoveryReport(repo:Repository) async throws->[String:Any] {
        let house=DemoFactory.make(),options=SceneOptions(),exports=Exporter.destination("probe").deletingLastPathComponent()
        func published()throws->Set<String> {Set(try FileManager.default.contentsOfDirectory(atPath:exports.path))}
        func cache()throws->[String:String] {
            let root=repo.root.appendingPathComponent("tours")
            guard let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.contentModificationDateKey]) else{return [:]}
            var result:[String:String]=[:]
            for case let url as URL in files where url.pathExtension=="mp4" {
                guard !url.lastPathComponent.contains("partial") else{throw HouseError.message("Interrupted movie retained an unfinished shot.")}
                let date=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate!
                result[url.lastPathComponent]=try StreamingArchive.digest(url).sha+"|"+String(date.timeIntervalSince1970)
            }
            return result
        }
        let originalExports=try published();var retained:[String:String]=[:]
        var completedShots=0,partialFrames=0,interrupted:Task<URL,Error>?
        interrupted=Task {
            try await MovieExporter.render(house,repo:repo,options:options,duration:5,width:320,height:180,checkpoint:{phase in
                if phase=="shot-committed" {completedShots+=1}
                if phase=="frame-encoded",completedShots==1 {
                    partialFrames+=1
                    if partialFrames==3 {interrupted?.cancel()}
                }
            }){_ in}
        }
        do {_=try await interrupted!.value;throw HouseError.message("Mid-shot cancellation did not stop export.")}catch is CancellationError{}
        retained=try cache()
        guard completedShots==1,partialFrames==3,retained.count==1,try published()==originalExports else{throw HouseError.message("Mid-shot interruption did not retain exactly the completed shot and remove partial output.")}

        for phase in ["shot-committed","assembly-started","assembly-completed"] {
            do {
                _=try await MovieExporter.render(house,repo:repo,options:options,duration:5,width:320,height:180,checkpoint:{if $0==phase {throw CancellationError()}}){_ in}
                throw HouseError.message("Movie fault checkpoint was not reached: "+phase)
            } catch is CancellationError {}
            let current=try cache()
            guard !current.isEmpty,retained.allSatisfy({current[$0.key]==$0.value}),try published()==originalExports else{throw HouseError.message("Movie interruption changed a completed shot or published an incomplete final file.")}
            retained=current
        }
        var cancelled:Task<URL,Error>?
        cancelled=Task {
            try await MovieExporter.render(house,repo:repo,options:options,duration:5,width:320,height:180,checkpoint:{if $0=="assembly-completed" {cancelled?.cancel()}}){_ in}
        }
        do {_=try await cancelled!.value;throw HouseError.message("Cancelled movie was published.")}catch is CancellationError{}
        guard try cache()==retained,try published()==originalExports else{throw HouseError.message("Task cancellation lost a shot or retained a final export.")}
        let recovered=try await MovieExporter.render(house,repo:repo,options:options,duration:5,width:320,height:180){_ in}
        guard try cache()==retained,await MovieExporter.validClip(recovered,frames:150,width:320,height:180) else{throw HouseError.message("Interrupted movie did not resume from its verified shots.")}
        let digest=try StreamingArchive.digest(recovered).sha
        try FileManager.default.removeItem(at:recovered);try FileManager.default.removeItem(at:recovered.deletingPathExtension().appendingPathExtension("json"))
        return ["test":"Movie interruption and final-publication recovery","passed":true,"faultPhases":["mid-shot","shot-committed","assembly-started","assembly-completed"],"actualTaskCancellation":true,"retainedShots":retained.count,"recoveredFrames":150,"recoveredMovieSHA256":digest,"physicalDeviceQualified":false]
    }
    static func movieTargetReport(root:URL) async throws->[String:Any] {
        let scene=SCNScene();scene.background.contents=UIColor.black
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=1;camera.camera!.zNear=0.1;camera.camera!.zFar=10;scene.rootNode.addChildNode(camera)
        func plane(_ x:Float,_ y:Float,_ z:Float,_ color:UIColor) {
            let geometry=SCNPlane(width:0.6,height:0.6);geometry.firstMaterial!.diffuse.contents=color;geometry.firstMaterial!.lightingModel = .constant
            let node=SCNNode(geometry:geometry);node.position=SCNVector3(x,y,z);scene.rootNode.addChildNode(node)
        }
        plane(-0.5,0.5,-2,.red);plane(-0.5,0.5,-3,.green);plane(0.5,0.5,-2,.green);plane(0.5,-0.5,-2,.blue)
        let renderer=try MovieFrameRenderer(scene:scene,camera:camera,width:320,height:240,title:"Target orientation",provenance:"SYNTHETIC TEST")
        var pool:CVPixelBufferPool?
        let attributes=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:240,kCVPixelBufferMetalCompatibilityKey as String:true,kCVPixelBufferIOSurfacePropertiesKey as String:[:]] as [String:Any]
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault,nil,attributes as CFDictionary,&pool)==kCVReturnSuccess,let pool else{throw HouseError.message("Probe pixel pool failed.")}
        let buffer=try await renderer.frame(at:0,pool:pool)
        CVPixelBufferLockBaseAddress(buffer,.readOnly);defer{CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
        guard let base=CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to:UInt8.self) else{throw HouseError.message("Probe pixels unavailable.")}
        let stride=CVPixelBufferGetBytesPerRow(buffer)
        func rgb(_ x:Int,_ y:Int)->[Int] {let p=y*stride+x*4;return [Int(base[p+2]),Int(base[p+1]),Int(base[p])]}
        let red=rgb(100,60),green=rgb(220,60),blue=rgb(220,180)
        var captionPixels=0
        for y in 193..<221 {for x in 20..<300 {let c=rgb(x,y);if c.allSatisfy({$0>180}){captionPixels+=1}}}
        if let cg=CIContext().createCGImage(CIImage(cvPixelBuffer:buffer),from:CGRect(x:0,y:0,width:320,height:240)) {try UIImage(cgImage:cg).pngData()?.write(to:root.appendingPathComponent("metal-target.png"))}
        let passed=red[0]>180 && red[1]<70 && red[2]<70 && green[1]>180 && green[0]<70 && blue[2]>180 && blue[0]<70 && captionPixels>10
        return ["test":"Direct Metal movie target, color order, orientation and depth","passed":passed,"topLeftRGB":red,"topRightRGB":green,"bottomRightRGB":blue,"captionPixels":captionPixels,"cpuSceneReadbackInProduction":false]
    }
    // Read the process footprint, not total installed device RAM. This is a
    // sampled observation; the kernel's resident peak also includes earlier work.
    static func evidenceSearchReport()throws->[String:Any] {
        var house=House.empty("Search workload");house.rooms[0].name="Café kitchen"
        let room=house.rooms[0].id,stage=house.stages[1].id,segment=Segment(roomID:house.rooms[0].id,stageID:house.stages[1].id)
        house.segments=[segment]
        let base=Observation(roomID:room,stageID:stage,segmentID:segment.id,timestamp:0,image:"search-fixture.jpg",width:64,height:64,camera:Rigid().values,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic metadata",light:500,sharpness:0.1)
        var expected=Set<UUID>()
        for i in 0..<50000 {
            var o=base;o.id=UUID();o.timestamp=Double(i);o.note=(i%1000==0 ? "Supply valve":"Electrical outlet")+" · photograph \(i)"
            if i%1000==0 {expected.insert(o.id)}
            house.observations.append(o)
        }
        house.features=[Feature(name:"Panel A",trade:.electrical,roomID:room,stageID:stage,kind:.observed,mesh:Mesh())]
        let start=ProcessInfo.processInfo.systemUptime,index=try EvidenceSearch.Index(house:house)
        let build=(ProcessInfo.processInfo.systemUptime-start)*1000
        let first=try index.find("",limit:200),valves=try index.find("CAFE valve"),panel=try index.find("cafe\u{301} panel")
        guard first.observationCount==50000,first.observations.count==200,first.observations.first?.id==house.observations.last?.id,
          valves.observationCount==50,Set(valves.observations.map{$0.id})==expected,panel.featureCount==1,panel.observationCount==0 else{throw HouseError.message("Search lost room metadata, word matching, ordering or result pagination.")}
        var times:[Double]=[],queryTimings:[[String:Any]]=[]
        for query in ["cafe valve","finished","electrical outlet","absent result","panel a","café kitchen"]+Array(repeating:"cafe valve",count:6) {
            let time=ProcessInfo.processInfo.systemUptime
            _ = try index.find(query)
            let elapsed=(ProcessInfo.processInfo.systemUptime-time)*1000
            times.append(elapsed);queryTimings.append(["query":query,"milliseconds":elapsed])
        }
        times.sort();let p95=times[Int(ceil(Double(times.count)*0.95))-1]
        var imported=House.empty("Imported evidence");imported.rooms[0].name="Kitchen"
        let known=DocumentaryPhoto(image:"known.jpg",note:"Valve label",roomID:imported.rooms[0].id,stageID:imported.stages[1].id)
        let unknown=DocumentaryPhoto(image:"unknown.jpg",note:"Valve label",roomID:nil,stageID:nil)
        imported.documentaryPhotos=[known,unknown]
        let importedIndex=try EvidenceSearch.Index(house:imported),named=try importedIndex.find("kitchen finished valve"),all=try importedIndex.find("valve",limit:1)
        guard named.documentaryPhotos.map({$0.id})==[known.id],named.photographCount==1,
          all.photographCount==2,all.documentaryPhotos.count==1,all.documentaryPhotos[0].id==unknown.id,
          all.observations.isEmpty else{throw HouseError.message("Documentary search lost labels or fabricated room/stage metadata.")}
        var reference=House.empty("Substring reference");reference.rooms[0].name="Café utility"
        let referenceSegment=Segment(roomID:reference.rooms[0].id,stageID:reference.stages[0].id);reference.segments=[referenceSegment]
        let notes=["Valves and electrical outlets","valve valve","CAFÉ label","cafe\u{301} label","12-34 outlet.","line\nvalve","👷🏽 pipe","Ελληνικά service"," 東京 配管 ","","valve valve"]
        reference.observations=notes.enumerated().map{index,note in
            var o=base;o.id=UUID();o.roomID=referenceSegment.roomID;o.stageID=referenceSegment.stageID;o.segmentID=referenceSegment.id;o.timestamp=Double(index);o.note=note;return o
        }
        let referenceIndex=try EvidenceSearch.Index(house:reference)
        let referenceQueries=["","val","valve","valve valve","lec out","CAFÉ label","afe","12-3","outlet.","line valve","👷","🏽","ελλην","東京","管","utility pipe","not-found","rough valve"]
        for query in referenceQueries {
            let terms=EvidenceSearch.normalized(query).split(whereSeparator:{$0.isWhitespace}).map{Data($0.utf8)}
            let expected=reference.observations.reversed().filter{o in
                let bytes=Data((EvidenceSearch.normalized(o.note)+" "+EvidenceSearch.normalized(reference.rooms[0].name)+" "+EvidenceSearch.normalized(reference.stages[0].name)).utf8)
                return terms.allSatisfy{bytes.range(of:$0) != nil}
            }.map{$0.id}
            let actual=try referenceIndex.find(query)
            guard actual.observationCount==expected.count,actual.observations.map({$0.id})==expected else{throw HouseError.message("Indexed search disagreed with independent full-text substring matching.")}
        }
        return ["test":"Fifty-thousand photograph metadata search","passed":p95<=300,"photographs":50000,"uniquePhotoMetadata":50000,"defaultPageSize":200,"indexBuildMilliseconds":build,"queryP95Milliseconds":p95,"queries":times.count,"queryTimingsMilliseconds":queryTimings,"substringReferenceQueries":referenceQueries.count,"imageFilesRead":0,"limitations":"Synthetic metadata workload. Simulator results do not qualify sustained performance on the owner's phone."]
    }
    nonisolated static func memorySample()->[String:UInt64] {
        var info=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let capacity=Int(count)
        let status=withUnsafeMutablePointer(to:&info){pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:capacity){task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)}
        }
        guard status==KERN_SUCCESS else{return [:]}
        return ["physicalFootprintBytes":info.phys_footprint,"residentBytes":info.resident_size,"lifetimeResidentPeakBytes":info.resident_size_peak]
    }
    static func codedReferenceReport(repo:Repository,outputRoot:URL)throws->[String:Any] {
        var diagnostics:[String:Any]=["completed":false,"stage":"print","physicalDeviceQualified":false]
        func checkpoint(_ stage:String) {
            diagnostics["stage"]=stage
            if let bytes=try? JSONSerialization.data(withJSONObject:diagnostics,options:[.sortedKeys]) {try? DurableFiles.write(bytes,to:outputRoot.appendingPathComponent("coded-reference-diagnostics.json"))}
        }
        defer {checkpoint(diagnostics["stage"] as? String ?? "unknown")}
        var house=House.empty("Coded reference fixture");house.isDemo=true
        var segment=Segment(roomID:house.rooms[0].id,stageID:house.stages[0].id);house.segments=[segment]
        let centres=[V3(-0.7,-0.5,2.4),V3(0.7,-0.55,2.8),V3(-0.65,0.05,2.0),V3(0.75,0.10,2.5),V3(-0.7,0.6,2.7),V3(0.65,0.6,2.1)]
        let codes=[1,7,19,33,102,301],width=1280,height=960
        var cells:[[UInt8]]=[]
        for i in centres.indices {
            let board=try BoardGenerator.make(name:"Test reference \(i+1)",repo:repo,tagID:codes[i]);house.references.append(board)
            let c=centres[i],angle=i%2==0 ? 0.5:-0.5,co=cos(angle),si=sin(angle)
            let pose=ReferencePose(boardID:board.id,matrix:[co,-si,0,c.x, 0,0,-1,-c.y, si,co,0,-c.z, 0,0,0,1])
            segment.referencePoses.append(pose)
            var bytes=[UInt8](repeating:0,count:100)
            guard bytes.withUnsafeMutableBufferPointer({hx_tag_image(UInt32(codes[i]),$0.baseAddress,100)})==10 else{throw HouseError.message("Reference raster failed.")};cells.append(bytes)
            if i==0 {
                try repo.read(board.pdf).write(to:outputRoot.appendingPathComponent("coded-reference.pdf"))
                let (gray,w,h)=try VisualMapping.image(repo.read(board.image))
                let found=try CodedReferences.detect(gray:gray,width:w,height:h,stride:w,boards:[board])
                guard found.count==1,found[0].tagID==codes[i],abs(found[0].corners[0].u-0.1)<0.003,abs(found[0].corners[0].v-0.9)<0.003 else{throw HouseError.message("Printed reference orientation or full-image coordinates changed.")}
            }
        }
        house.segments[0]=segment
        func observation(_ x:Double,_ y:Double=0)->Observation {
            var matrix=Rigid().values;matrix[3]=x;matrix[7]=y
            return Observation(roomID:segment.roomID,stageID:segment.stageID,segmentID:segment.id,timestamp:x+1,image:"synthetic-codes.png",width:width,height:height,camera:matrix,intrinsics:[1000,0,640,0,1000,480,0,0,1],tracking:"synthetic reference camera",light:1000,sharpness:0.1)
        }
        // A saved edge-origin detection of exact projected geometry must
        // recover the same metric board after an archive round trip. Omitting
        // the half-pixel conversion shifts the estimated board by >1 mm.
        let calibrationView=observation(0.13,-0.07),calibrationBoard=house.references[0],calibrationPose=segment.referencePoses[0]
        let calibrationCorners=CodedReferences.corners(board:calibrationBoard,pose:calibrationPose).compactMap{CameraProjection.project($0,through:calibrationView)?.0}.map{UV(u:$0.u+0.5/Double(width),v:$0.v+0.5/Double(height))}
        let saved=CodedDetection(boardID:calibrationBoard.id,tagID:codes[0],corners:calibrationCorners,margin:100)
        let decoded=try JSONDecoder().decode(CodedDetection.self,from:JSONEncoder().encode(saved))
        guard decoded==saved,let calibrationMeasured=CodedReferences.measure([decoded],camera:calibrationView.camera,intrinsics:calibrationView.intrinsics,width:width,height:height,boards:[calibrationBoard]).first,
          zip(calibrationMeasured.matrix,calibrationPose.matrix).allSatisfy({abs($0-$1)<0.00001}) else{throw HouseError.message("Archived marker pixels and camera intrinsics disagree on pixel centres.")}
        diagnostics["archivedPixelCentreContractPassed"]=true
        func render(_ camera:Observation,moved:Bool=false,duplicate:Bool=false)->Data {
            var data=Data(repeating:245,count:width*height)
            let worldFromCamera=PoseRefinement.matrix(camera.camera)!
            data.withUnsafeMutableBytes {buffer in
                let pixels=buffer.bindMemory(to:UInt8.self)
                for i in centres.indices {
                    var transform=PoseRefinement.matrix(segment.referencePoses[i].matrix)!
                    if moved && i==0 {transform.columns.3.x+=0.08}
                    let board=house.references[i],image=cells[duplicate && i==1 ? 0:i]
                    let corners=[(-0.5,-0.5),(0.5,-0.5),(0.5,0.5),(-0.5,0.5)].compactMap {x,y -> UV? in
                        let p=transform*SIMD4(x*board.width,0,y*board.width,1)
                        return CameraProjection.project(V3(p.x,-p.z,p.y),through:camera)?.0
                    }
                    guard corners.count==4 else{continue}
                    let x0=max(0,Int(floor(corners.map{$0.u}.min()!*Double(width)))-1)
                    let x1=min(width-1,Int(ceil(corners.map{$0.u}.max()!*Double(width)))+1)
                    let y0=max(0,Int(floor(corners.map{$0.v}.min()!*Double(height)))-1)
                    let y1=min(height-1,Int(ceil(corners.map{$0.v}.max()!*Double(height)))+1)
                    let boardFromCamera=transform.inverse*worldFromCamera
                    let origin=boardFromCamera*SIMD4<Double>(0,0,0,1)
                    // Write raw row-major pixels directly. Core Graphics path
                    // coordinates must not choose the camera image orientation.
                    for y in y0...y1 {for x in x0...x1 {
                        let ray=boardFromCamera*SIMD4((Double(x)-camera.intrinsics[2])/camera.intrinsics[0],-(Double(y)-camera.intrinsics[5])/camera.intrinsics[4],-1,0)
                        guard abs(ray.y)>1e-12 else{continue}
                        let distance = -origin.y/ray.y
                        guard distance>0 else{continue}
                        let local=origin+ray*distance,u=local.x/board.width+0.5,v=local.z/board.width+0.5
                        guard u>=0,u<1,v>=0,v<1 else{continue}
                        pixels[y*width+x]=image[Int(v*10)*10+Int(u*10)]==0 ? 12:245
                    }}
                }
            }
            return data
        }
        var measured:[UUID:ReferencePose]=[:],measurementErrors:[Double]=[]
        for (imageIndex,x) in [-0.12,0.12].enumerated() {
            checkpoint("source image \(imageIndex)")
            var o=observation(x);let gray=render(o)
            if let provider=CGDataProvider(data:gray as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),let png=UIImage(cgImage:image).pngData() {try png.write(to:outputRoot.appendingPathComponent("coded-source-\(imageIndex).png"))}
            o.codedDetections=try CodedReferences.detect(gray:gray,width:width,height:height,stride:width,boards:house.references)
            diagnostics["source\(imageIndex)DetectedIDs"]=o.codedDetections?.map{$0.tagID} ?? []
            guard o.codedDetections?.count==6 else{throw HouseError.message("Known source image did not decode all six separated boards.")}
            let poses=CodedReferences.measure(o.codedDetections ?? [],camera:o.camera,intrinsics:o.intrinsics,width:width,height:height,boards:house.references)
            diagnostics["source\(imageIndex)MeasuredIDs"]=poses.compactMap{p in house.references.first{$0.id==p.boardID}?.tagID}
            guard poses.count==6 else{throw HouseError.message("Source corner geometry did not resolve all six board poses: \(poses.count).")}
            o.referenceObservations=poses
            for pose in poses {
                let truth=segment.referencePoses.first{$0.boardID==pose.boardID}!
                measurementErrors.append((V3(pose.matrix[3],pose.matrix[7],pose.matrix[11])-V3(truth.matrix[3],truth.matrix[7],truth.matrix[11])).length)
                if let prior=measured[pose.boardID] {
                    guard VisualMapping.agree(Rigid(values:prior.matrix),Rigid(values:pose.matrix)) else{throw HouseError.message("Independent source images disagree about a fixed coded board.")}
                    if (pose.imageFitRMS ?? .infinity)<(prior.imageFitRMS ?? .infinity) {measured[pose.boardID]=pose}
                }else{measured[pose.boardID]=pose}
            }
            house.observations.append(o)
        }
        house.segments[0].referencePoses=measured.values.sorted{$0.boardID.uuidString<$1.boardID.uuidString}
        diagnostics["sourceBoardPositionErrorsMetres"]=measurementErrors;checkpoint("capture persistence")
        try house.validate()
        var captureCheckpoint=house;captureCheckpoint.observations=[];try repo.save(captureCheckpoint)
        for o in house.observations {try repo.stageCapture(o,projectID:house.id,room:house.rooms[0],stage:house.stages[0],segment:house.segments[0],references:house.references)}
        guard let recovered=try Repository(root:repo.root).all().first(where:{$0.id==house.id}),recovered.observations==house.observations else{throw HouseError.message("Coded capture rows did not preserve corner and pose evidence after reopening.")}
        let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(recovered));try restored.validate()
        let map=CodedReferences.build(house:restored,segment:restored.segments[0])
        diagnostics["supportedBoards"]=map.boards.count;checkpoint("source consistency")
        guard map.boards.count==6 else{throw HouseError.message("Translated source-corner evidence did not qualify the saved board geometry.")}
        var missingCheckpoint=restored;missingCheckpoint.segments[0].referencePoses=[]
        let rebuilt=CodedReferences.build(house:missingCheckpoint,segment:missingCheckpoint.segments[0])
        guard rebuilt.boards.count==6,zip(rebuilt.boards,map.boards).allSatisfy({$0.id==$1.id && $0.corners==$1.corners}) else{throw HouseError.message("Committed source rows could not recover before the aggregate reference checkpoint.")}
        var linked=missingCheckpoint
        linked.segments[0].registration=Rigid()
        var other=linked.segments[0];other.id=UUID();other.stageID=linked.stages[1].id;other.registration=nil
        linked.segments.append(other)
        for original in missingCheckpoint.observations {
            var copy=original;copy.id=UUID();copy.segmentID=other.id;copy.stageID=other.stageID;copy.camera[3]-=0.4;copy.referenceObservations=[]
            linked.observations.append(copy)
        }
        let (handoff,_,link)=try ReferenceRegistration.fit(source:other,anchor:linked.segments[0],house:linked)
        guard (handoff.apply(V3())-V3(0.4,0,0)).length<0.001 else{throw HouseError.message("Coded handoff failed to rebuild geometry from durable source rows.")}
        linked.segments[1].registration=handoff;linked.segments[1].registrationLink=link
        ReferenceRegistration.invalidateChangedInputs(&linked)
        guard linked.segments[1].registration != nil else{throw HouseError.message("Unchanged coded handoff invalidated itself.")}
        var trackingFault=linked
        for i in trackingFault.observations.indices where trackingFault.observations[i].segmentID==other.id {trackingFault.observations[i].tracking="limited(excessiveMotion)"}
        guard CodedReferences.build(house:trackingFault,segment:trackingFault.segments[1]).boards.isEmpty else{throw HouseError.message("Limited tracking retained coded source geometry.")}
        ReferenceRegistration.invalidateChangedInputs(&trackingFault)
        guard trackingFault.segments[1].registration==nil else{throw HouseError.message("Changed tracking admission retained a stale coded handoff.")}
        diagnostics["limitedTrackingSourcesRefused"]=true
        let last=linked.observations.count-1
        linked.observations[last].codedDetections![0].corners[0].u+=0.01
        ReferenceRegistration.invalidateChangedInputs(&linked)
        guard linked.segments[1].registration==nil else{throw HouseError.message("A changed raw reference corner retained a stale stage registration.")}
        var resizedPrint=restored;resizedPrint.references[0].width *= 1.5
        guard !CodedReferences.build(house:resizedPrint,segment:resizedPrint.segments[0]).boards.contains(where:{$0.id==resizedPrint.references[0].id}) else{throw HouseError.message("A changed print scale reused an old metric pose despite conflicting translated views.")}
        var conflictedHouse=restored,changed=restored.observations[0];changed.id=UUID()
        let firstBoard=house.references[0].id
        let changedIndex=changed.codedDetections!.firstIndex{$0.boardID==firstBoard}!
        for i in 0..<4 {changed.codedDetections![changedIndex].corners[i].u+=0.02}
        conflictedHouse.observations.append(changed)
        guard !CodedReferences.build(house:conflictedHouse,segment:conflictedHouse.segments[0]).boards.contains(where:{$0.id==firstBoard}) else{throw HouseError.message("A conflicting later source frame was ignored in favor of earlier agreeing views.")}
        var errors:[Double]=[],queryChecks:[[String:Any]]=[]
        for (x,y) in [(-0.06,0.02),(0.0,-0.03),(0.05,0.04),(0.09,-0.02)] {
            checkpoint("query \(errors.count)")
            let o=observation(x,y),result=try CodedReferences.localize(gray:render(o),width:width,height:height,stride:width,intrinsics:o.intrinsics,map:map)
            var check:[String:Any]=["x":x,"y":y,"accepted":result.pose != nil && !result.conflict]
            if let quality=result.quality {check["rejectionGate"]=quality.rejection;check["rmsPixels"]=quality.rms_pixels;check["maximumHeldOutPixels"]=quality.maximum_check_pixels;check["maximumLeaveOutShiftMetres"]=quality.maximum_leave_out_shift_metres}
            queryChecks.append(check);diagnostics["queries"]=queryChecks
            guard let pose=result.pose,!result.conflict else{continue}
            errors.append((V3(pose.values[3],pose.values[7],pose.values[11])-V3(x,0,y)).length)
            diagnostics["acceptedPositionErrorsMetres"]=errors
        }
        checkpoint("rejection challenges")
        let q=observation(0.03)
        let moved=try CodedReferences.localize(gray:render(q,moved:true),width:width,height:height,stride:width,intrinsics:q.intrinsics,map:map)
        guard moved.conflict,moved.pose==nil else{throw HouseError.message("A moved reference was incorrectly admitted.")}
        var duplicateRejected=false
        do{_=try CodedReferences.localize(gray:render(q,duplicate:true),width:width,height:height,stride:width,intrinsics:q.intrinsics,map:map)}catch{duplicateRejected=true}
        let missing=try CodedReferences.localize(gray:Data(repeating:245,count:width*height),width:width,height:height,stride:width,intrinsics:q.intrinsics,map:map)
        let otherRegion=CodedReferences.Map(boards:[],known:map.known)
        let wrong=try CodedReferences.localize(gray:render(q),width:width,height:height,stride:width,intrinsics:q.intrinsics,map:otherRegion)
        guard wrong.conflict,wrong.pose==nil else{throw HouseError.message("References from another saved region did not hide alignment.")}
        var movedHouse=house;movedHouse.references[0].valid=false
        guard CodedReferences.build(house:movedHouse,segment:movedHouse.segments[0]).boards.count==5 else{throw HouseError.message("Invalidating a board did not remove its evidence.")}
        diagnostics["completed"]=true;checkpoint("completed")
        return ["test":"Coded reference images, saved corner provenance and finished-wall pose","passed":errors.count==4 && duplicateRejected && missing.pose==nil && errors.allSatisfy{$0<=0.01},"nominalQueries":errors.count,"acceptedPositionErrorsMetres":errors,"sourceBoardPositionErrorsMetres":measurementErrors,"oracleBoardPosesUsedForLocalization":false,"movedReferenceRejected":true,"duplicateReferenceRejected":duplicateRejected,"missingReferencesHidden":missing.pose==nil,"wrongRegionRejected":true,"physicalDeviceQualified":false,"limitations":"Synthetic raster images and known source camera calibration/poses. Board poses are estimated from pixels. Actual camera pose drift/timing, print flatness/scale and complete-house diversity remain unqualified."]
    }
    nonisolated static func prepareLargeScene(textureKeys:[String])throws->(House,SpatialDisplayIndex,[String:Any]) {
        let started=ProcessInfo.processInfo.systemUptime
        var h=House.empty("Synthetic capacity workload");h.isDemo=true;h.rooms=[]
        h.stages[0].phase = .rough;h.stages[1].phase = .finished
        let side=50
        for roomIndex in 0..<100 {
            try Task.checkCancellation()
            let origin=V3(Double(roomIndex%5)*6,Double((roomIndex/5)%4)*6,Double(roomIndex/20)*3.5)
            let room=Room(name:"Capacity space \(roomIndex+1)",level:roomIndex/20,origin:origin,size:V3(5,5,3));h.rooms.append(room)
            for stage in 0..<2 {
                var mesh=Mesh(),uv:[UV]=[]
                for y in 0...side {for x in 0...side {
                    mesh.vertices.append(origin+V3(Double(x)*5/Double(side),4.8+Double(stage)*0.05,Double(y)*3/Double(side)))
                    uv.append(UV(u:Double(x)/Double(side),v:Double(y)/Double(side)))
                }}
                for y in 0..<side {for x in 0..<side {
                    let a=Int32(y*(side+1)+x),b=a+1,c=a+Int32(side+1),d=c+1
                    mesh.triangles += [a,b,c,b,d,c]
                }}
                h.features.append(Feature(name:"Capacity wall",trade:stage==0 ? .structure:.finish,roomID:room.id,stageID:h.stages[stage].id,kind:.synthetic,mesh:mesh,texture:textureKeys[(roomIndex*2+stage)%textureKeys.count],uv:uv))
            }
        }
        try h.validate()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let bytes=try encoder.encode(h)
        guard bytes.count<=100_000_000 else{throw HouseError.message("Capacity metadata exceeds the store's admission limit.")}
        let restored=try JSONDecoder().decode(House.self,from:bytes);try restored.validate()
        guard restored.rooms==h.rooms,restored.features.count==200,zip(restored.features,h.features).allSatisfy({$0.id==$1.id && $0.mesh==$1.mesh}) else{throw HouseError.message("Capacity metadata changed during round trip.")}
        let rough=SceneBuilder.features(h,options:SceneOptions()),finished=SceneBuilder.features(h,options:SceneOptions(mode:.finished))
        guard rough.count==100,finished.count==100,Set(rough.map{$0.id}).isDisjoint(with:Set(finished.map{$0.id})) else{throw HouseError.message("Capacity stages lost isolation.")}
        let index=try SpatialDisplayIndex(features:h.features)
        guard index.tiles.reduce(0,{$0+$1.primitives.count})==1_000_000 else{throw HouseError.message("Capacity index lost source primitives.")}
        var timings:[Double]=[],maxResident=0,maxCost=0
        for room in h.rooms {
            try Task.checkCancellation();let start=ProcessInfo.processInfo.systemUptime
            let plan=index.plan(camera:room.origin+V3(2.5,2,1.6))
            timings.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            let cost=plan.reduce(0,{$0+$1.budget});maxResident=max(maxResident,plan.count);maxCost=max(maxCost,cost)
            guard plan.count<=512,cost<=DisplayGeometry.sceneVertexBudget else{throw HouseError.message("Capacity residency exceeded its budget.")}
            for allocation in plan.prefix(2) {let (_,mesh,_)=index.materialize(allocation);guard mesh.valid,DisplayGeometry.cost(mesh)<=allocation.budget else{throw HouseError.message("Capacity tile exceeded allocation.")}}
        }
        timings.sort()
        return(h,index,["rooms":100,"levels":5,"stages":2,"sourceTriangles":1_000_000,"metadataBytes":bytes.count,"tiles":index.tiles.count,"maximumResidentTiles":maxResident,"maximumResidentEntries":maxCost,"planP95Milliseconds":timings[Int(ceil(Double(timings.count)*0.95))-1],"preparationSeconds":ProcessInfo.processInfo.systemUptime-started,"memoryAfterPreparation":memorySample()])
    }
    static func largeSceneReport(repo:Repository) async throws->[String:Any] {
        let root=repo.root
        // Exercise real image decoding with more distinct assets than the resident cache.
        var textureKeys:[String]=[]
        for index in 0..<32 {
            try Task.checkCancellation()
            let bytes=try autoreleasepool { () throws -> Data in
                let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
                let image=UIGraphicsImageRenderer(size:CGSize(width:768,height:768),format:format).image {context in
                    for y in 0..<12 {for x in 0..<12 {
                        UIColor(hue:CGFloat(index)/32,saturation:0.5,brightness:(x+y)%2==0 ? 0.9:0.35,alpha:1).setFill()
                        context.fill(CGRect(x:x*64,y:y*64,width:64,height:64))
                    }}
                }
                guard let bytes=image.pngData() else{throw HouseError.message("Capacity texture encoding failed.")};return bytes
            }
            textureKeys.append(try repo.put(bytes,ext:"png"))
        }
        let keys=textureKeys
        let prepared=try await LocalWorker.run{try prepareLargeScene(textureKeys:keys)}
        let h=prepared.0,index=prepared.1,scene=SceneBuilder.baseScene(),options=SceneOptions(mode:.evidence)
        let stream=SpatialSceneStream(index:index,scene:scene,options:options)
        let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene
        let camera=SceneBuilder.camera(at:V3());scene.rootNode.addChildNode(camera);renderer.pointOfView=camera
        var frameTimes:[Double]=[],memories:[[String:UInt64]]=[],sharpFrames=0,loads:[Double]=[],collisionCounts:[Int]=[],textureCounts:[Int]=[],decodedBytes:[Int]=[],completeNearFaces:[Int]=[]
        for (visit,roomIndex) in [0,99].enumerated() {
            let room=h.rooms[roomIndex],position=room.origin+V3(2.5,-1,1.5),start=ProcessInfo.processInfo.systemUptime
            camera.simdPosition=position.render;camera.look(at:SCNVector3((room.origin+V3(2.5,4.8,1.5)).render))
            // Drain the same one-tile updates as the interactive view. The
            // synthetic clock drives residency only, never the reported timing.
            for tick in 0..<513 {try Task.checkCancellation();stream.update(camera:position,time:Double(visit*1000+tick)/30);if tick%16==0 {await Task.yield()}}
            guard stream.pending.isEmpty,stream.nodes.count<=512,stream.allocations.values.reduce(0,{$0+$1.budget})<=DisplayGeometry.sceneVertexBudget else{throw HouseError.message("Capacity scene did not settle within its residency budget.")}
            let roomTiles=index.tiles.indices.filter{index.features[index.tiles[$0].feature].roomID==room.id}
            var nearFaces=0
            for tile in roomTiles {
                guard let allocation=stream.allocations[tile],allocation.budget>=index.tiles[tile].cost else{throw HouseError.message("The nearby capacity wall lost full-surface admission.")}
                let (_,mesh,_)=index.materialize(allocation);nearFaces+=mesh.triangles.count/3
            }
            guard nearFaces==10000 else{throw HouseError.message("Display reduction perforated a nearby wall.")}
            completeNearFaces.append(nearFaces)
            loads.append(ProcessInfo.processInfo.systemUptime-start)
            let rasterBytes=SceneBuilder.decodedTextureBytes(stream.textures)
            guard !stream.textures.isEmpty,stream.textures.count<=DisplayGeometry.textureBudget,rasterBytes<=DisplayGeometry.textureByteBudget else{throw HouseError.message("Capacity textures exceed decoded residency limits.")}
            textureCounts.append(stream.textures.count);decodedBytes.append(rasterBytes)
            let inside=room.origin+V3(2.5,2,1.6)
            let local=try await LocalWorker.run{try SpatialClearance(index:index,camera:inside)}
            guard local.complete,local.primitiveCount>0,local.primitiveCount<=500000,
              local.isClear(from:inside,to:inside+V3(0.3,0,0),radius:0.15),
              !local.isClear(from:inside,to:room.origin+V3(2.5,5.2,1.6),radius:0.15),
              !local.isClear(from:inside,to:inside+V3(4.1,0,0),radius:0.15)
            else{throw HouseError.message("Capacity local collision lost wall or coverage bounds.")}
            collisionCounts.append(local.primitiveCount)
            for frame in 0..<30 {
                try Task.checkCancellation();let before=ProcessInfo.processInfo.systemUptime
                let image=autoreleasepool{renderer.snapshot(atTime:Double(frame)/30,with:CGSize(width:640,height:360),antialiasingMode:.none)}
                frameTimes.append((ProcessInfo.processInfo.systemUptime-before)*1000)
                if frame==0 {guard let cg=image.cgImage,CaptureController.sharpness(cg)>0.002 else{throw HouseError.message("Capacity renderer produced an empty view.")};sharpFrames+=1;if visit==0 {try image.pngData()?.write(to:root.appendingPathComponent("large-house-render.png"))}}
                if frame%10==0 {memories.append(memorySample());await Task.yield()}
            }
        }
        frameTimes.sort();var report=prepared.2
        report["test"]="100-space two-stage capacity and native streamed render";report["passed"]=sharpFrames==2
        report["offscreenFrames"]=frameTimes.count;report["offscreenSize"]=[640,360]
        report["offscreenP50Milliseconds"]=frameTimes[frameTimes.count/2];report["offscreenP95Milliseconds"]=frameTimes[Int(ceil(Double(frameTimes.count)*0.95))-1]
        report["residencyLoadSeconds"]=loads;report["memorySamples"]=memories
        report["sourceTextureCount"]=textureKeys.count;report["residentTextureCounts"]=textureCounts
        report["decodedTextureBytes"]=decodedBytes;report["decodedTextureByteBudget"]=DisplayGeometry.textureByteBudget
        report["localCollisionPrimitives"]=collisionCounts;report["localCollisionRadiusMetres"]=4
        report["completeNearbySourceFaces"]=completeNearFaces
        report["limitations"]="Synthetic tiled walls with procedural textures, local original-geometry collision and no capture data. Decoded raster bounds exclude GPU/driver allocations. Offscreen snapshot time includes readback; it is not sustained display FPS, device thermal qualification, reconstruction completeness or navigation-topology evidence."
        report["physicalDeviceQualified"]=false
        return report
    }
}

