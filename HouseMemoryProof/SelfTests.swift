import Foundation
import SceneKit
import PDFKit
import SQLite3

@MainActor enum SelfTests {
    static func run(model:AppModel) async {
        guard let mainRepo=model.repository else{return}
        var results:[[String:Any]]=[]
        func check(_ name:String,_ body:()throws->Bool){do{let ok=try body();results.append(["test":name,"passed":ok])}catch{results.append(["test":name,"passed":false,"error":error.localizedDescription])}}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("self-tests-"+UUID().uuidString)
        do {
            let repo=try Repository(root:folder);var house=DemoFactory.make()
            check("Canonical AR basis"){V3(ar:SIMD3(1,2,3))==V3(1,-3,2)}
            check("Identity rigid transform"){Rigid().valid && Rigid().apply(V3(2,3,4))==V3(2,3,4)}
            check("Reject scale in rigid transform"){var t=Rigid();t.values[0]=2;return !t.valid}
            check("Reject reflected transform"){var t=Rigid();t.values[0] = -1;return !t.valid}
            check("Reference fit and held-out point"){let a=[V3(),V3(1,0,0),V3(0,1,0),V3(1,1,2)],b=a.map{V3(-$0.y+3,$0.x+4,$0.z+2)};guard let(t,e)=Rigid.register(source:Array(a.prefix(3)),target:Array(b.prefix(3))) else{return false};return e<1e-10 && (t.apply(a[3])-b[3]).length<1e-10}
            check("Reject collinear controls"){Rigid.register(source:[V3(),V3(1),V3(2)],target:[V3(),V3(1),V3(2)])==nil}
            check("Fixture has three independent rooms and paired stages"){try house.validate();return house.rooms.count==3 && house.stages.count==2 && house.features.allSatisfy{$0.kind == .synthetic}}
            check("Finish switch preserves stable geometry"){let rough=house.features.filter{SceneBuilder.visible($0,SceneOptions(mode:.rough))},finish=house.features.filter{SceneBuilder.visible($0,SceneOptions(mode:.finished,ceilings:true))};return !rough.isEmpty && !finish.isEmpty && rough.allSatisfy{$0.trade != .finish} && finish.contains{$0.trade == .ceiling}}
            check("Additive schema migration preserves original identity"){let data=try JSONEncoder().encode(house);var json=try JSONSerialization.jsonObject(with:data) as! [String:Any];json.removeValue(forKey:"references");let old=try JSONSerialization.data(withJSONObject:json);let decoded=try JSONDecoder().decode(House.self,from:old);return decoded.id==house.id && decoded.references.isEmpty && decoded.features==house.features}
            check("Stage composition isolates unfinished and finished session frames"){
                var h=House.empty("Stages");let a=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id),b=Segment(roomID:h.rooms[0].id,stageID:h.stages[1].id);h.segments=[a,b]
                for segment in h.segments{h.features.append(Feature(name:"Surface",trade:.unknown,roomID:segment.roomID,stageID:segment.stageID,kind:.observed,mesh:.box(center:V3(),size:V3(1,1,1)),segmentID:segment.id))}
                return SceneBuilder.features(h,options:SceneOptions(mode:.rough)).map{$0.segmentID}==[a.id] && SceneBuilder.features(h,options:SceneOptions(mode:.finished)).map{$0.segmentID}==[b.id] && SceneBuilder.features(h,options:SceneOptions(mode:.ghost)).count==1
            }
            check("Local store roundtrip"){try repo.save(house);return try repo.all().first==house}
            check("Revision recovery"){let original=house;house.revision+=1;house.name="Edited";try repo.save(house);return try repo.previous(house.id)==original}
            check("Failed candidate does not replace committed evidence"){
                let before=try repo.all().first;var bad=house;bad.features[0].mesh.triangles=[0,1,Int32.max]
                do{try repo.save(bad);return false}catch{return try repo.all().first==before}
            }
            check("Corrupt project is isolated without hiding healthy projects"){
                let isolated=try Repository(root:folder.appendingPathComponent("corrupt-row"));let good=House.empty("Healthy"),bad=House.empty("Corrupt");try isolated.save(good);try isolated.save(bad)
                var db:OpaquePointer?;guard sqlite3_open(isolated.root.appendingPathComponent("house.sqlite").path,&db)==SQLITE_OK else{return false};defer{sqlite3_close(db)}
                guard sqlite3_exec(db,"UPDATE projects SET json='broken' WHERE id='\(bad.id.uuidString)'",nil,nil,nil)==SQLITE_OK else{return false}
                let remaining=try isolated.all();return remaining.map{$0.id}==[good.id] && isolated.recoveryWarnings.count==1 && FileManager.default.fileExists(atPath:isolated.root.appendingPathComponent("recovery/"+bad.id.uuidString+".json").path)
            }
            check("Asset hash identity"){let a=try repo.put(Data("original".utf8),ext:"txt"),b=try repo.put(Data("original".utf8),ext:"txt");let read=try repo.read(a);return a==b && read==Data("original".utf8)}
            check("Unsafe paths rejected"){do{_=try repo.assetURL("../escape");return false}catch{return true}}
            check("Invalid mesh indices rejected"){!Mesh(vertices:[V3()],triangles:[0,1,2]).valid}
            check("Reject nonfinite mesh"){!Mesh(vertices:[V3(.nan,0,0)],triangles:[]).valid}
            check("Archive metadata and original roundtrip"){let key=try repo.put(Data("source drawing".utf8),ext:"txt");house.drawings.append(Drawing(name:"source.txt",asset:key));let url=try Exporter.archive(house,repo:repo);try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("test.hxray"));try FileManager.default.copyItem(at:url,to:mainRepo.root.appendingPathComponent("test.hxray"));let fresh=try Repository(root:folder.appendingPathComponent("restore"));let restored=try Exporter.restore(url,repo:fresh);let verified=try fresh.integrity(restored);return restored.id != house.id && restored.features==house.features && restored.assets==house.assets && verified==1}
            check("Corrupt archive rejected"){let url=try Exporter.archive(house,repo:repo);var bytes=try Data(contentsOf:url);bytes[60]^=0xff;let broken=folder.appendingPathComponent("broken.hxray");try bytes.write(to:broken);do{_=try Exporter.restore(broken,repo:repo);return false}catch{return true}}
            check("GLB framing and length"){let url=try Exporter.glb(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.glb"));return d.uint32(0)==0x46546c67 && d.uint32(4)==2 && Int(d.uint32(8))==d.count}
            check("PLY independent parser roundtrip"){let url=try Exporter.meshText(house,options:SceneOptions(),ply:true);let mesh=try PLYReader.read(Data(contentsOf:url));return mesh.valid && mesh.vertices.count==Exporter.canonicalFeatures(house,options:SceneOptions()).reduce(0){$0+$1.mesh.vertices.count}}
            check("USDZ stored and 64-byte aligned"){let url=try Exporter.usdz(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.usdz"));let entries=try StoredZip.read(url);let start=30+Int(d.uint16(26))+Int(d.uint16(28));return start%64==0 && entries.first?.name=="house.usda"}
            check("No tour across absent captured rooms"){let empty=House.empty("Uncaptured");let plan=TourDirector.plan(empty);return plan.shots.isEmpty && plan.excluded.count==1}
            check("Deterministic tour source revision"){let a=try JSONEncoder().encode(TourDirector.plan(house)),b=try JSONEncoder().encode(TourDirector.plan(house));let p=try JSONDecoder().decode(TourPlan.self,from:a),q=try JSONDecoder().decode(TourPlan.self,from:b);return Set(p.shots.map{$0.roomID}).count==3 && p.shots.allSatisfy{$0.duration<=5} && p.sourceRevision==q.sourceRevision && p.shots.map{$0.position}==q.shots.map{$0.position}}
            check("Tour cache separates layers and projects"){let plan=TourDirector.plan(house);let a=try MovieExporter.cacheKey(house:house,plan:plan,options:SceneOptions());let b=try MovieExporter.cacheKey(house:house,plan:plan,options:SceneOptions(mode:.finished));var other=house;other.id=UUID();let c=try MovieExporter.cacheKey(house:other,plan:plan,options:SceneOptions());return a != b && a != c}
            check("Walk collision and explicit doorway"){NavigationGeometry.allowed(V3(3,2,1.6),house:house) && !NavigationGeometry.allowed(V3(3,-0.1,1.6),house:house) && NavigationGeometry.allowed(V3(6.1,2.2,1.6),house:house) && !NavigationGeometry.allowed(V3(6.1,1,1.6),house:house)}
            check("SceneKit offscreen render"){let scene=SceneBuilder.scene(house,options:SceneOptions());let camera=SceneBuilder.camera(at:V3(13,-12,12));camera.look(at:SCNVector3(4,1,-2));scene.rootNode.addChildNode(camera);let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;let image=renderer.snapshot(atTime:0,with:CGSize(width:480,height:320),antialiasingMode:.none);try image.pngData()?.write(to:mainRepo.root.appendingPathComponent("test-render.png"));return image.cgImage.map{CaptureController.sharpness($0)>0.002} ?? false}
            check("Two-reference drift correction and inconsistent-board rejection"){
                var h=House.empty("Reference checks");let a=ReferenceBoard(name:"A",image:"a.png",pdf:"a.pdf",width:0.18),b=ReferenceBoard(name:"B",image:"b.png",pdf:"b.pdf",width:0.18);h.references=[a,b]
                var fixedA=Rigid().values,fixedB=Rigid().values;fixedA[3] = -0.5;fixedB[3]=0.5
                var s=Segment(roomID:h.rooms[0].id,stageID:h.stages[0].id);s.referencePoses=[ReferencePose(boardID:a.id,matrix:fixedA),ReferencePose(boardID:b.id,matrix:fixedB)]
                var movedA=fixedA,movedB=fixedB,camera=Rigid().values;movedA[3]+=0.1;movedB[3]+=0.1;camera[3]=0.1
                var o=Observation(roomID:s.roomID,stageID:s.stageID,segmentID:s.id,timestamp:0,image:"a.jpg",width:64,height:64,camera:camera,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1,referenceObservations:[ReferencePose(boardID:a.id,matrix:movedA),ReferencePose(boardID:b.id,matrix:movedB)])
                guard let corrected=PoseRefinement.refine(o,segment:s,house:h),abs(corrected.observation.camera[3])<1e-9,o.camera[3]==0.1 else{return false}
                movedB[3]+=0.2;o.referenceObservations=[ReferencePose(boardID:a.id,matrix:movedA),ReferencePose(boardID:b.id,matrix:movedB)]
                return PoseRefinement.refine(o,segment:s,house:h)==nil
            }
            check("Projection and occlusion rejection"){
                var depth=Data();for _ in 0..<64*64{depth.float(1)}
                let o=Observation(roomID:house.rooms[0].id,stageID:house.stages[0].id,segmentID:UUID(),timestamp:0,image:"fixture.jpg",width:64,height:64,camera:Rigid().values,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"normal",light:1000,sharpness:0.1)
                guard let (uv,z)=TextureBuilder.project(V3(0,1,0),through:o) else{return false}
                var withDepth=o;withDepth.depthWidth=64;withDepth.depthHeight=64
                let camera=TextureBuilder.Camera(observation:withDepth,depth:depth)
                return abs(uv.u-0.5)<1e-9 && abs(uv.v-0.5)<1e-9 && TextureBuilder.visible(uv,z:z,camera:camera) && !TextureBuilder.visible(uv,z:2,camera:camera)
            }
            do {
                guard let path=Bundle.main.url(forResource:"IFC",withExtension:nil)?.appendingPathComponent("test-block.ifc") else{throw HouseError.message("IFC test fixture missing.")}
                let importer=IFCImporter();let features=try await importer.load(Data(contentsOf:path),roomID:house.rooms[0].id,stageID:house.stages[0].id)
                let points=features.flatMap{$0.mesh.vertices};let extent=V3((points.map{$0.x}.max() ?? 0)-(points.map{$0.x}.min() ?? 0),(points.map{$0.y}.max() ?? 0)-(points.map{$0.y}.min() ?? 0),(points.map{$0.z}.max() ?? 0)-(points.map{$0.z}.min() ?? 0))
                results.append(["test":"Bundled IFC2x3 conversion and axes","passed":abs(extent.x-1)<0.001 && abs(extent.y-2)<0.001 && abs(extent.z-3)<0.001,"extent":[extent.x,extent.y,extent.z]])
                let source=try String(contentsOf:path,encoding:.utf8)
                let millimetres=source.replacingOccurrences(of:"IFC2X3",with:"IFC4").replacingOccurrences(of:".ELEMENT.",with:".NOTDEFINED.").replacingOccurrences(of:".LENGTHUNIT.,$,.METRE.",with:".LENGTHUNIT.,.MILLI.,.METRE.").replacingOccurrences(of:"#17,1.,2.",with:"#17,1000.,2000.").replacingOccurrences(of:"#18,#9,#7,3.",with:"#18,#9,#7,3000.").replacingOccurrences(of:"$,$,#15,#21",with:"$,$,#25,#21").replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:"#23=IFCCARTESIANPOINT((10000.,20000.,30000.));\n#24=IFCAXIS2PLACEMENT3D(#23,#7,#8);\n#25=IFCLOCALPLACEMENT(#15,#24);\nENDSEC;\nEND-ISO")
                let converted=try await importer.load(Data(millimetres.utf8),roomID:house.rooms[0].id,stageID:house.stages[0].id)
                let vertices=converted.flatMap{$0.mesh.vertices};let low=V3(vertices.map{$0.x}.min() ?? 0,vertices.map{$0.y}.min() ?? 0,vertices.map{$0.z}.min() ?? 0),high=V3(vertices.map{$0.x}.max() ?? 0,vertices.map{$0.y}.max() ?? 0,vertices.map{$0.z}.max() ?? 0)
                results.append(["test":"IFC4 millimetres and nested placement","passed":(low-V3(9.5,19,30)).length<0.001 && (high-V3(10.5,21,33)).length<0.001,"lower":[low.x,low.y,low.z],"upper":[high.x,high.y,high.z]])
            }catch{results.append(["test":"Bundled IFC2x3 conversion and axes","passed":false,"error":error.localizedDescription])}
            do {
                let fixture=try SimulatedCapture.make(repo:mainRepo);let feature=try await Reconstruction.fuse(house:fixture,segment:fixture.segments[0],repo:mainRepo){_ in}
                let surface=try await SurfaceReconstruction.build(house:fixture,segment:fixture.segments[0],repo:mainRepo){_ in}
                let surfaceError=surface.mesh.vertices.map{abs($0.y-2)}.max() ?? .infinity
                results.append(["test":"Native signed-distance surface fusion","passed":surface.mesh.valid && surface.mesh.triangles.count>300 && surfaceError<0.003,"vertices":surface.mesh.vertices.count,"maxPlaneErrorMetres":surfaceError,"syntheticOnly":true])
                var pointHouse=fixture;pointHouse.features=[feature]
                let pointGLB=try Exporter.glb(pointHouse,options:SceneOptions()),pointUSD=try Exporter.usdz(pointHouse,options:SceneOptions())
                for (from,name) in [(pointGLB,"points.glb"),(pointUSD,"points.usdz")]{let target=mainRepo.root.appendingPathComponent(name);try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:from,to:target)}
                let error=feature.mesh.vertices.map{abs($0.y-2)}.max() ?? .infinity
                let textured=try TextureBuilder.build(house:fixture,segment:fixture.segments[0],repo:mainRepo)
                var candidate=fixture;candidate.features=textured
                let glb=try Exporter.glb(candidate,options:SceneOptions());try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("textured.glb"));try FileManager.default.copyItem(at:glb,to:mainRepo.root.appendingPathComponent("textured.glb"))
                let usd=try Exporter.usdz(candidate,options:SceneOptions());try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("textured.usdz"));try FileManager.default.copyItem(at:usd,to:mainRepo.root.appendingPathComponent("textured.usdz"))
                results.append(["test":"Simulated camera to fusion and photo texture pipeline","passed":feature.mesh.vertices.count>100 && error<0.003 && textured.contains{$0.texture != nil},"points":feature.mesh.vertices.count,"maxPlaneErrorMetres":error,"syntheticOnly":true])
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
            if ProcessInfo.processInfo.arguments.contains("--video-test") {
                do {let movie=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:5,width:640,height:360){_ in};try? FileManager.default.removeItem(at:mainRepo.root.appendingPathComponent("test-tour.mp4"));try FileManager.default.copyItem(at:movie,to:mainRepo.root.appendingPathComponent("test-tour.mp4"));results.append(["test":"Native MP4 encode, assembly and duration","passed":true])}catch{results.append(["test":"Native MP4 encode, assembly and duration","passed":false,"error":error.localizedDescription])}
            }
        }catch{results.append(["test":"Test harness setup","passed":false,"error":error.localizedDescription])}
        #if targetEnvironment(simulator)
        let platform="iPhone simulator"
        #else
        let platform="physical iPhone"
        #endif
        let report:[String:Any]=["platform":platform,"date":ISO8601DateFormatter().string(from:Date()),"tests":results,"passed":results.allSatisfy{($0["passed"] as? Bool)==true},"fieldAccuracyValidated":false,"precisionProfileEnabled":false]
        do{let bytes=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try bytes.write(to:mainRepo.root.appendingPathComponent("self-test.json"),options:.atomic)}catch{model.error=error.localizedDescription}
        try? FileManager.default.removeItem(at:folder)
    }
}
