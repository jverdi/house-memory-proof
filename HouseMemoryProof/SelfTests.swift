import Foundation
import SceneKit
import PDFKit
import SQLite3
import ImageIO
import AVFoundation
import UIKit
import Darwin

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
            await check("Multi-board pose holds out each board and rejects moved or duplicate references") {var error=0.0;return hx_reference_selftest(&error)==1 && error<0.003}
            await check("Pinned AprilTag identity, corner coordinates, rotation and duplicate rejection") {hx_tag_selftest()==1}
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
            await check("Display reduction stays bounded and preserves source triangles and UVs") {
                let mesh=Mesh.box(center:V3(),size:V3(2,3,4)),uv=mesh.vertices.map{UV(u:$0.x,v:$0.y)}
                let reduced=DisplayGeometry.reduce(mesh,uv:uv,budget:9)
                guard reduced.0.valid,reduced.0.vertices.count<=9,reduced.0.triangles.count<=9,reduced.1?.count==reduced.0.vertices.count else{return false}
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
                guard map.points.contains(where:{optimized.contains($0)}) else{return false}
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
                return supported.supported>0 && blocked.supported==0 && blocked.states.contains(3) && unknown.states.allSatisfy{$0==0}
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
            await check("Rendered corner images localize held query viewpoints without pose input"){
                let resources=Bundle.main.url(forResource:"IFC",withExtension:nil)!
                let capture=try Exporter.restore(resources.appendingPathComponent("vision-map.hxray"),repo:repo)
                let map=try VisualMapping.build(house:capture,segment:capture.segments[0],repo:repo)
                let evaluator=try JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("vision-queries.json"))) as! [String:Any]
                var matched=0;var worst=0.0
                for query in evaluator["queries"] as! [[String:Any]] {
                    let(gray,w,h)=try VisualMapping.image(Data(contentsOf:resources.appendingPathComponent(query["image"] as! String)))
                    let features=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
                    let result=VisualMapping.query(features,width:query["width"] as! Int,height:query["height"] as! Int,intrinsics:query["intrinsics"] as! [Double],map:map)
                    if query["shouldMatch"] as! Bool {
                        if let result {guard VisualMapping.competingMatch(features,width:query["width"] as! Int,height:query["height"] as! Int,intrinsics:query["intrinsics"] as! [Double],maps:[map]) else{throw HouseError.message("A duplicated visual room was not flagged as a competing match.")};let a=result.transform.values,b=query["expectedCamera"] as! [Double];let error=(V3(a[3],a[7],a[11])-V3(b[3],b[7],b[11])).length;worst=max(worst,error);matched+=1}
                    }else if result != nil {throw HouseError.message("Unrelated texture was incorrectly localized.")}
                }
                guard matched>=2,worst<0.03 else{throw HouseError.message("Image localization: \(matched)/3 held views, worst accepted position error \(worst) m, \(map.points.count) map features.")}
                return true
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
            await check("Additive schema migration preserves original identity"){let data=try JSONEncoder().encode(house);var json=try JSONSerialization.jsonObject(with:data) as! [String:Any];json.removeValue(forKey:"references");let old=try JSONSerialization.data(withJSONObject:json);let decoded=try JSONDecoder().decode(House.self,from:old);return decoded.id==house.id && decoded.references.isEmpty && decoded.features==house.features}
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
            await check("Local store roundtrip"){try repo.save(house);return try repo.all().first==house}
            await check("Revision recovery"){let original=house;house.revision+=1;house.name="Edited";try repo.save(house);return try repo.previous(house.id)==original}
            await check("Failed candidate does not replace committed evidence"){
                let before=try repo.all().first;var bad=house;bad.features[0].mesh.triangles=[0,1,Int32.max]
                do{try repo.save(bad);return false}catch{return try repo.all().first==before}
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
                var missing=feature;missing.texture=String(repeating:"0",count:64)+".png"
                do{_=try Exporter.exportAssets([missing],textGeometry:false,root:root);return false}catch{}
                let original=try repo.assetURL(key);try Data([1,2,3]).write(to:original)
                do{_=try Exporter.verifiedTexture(key,assets:assets);return false}catch{}
                try bytes.write(to:original)
                return true
            }
            await check("PLY independent parser roundtrip"){let url=try Exporter.meshText(house,options:SceneOptions(),ply:true);let mesh=try PLYReader.read(Data(contentsOf:url));return mesh.valid && mesh.vertices.count==Exporter.canonicalFeatures(house,options:SceneOptions()).reduce(0){$0+$1.mesh.vertices.count}}
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
            await check("Tour path rejects observed wall and accepts supported camera corridor"){
                var h=House.empty("Path test");let r=h.rooms[0],stage=h.stages[0],segment=Segment(roomID:r.id,stageID:stage.id);h.segments=[segment]
                for i in 0..<2 {var m=Rigid().values;m[3]=Double(i)*0.5;m[7]=1.6;h.observations.append(Observation(roomID:r.id,stageID:stage.id,segmentID:segment.id,timestamp:Double(i),image:"camera.jpg",width:64,height:64,camera:m,intrinsics:[32,0,32,0,32,32,0,0,1],tracking:"synthetic",light:1000,sharpness:0.1))}
                h.features=[Feature(name:"Captured floor",trade:.floor,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:V3(0,0,-0.1),size:V3(3,3,0.1)),segmentID:segment.id)]
                let a=V3(0,0,1.6),b=V3(0.5,0,1.6),options=SceneOptions()
                guard TourDirector.clearPath(a,b,house:h,options:options,clearance:SpatialClearance(features:Exporter.canonicalFeatures(h,options:options))),TourDirector.plan(h).shots.contains(where:{$0.endPosition != nil}) else{return false}
                h.features=[Feature(name:"Blocking wall",trade:.structure,roomID:r.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:V3(0.25,0,1.6),size:V3(0.1,2,2)),segmentID:segment.id)]
                return !TourDirector.clearPath(a,b,house:h,options:options,clearance:SpatialClearance(features:Exporter.canonicalFeatures(h,options:options))) && TourDirector.plan(h).shots.allSatisfy{$0.endPosition==nil}
            }
            await check("Moving tour uses short-angle interpolation and endpoint continuity"){
                let shot=TourShot(roomID:UUID(),position:V3(),yaw:179*Double.pi/180,pitch:0,caption:"test",duration:5,endPosition:V3(1,0,0),endYaw: -179*Double.pi/180,endPitch:0.2)
                let a=TourDirector.camera(shot,phase:0),m=TourDirector.camera(shot,phase:0.5),b=TourDirector.camera(shot,phase:1)
                return a.0==V3() && b.0==V3(1,0,0) && abs(m.0.x-0.5)<1e-10 && abs(m.1-Double.pi)<1e-10 && abs(m.2-0.1)<1e-10
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
                let camera=TextureBuilder.Camera(observation:withDepth,depth:depth)
                return abs(uv.u-0.5)<1e-9 && abs(uv.v-0.5)<1e-9 && TextureBuilder.visible(uv,z:z,camera:camera) && !TextureBuilder.visible(uv,z:2,camera:camera)
            }
            do {
                guard let path=Bundle.main.url(forResource:"IFC",withExtension:nil)?.appendingPathComponent("test-block.ifc") else{throw HouseError.message("IFC test fixture missing.")}
                let importer=IFCImporter(),input=try Data(contentsOf:path),roomID=house.rooms[0].id,stageID=house.stages[0].id
                let cancelled=Task {try await importer.load(input,roomID:roomID,stageID:stageID)}
                await Task.yield();cancelled.cancel()
                do{_=try await cancelled.value;throw HouseError.message("Cancelled IFC import unexpectedly published geometry.")}catch is CancellationError{}
                let features=try await importer.load(input,roomID:roomID,stageID:stageID)
                let points=features.flatMap{$0.mesh.vertices};let extent=V3((points.map{$0.x}.max() ?? 0)-(points.map{$0.x}.min() ?? 0),(points.map{$0.y}.max() ?? 0)-(points.map{$0.y}.min() ?? 0),(points.map{$0.z}.max() ?? 0)-(points.map{$0.z}.min() ?? 0))
                results.append(["test":"Bundled IFC2x3 conversion and axes","passed":abs(extent.x-1)<0.001 && abs(extent.y-2)<0.001 && abs(extent.z-3)<0.001,"extent":[extent.x,extent.y,extent.z]])
                let source=try String(contentsOf:path,encoding:.utf8)
                let millimetres=source.replacingOccurrences(of:"IFC2X3",with:"IFC4").replacingOccurrences(of:".ELEMENT.",with:".NOTDEFINED.").replacingOccurrences(of:".LENGTHUNIT.,$,.METRE.",with:".LENGTHUNIT.,.MILLI.,.METRE.").replacingOccurrences(of:"#17,1.,2.",with:"#17,1000.,2000.").replacingOccurrences(of:"#18,#9,#7,3.",with:"#18,#9,#7,3000.").replacingOccurrences(of:"$,$,#15,#21",with:"$,$,#25,#21").replacingOccurrences(of:"ENDSEC;\nEND-ISO",with:"#23=IFCCARTESIANPOINT((10000.,20000.,30000.));\n#24=IFCAXIS2PLACEMENT3D(#23,#7,#8);\n#25=IFCLOCALPLACEMENT(#15,#24);\nENDSEC;\nEND-ISO")
                let converted=try await importer.load(Data(millimetres.utf8),roomID:house.rooms[0].id,stageID:house.stages[0].id)
                let vertices=converted.flatMap{$0.mesh.vertices};let low=V3(vertices.map{$0.x}.min() ?? 0,vertices.map{$0.y}.min() ?? 0,vertices.map{$0.z}.min() ?? 0),high=V3(vertices.map{$0.x}.max() ?? 0,vertices.map{$0.y}.max() ?? 0,vertices.map{$0.z}.max() ?? 0)
                results.append(["test":"IFC4 millimetres and nested placement","passed":(low-V3(9.5,19,30)).length<0.001 && (high-V3(10.5,21,33)).length<0.001,"lower":[low.x,low.y,low.z],"upper":[high.x,high.y,high.z]])
            }catch{results.append(["test":"Bundled IFC2x3 conversion and axes","passed":false,"error":error.localizedDescription])}
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
            if includeMovie || ProcessInfo.processInfo.arguments.contains("--video-test") {
                mark("100-space scene capacity")
                do{results.append(try await largeSceneReport(repo:mainRepo))}
                catch{results.append(["test":"100-space two-stage capacity and native streamed render","passed":false,"error":error.localizedDescription])}
                do {
                    mark("1080p30 movie encode and cache reuse")
                    let started=ProcessInfo.processInfo.systemUptime
                    let movie=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:10,width:1920,height:1080){model.progress=$0}
                    let directory=repo.root.appendingPathComponent("tours"),all=FileManager.default.enumerator(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])!
                    var dates:[URL:Date]=[:]
                    for case let url as URL in all where url.pathExtension=="mp4" {dates[url]=try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate}
                    _=try await MovieExporter.render(house,repo:repo,options:SceneOptions(),duration:10,width:1920,height:1080){_ in}
                    let reused=try !dates.isEmpty && dates.allSatisfy{try $0.key.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate==$0.value}
                    let target=mainRepo.root.appendingPathComponent("test-tour.mp4");try? FileManager.default.removeItem(at:target);try FileManager.default.copyItem(at:movie,to:target)
                    let generator=AVAssetImageGenerator(asset:AVURLAsset(url:target));let frame=try await generator.image(at:CMTime(seconds:1,preferredTimescale:30))
                    try UIImage(cgImage:frame.image).pngData()?.write(to:mainRepo.root.appendingPathComponent("test-tour-frame.png"))
                    results.append(["test":"1080p30 MP4 encode, decode and verified chunk reuse","passed":reused,"width":1920,"height":1080,"durationSeconds":10,"seconds":ProcessInfo.processInfo.systemUptime-started])
                }catch{results.append(["test":"1080p30 MP4 encode, decode and verified chunk reuse","passed":false,"error":error.localizedDescription])}
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
    // Read the process footprint, not total installed device RAM. This is a
    // sampled observation; the kernel's resident peak also includes earlier work.
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
        var frameTimes:[Double]=[],memories:[[String:UInt64]]=[],sharpFrames=0,loads:[Double]=[],collisionCounts:[Int]=[],textureCounts:[Int]=[],decodedBytes:[Int]=[]
        for (visit,roomIndex) in [0,99].enumerated() {
            let room=h.rooms[roomIndex],position=room.origin+V3(2.5,-1,1.5),start=ProcessInfo.processInfo.systemUptime
            camera.simdPosition=position.render;camera.look(at:SCNVector3((room.origin+V3(2.5,4.8,1.5)).render))
            // Drain the same one-tile updates as the interactive view. The
            // synthetic clock drives residency only, never the reported timing.
            for tick in 0..<513 {try Task.checkCancellation();stream.update(camera:position,time:Double(visit*1000+tick)/30);if tick%16==0 {await Task.yield()}}
            guard stream.pending.isEmpty,stream.nodes.count<=512,stream.allocations.values.reduce(0,{$0+$1.budget})<=DisplayGeometry.sceneVertexBudget else{throw HouseError.message("Capacity scene did not settle within its residency budget.")}
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
        report["limitations"]="Synthetic tiled walls with procedural textures, local original-geometry collision and no capture data. Decoded raster bounds exclude GPU/driver allocations. Offscreen snapshot time includes readback; it is not sustained display FPS, device thermal qualification, reconstruction completeness or navigation-topology evidence."
        report["physicalDeviceQualified"]=false
        return report
    }
}
