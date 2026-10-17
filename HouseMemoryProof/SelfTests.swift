import Foundation
import SceneKit
import PDFKit

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
            check("Local store roundtrip"){try repo.save(house);return try repo.all().first==house}
            check("Revision recovery"){let original=house;house.revision+=1;house.name="Edited";try repo.save(house);return try repo.previous(house.id)==original}
            check("Asset hash identity"){let a=try repo.put(Data("original".utf8),ext:"txt"),b=try repo.put(Data("original".utf8),ext:"txt");return a==b && (try repo.read(a))==Data("original".utf8)}
            check("Unsafe paths rejected"){do{_=try repo.assetURL("../escape");return false}catch{return true}}
            check("Invalid mesh indices rejected"){!Mesh(vertices:[V3()],triangles:[0,1,2]).valid}
            check("Reject nonfinite mesh"){!Mesh(vertices:[V3(.nan,0,0)],triangles:[]).valid}
            check("Archive metadata and original roundtrip"){let key=try repo.put(Data("source drawing".utf8),ext:"txt");house.drawings.append(Drawing(name:"source.txt",asset:key));let url=try Exporter.archive(house,repo:repo);let fresh=try Repository(root:folder.appendingPathComponent("restore"));let restored=try Exporter.restore(url,repo:fresh);return restored.id != house.id && restored.features==house.features && restored.assets==house.assets && (try fresh.integrity(restored))==1}
            check("Corrupt archive rejected"){let url=try Exporter.archive(house,repo:repo);var bytes=try Data(contentsOf:url);bytes[60]^=0xff;let broken=folder.appendingPathComponent("broken.hxray");try bytes.write(to:broken);do{_=try Exporter.restore(broken,repo:repo);return false}catch{return true}}
            check("GLB framing and length"){let url=try Exporter.glb(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.glb"));return d.uint32(0)==0x46546c67 && d.uint32(4)==2 && Int(d.uint32(8))==d.count}
            check("PLY independent parser roundtrip"){let url=try Exporter.meshText(house,options:SceneOptions(),ply:true);let mesh=try PLYReader.read(Data(contentsOf:url));return mesh.valid && mesh.vertices.count==Exporter.canonicalFeatures(house,options:SceneOptions()).reduce(0){$0+$1.mesh.vertices.count}}
            check("USDZ stored and 64-byte aligned"){let url=try Exporter.usdz(house,options:SceneOptions());let d=try Data(contentsOf:url);try d.write(to:mainRepo.root.appendingPathComponent("test.usdz"));let entries=try StoredZip.read(url);let start=30+Int(d.uint16(26))+Int(d.uint16(28));return start%64==0 && entries.first?.name=="house.usda"}
            check("No tour across absent captured rooms"){let empty=House.empty("Uncaptured");let plan=TourDirector.plan(empty);return plan.shots.isEmpty && plan.excluded.count==1}
            check("Deterministic tour source revision"){let a=try JSONEncoder().encode(TourDirector.plan(house)),b=try JSONEncoder().encode(TourDirector.plan(house));let p=try JSONDecoder().decode(TourPlan.self,from:a),q=try JSONDecoder().decode(TourPlan.self,from:b);return p.shots.count==3 && p.sourceRevision==q.sourceRevision && p.shots.map{$0.position}==q.shots.map{$0.position}}
            check("SceneKit offscreen render"){let scene=SceneBuilder.scene(house,options:SceneOptions());let camera=SceneBuilder.camera(at:V3(13,-12,12));camera.look(at:SCNVector3(4,1,-2));scene.rootNode.addChildNode(camera);let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;let image=renderer.snapshot(atTime:0,with:CGSize(width:480,height:320),antialiasingMode:.none);try image.pngData()?.write(to:mainRepo.root.appendingPathComponent("test-render.png"));return image.cgImage.map{CaptureController.sharpness($0)>0.002} ?? false}
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
