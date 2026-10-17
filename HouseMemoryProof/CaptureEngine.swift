import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import Vision
import ImageIO

@MainActor final class CaptureController:NSObject,ObservableObject,ARSessionDelegate {
    let view=ARSCNView(frame:.zero)
    @Published var running=false
    @Published var message="Choose a room and stage, then start."
    @Published var count=0
    @Published var tracking="Not started"
    @Published var supported=ARWorldTrackingConfiguration.isSupported
    @Published var hasDepth=ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    @Published var processing=false
    @Published var coverageCells=0
    private var cellSet=Set<String>()
    private var model:AppModel?
    private var houseID:UUID?
    private var segment:Segment?
    private var lastFrameTime:TimeInterval=0
    private var lastPosition=SIMD3<Float>(repeating:0)
    private var lastForward=SIMD3<Float>(0,0,-1)
    private var meshes:[UUID:Feature]=[:]
    private var pending=0
    private var stopping=false
    private var generation=UUID()
    var reveal=false
    private var revealedNodes:[SCNNode]=[]
    private let overlayRoot=SCNNode()
    private var loadedWorldMap=false
    private var markerSeen:TimeInterval=0
    private var markerTransform:simd_float4x4?
    private var currentReferencePoses:[UUID:ReferencePose]=[:]
    init(model:AppModel){self.model=model;super.init();view.session.delegate=self;view.session.delegateQueue = .main;view.automaticallyUpdatesLighting=true;view.scene=SCNScene()}
    func start(room:Room,stage:Stage,prior:Segment?=nil,reveal:Bool=false) {
        guard supported,let h=model?.house else{message="AR tracking is unavailable. You can still view, import, annotate and export.";return}
        guard !running,!processing else{return}
        Task {
            let granted=await AVCaptureDevice.requestAccess(for:.video)
            guard granted else{message="Camera permission is denied. Enable it in iPhone Settings to capture; saved projects remain available.";return}
            guard let repo=model?.repository,repo.freeBytes()>750_000_000 else{message="Free at least 750 MB before starting a capture.";return}
            self.reveal=reveal;houseID=h.id;generation=UUID();count=0;meshes=[:];cellSet=[];coverageCells=0;lastFrameTime=0;stopping=false
            let config=ARWorldTrackingConfiguration();config.planeDetection=[.horizontal,.vertical]
            config.detectionImages=await BoardGenerator.images(h,repo:repo);config.maximumNumberOfTrackedImages=2
            currentReferencePoses=[:];markerTransform=nil;markerSeen=0;loadedWorldMap=false
            if hasDepth{config.frameSemantics.insert(.sceneDepth)}
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification){config.sceneReconstruction = .meshWithClassification}
            if let prior,let key=prior.worldMap {
                do {let data=try repo.read(key);config.initialWorldMap=try NSKeyedUnarchiver.unarchivedObject(ofClass:ARWorldMap.self,from:data);loadedWorldMap=config.initialWorldMap != nil}catch{message="Saved map could not be loaded: \(error.localizedDescription)";return}
            }
            if reveal {
                guard let prior,config.initialWorldMap != nil || !prior.referencePoses.isEmpty else{message="This session has no saved AR map. Open source photographs instead.";return}
                segment=prior
                var scoped=h;scoped.features=h.features.filter{$0.segmentID==prior.id};scoped.segments=scoped.segments.map{var s=$0;s.registration=nil;return s}
                let scene=SceneBuilder.scene(scoped,options:SceneOptions(mode:.rough,ceilings:true))
                view.scene=scene;overlayRoot.removeFromParentNode();overlayRoot.childNodes.forEach{$0.removeFromParentNode()};revealedNodes=scene.rootNode.childNodes.filter{$0.geometry != nil};for n in revealedNodes{n.removeFromParentNode();overlayRoot.addChildNode(n);n.isHidden=true};scene.rootNode.addChildNode(overlayRoot)
            }else{
                let s=Segment(roomID:room.id,stageID:stage.id);segment=s;model?.edit{$0.segments.append(s)};view.scene=SCNScene()
            }
            view.session.run(config,options:[.resetTracking,.removeExistingAnchors]);running=true;message=reveal ? "Find the original viewpoint. Overlay stays hidden until ARKit relocalizes. Alignment remains approximate." : "Move slowly sideways. Capture the cavity, not just stud faces."
        }
    }
    func session(_ session:ARSession,didUpdate frame:ARFrame) {
        guard running else{return}
        let normal:Bool
        switch frame.camera.trackingState {case .normal:tracking="Tracking";normal=true
        case .notAvailable:tracking="Unavailable";normal=false
        case .limited(let reason):tracking="Limited: \(reason)";normal=false}
        if reveal {
            let markerFresh=frame.timestamp-markerSeen<2 && markerTransform != nil
            let eligible=normal && (markerFresh || (loadedWorldMap && markerTransform==nil && frame.worldMappingStatus == .mapped))
            if markerFresh,let transform=markerTransform{overlayRoot.simdTransform=transform}
            revealedNodes.forEach{$0.isHidden = !eligible}
            message=eligible ? "Approximate historical overlay. Verify against photographs and physical references; no precision calibration yet." : "Alignment unavailable — overlay hidden. Return to the original capture viewpoint."
            return
        }
        guard pending==0 else{return}
        if ProcessInfo.processInfo.thermalState == .critical || ProcessInfo.processInfo.thermalState == .serious {message="Phone is warm. Capture paused; let it cool.";return}
        guard normal else{message="Tracking limited. Hold still and aim at textured structure. Use Detail photo for documentary evidence.";return}
        let t=frame.camera.transform,p=SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z),f = -SIMD3(t.columns.2.x,t.columns.2.y,t.columns.2.z)
        guard frame.timestamp-lastFrameTime>0.8,(lastFrameTime==0 || simd_distance(p,lastPosition)>0.12 || simd_dot(f,lastForward)<0.99) else{return}
        lastFrameTime=frame.timestamp;lastPosition=p;lastForward=f
        retain(frame,documentary:false)
    }
    func detail(){guard running,!reveal,pending==0 else{return};view.session.captureHighResolutionFrame { [weak self] frame,error in Task {@MainActor in guard let self else{return};if let frame {self.retain(frame,documentary:true)}else{self.message=error?.localizedDescription ?? "Detail capture unavailable."}}}}
    private func retain(_ frame:ARFrame,documentary:Bool) {
        guard let segment,let repo=model?.repository else{return}
        guard repo.freeBytes()>500_000_000 else{message="Storage reserve reached. Saving this session.";stop();return}
        pending+=1;let token=generation;let houseID=houseID
        let orientation:Int
        switch (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation {case .landscapeRight:orientation=1;case .landscapeLeft:orientation=3;case .portraitUpsideDown:orientation=8;default:orientation=6}
        // One retained frame maximum; no unbounded ARFrame queue.
        DispatchQueue.global(qos:.utility).async { [weak self] in
            do {
                let ci=CIImage(cvPixelBuffer:frame.capturedImage),context=CIContext(options:[.cacheIntermediates:false])
                guard let image=context.createCGImage(ci,from:ci.extent),let jpg=UIImage(cgImage:image).jpegData(compressionQuality:0.95) else{throw HouseError.message("Image encoding failed.")}
                let imageKey=try repo.put(jpg,ext:"jpg")
                var depthKey:String?,confidenceKey:String?;var dw=0,dh=0
                if !documentary,let depth=frame.sceneDepth {
                    let buffer=depth.depthMap;dw=CVPixelBufferGetWidth(buffer);dh=CVPixelBufferGetHeight(buffer)
                    CVPixelBufferLockBaseAddress(buffer,.readOnly);var data=Data()
                    if let base=CVPixelBufferGetBaseAddress(buffer){for row in 0..<dh {data.append(base.advanced(by:row*CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to:UInt8.self),count:dw*4)}}
                    CVPixelBufferUnlockBaseAddress(buffer,.readOnly);depthKey=try repo.put(data,ext:"depth32")
                    if let cb=depth.confidenceMap {CVPixelBufferLockBaseAddress(cb,.readOnly);var d=Data();if let base=CVPixelBufferGetBaseAddress(cb){for row in 0..<dh{d.append(base.advanced(by:row*CVPixelBufferGetBytesPerRow(cb)).assumingMemoryBound(to:UInt8.self),count:dw)}};CVPixelBufferUnlockBaseAddress(cb,.readOnly);confidenceKey=try repo.put(d,ext:"confidence8")}
                }
                let k=frame.camera.intrinsics,t=frame.camera.transform
                var camera:[Double]=[],intrinsics:[Double]=[]
                for row in 0..<4{for col in 0..<4{camera.append(Double(t[col][row]))}}
                for row in 0..<3{for col in 0..<3{intrinsics.append(Double(k[col][row]))}}
                let quality=Self.sharpness(image)
                let obs=Observation(roomID:segment.roomID,stageID:segment.stageID,segmentID:segment.id,timestamp:frame.timestamp,image:imageKey,depth:depthKey,confidence:confidenceKey,depthWidth:dw,depthHeight:dh,width:image.width,height:image.height,camera:camera,intrinsics:intrinsics,tracking:String(describing:frame.camera.trackingState),light:Double(frame.lightEstimate?.ambientIntensity ?? 0),sharpness:quality,documentary:documentary,imageOrientation:orientation)
                Task {@MainActor in
                    guard let self else{return};self.pending-=1
                    guard self.generation==token,self.model?.selected==houseID else{return}
                    self.model?.edit{h in h.observations.append(obs)
                        if self.count%5==0 {h.features.removeAll{$0.segmentID==segment.id && $0.name=="Observed LiDAR surface"};h.features.append(contentsOf:self.meshes.values);if let i=h.segments.firstIndex(where:{$0.id==segment.id}){h.segments[i].referencePoses=Array(self.currentReferencePoses.values)}}
                    };self.count+=1
                    let p=self.lastPosition;self.cellSet.insert("\(Int(floor(p.x/0.25))):\(Int(floor(p.z/0.25)))");self.coverageCells=self.cellSet.count
                    self.message=obs.light<150 ? "Low light: add illumination and revisit dark cavities." : quality<0.02 ? "Low detail or blur: hold still and move closer." : "Saved locally. Change your viewing angle; unseen cavity depth remains unverified."
                    if self.stopping {self.finishStop()}
                }
            }catch{Task {@MainActor in guard let self else{return};self.pending-=1;self.message=error.localizedDescription;if self.stopping{self.finishStop()}}}
        }
    }
    nonisolated static func sharpness(_ image:CGImage)->Double {
        let n=64;var data=[UInt8](repeating:0,count:n*n)
        guard let c=CGContext(data:&data,width:n,height:n,bitsPerComponent:8,bytesPerRow:n,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else{return 0}
        c.draw(image,in:CGRect(x:0,y:0,width:n,height:n));var sum=0.0
        for y in 1..<n{for x in 1..<n{sum+=abs(Double(data[y*n+x])-Double(data[y*n+x-1]))+abs(Double(data[y*n+x])-Double(data[(y-1)*n+x]))}}
        return sum/Double((n-1)*(n-1)*510)
    }
    func session(_ session:ARSession,didAdd anchors:[ARAnchor]){references(anchors);collect(anchors)}
    func session(_ session:ARSession,didUpdate anchors:[ARAnchor]){references(anchors);collect(anchors)}
    func session(_ session:ARSession,didRemove anchors:[ARAnchor]){for a in anchors{meshes.removeValue(forKey:a.identifier)}}
    private func references(_ anchors:[ARAnchor]) {
        guard running else{return}
        for item in anchors {
            guard let anchor=item as? ARImageAnchor,anchor.isTracked,let name=anchor.referenceImage.name,let id=UUID(uuidString:name),model?.house?.references.first(where:{$0.id==id})?.valid==true else{continue}
            var values:[Double]=[];for row in 0..<4{for col in 0..<4{values.append(Double(anchor.transform[col][row]))}}
            if reveal,let old=segment?.referencePoses.first(where:{$0.boardID==id}),old.matrix.count==16 {
                var previous=matrix_identity_float4x4;for row in 0..<4{for col in 0..<4{previous[col][row]=Float(old.matrix[row*4+col])}}
                markerTransform=anchor.transform*simd_inverse(previous);markerSeen=view.session.currentFrame?.timestamp ?? 0
            }else if !reveal {currentReferencePoses[id]=ReferencePose(boardID:id,matrix:values)}
        }
    }
    private func collect(_ anchors:[ARAnchor]) {
        guard running,!reveal,let segment else{return}
        for anchor in anchors {
            guard let a=anchor as? ARMeshAnchor,a.geometry.vertices.count<30000 else{continue}
            let g=a.geometry;var vertices:[V3]=[];vertices.reserveCapacity(g.vertices.count)
            for i in 0..<g.vertices.count {let ptr=g.vertices.buffer.contents().advanced(by:g.vertices.offset+g.vertices.stride*i).assumingMemoryBound(to:Float.self);let p=a.transform*SIMD4(ptr[0],ptr[1],ptr[2],1);vertices.append(V3(ar:SIMD3(p.x,p.y,p.z)))}
            var triangles:[Int32]=[];triangles.reserveCapacity(g.faces.count*3)
            for i in 0..<g.faces.count*3 {let ptr=g.faces.buffer.contents().advanced(by:i*g.faces.bytesPerIndex);let value=g.faces.bytesPerIndex==4 ? ptr.load(as:UInt32.self):UInt32(ptr.load(as:UInt16.self));triangles.append(Int32(value))}
            let f=Feature(id:a.identifier,name:"Observed LiDAR surface",trade:.unknown,roomID:segment.roomID,stageID:segment.stageID,kind:.observed,mesh:Mesh(vertices:vertices,triangles:triangles),segmentID:segment.id)
            let total=meshes.values.reduce(0){$0+$1.mesh.vertices.count}-(meshes[a.identifier]?.mesh.vertices.count ?? 0)+vertices.count
            if (meshes.count<120 || meshes[a.identifier] != nil) && total<=250000 {meshes[a.identifier]=f}else{message="Surface budget reached. Stop and start a new segment; original photographs continue saving."}
        }
    }
    func stop(){guard running else{return};running=false;stopping=true;processing=true;if reveal{view.session.pause();revealedNodes.forEach{$0.isHidden=true};processing=false;return};if pending==0{finishStop()}}
    private func finishStop(){guard processing,let segment,let model,let repo=model.repository else{return};let features=Array(meshes.values);model.edit{h in h.features.removeAll{$0.segmentID==segment.id};h.features.append(contentsOf:features);if let i=h.segments.firstIndex(where:{$0.id==segment.id}){h.segments[i].referencePoses=Array(currentReferencePoses.values)}}
        view.session.getCurrentWorldMap { [weak self] map,error in
            Task {@MainActor in guard let self else{return};defer{self.view.session.pause();self.processing=false;self.stopping=false}
                do{if let map{let data=try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true);let key=try repo.put(data,ext:"armap");model.edit{h in if let i=h.segments.firstIndex(where:{$0.id==segment.id}){h.segments[i].worldMap=key}}};self.message="Session saved: \(self.count) images, \(features.count) mesh patches. Approximate, uncalibrated geometry."}catch{self.message="Photos and geometry saved. Map save failed: \(error.localizedDescription)"}
            }
        }
    }
    func sessionWasInterrupted(_ session:ARSession){if let sid=segment?.id{model?.edit{h in if let i=h.segments.firstIndex(where:{$0.id==sid}){h.segments[i].interrupted=true}}};message="Capture interrupted. Saved images remain intact. Start a new segment when you return.";stop()}
    func session(_ session:ARSession,didFailWithError error:Error){message=error.localizedDescription;stop()}
}
struct CaptureSurface:UIViewRepresentable {
    @ObservedObject var controller:CaptureController
    func makeUIView(context:Context)->ARSCNView{controller.view}
    func updateUIView(_ v:ARSCNView,context:Context){}
    static func dismantleUIView(_ v:ARSCNView,coordinator:()){v.session.pause()}
}
enum TextRecognition {
    static func read(_ image:CGImage,orientation:CGImagePropertyOrientation = .right) async throws ->String {try await Task.detached {
        let r=VNRecognizeTextRequest();r.recognitionLevel = .accurate;r.usesLanguageCorrection=false
        try VNImageRequestHandler(cgImage:image,orientation:orientation,options:[:]).perform([r]);return (r.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
    }.value}
}
