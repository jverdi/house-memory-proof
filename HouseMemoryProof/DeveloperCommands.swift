import CryptoKit
import Foundation
import Metal
import SceneKit
import UIKit

// Internal, file-based diagnostics. The launch adapter is DEBUG/simulator only;
// no network listener, project import, original mutation or Apple operation.
@MainActor enum DeveloperCommands {
  struct Request:Codable {
    var schema:Int
    var command:String
    var houseSHA256:String
    var preset:String
    var duration:Double
  }
  struct ReconstructionRequest:Codable {
    var schema:Int;var command:String;var houseSHA256:String;var kind:String;var segmentID:UUID?
  }
  private struct Header:Decodable {var command:String}
  static func validateFolder(_ folder:URL)throws {
    for name in ["request.json","input","input/assets","output"] {
      let url=folder.appendingPathComponent(name)
      guard url.resolvingSymlinksInPath().path==url.standardizedFileURL.path else{throw HouseError.message("Command directories may not contain symlinks.")}
    }
  }
  static func readInput(folder:URL,expectedHash:String)throws->(House,URL) {
    let input=folder.appendingPathComponent("input"),metadataURL=input.appendingPathComponent("house.json")
    guard metadataURL.resolvingSymlinksInPath().path==metadataURL.standardizedFileURL.path else{throw HouseError.message("Command input may not contain symlinks.")}
    let bytes=try DurableFiles.read(metadataURL,limit:100_000_000)
    let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    guard hash==expectedHash else{throw HouseError.message("Command input changed after staging.")}
    let house=try JSONDecoder().decode(House.self,from:bytes);try house.validate()
    let assets=input.appendingPathComponent("assets")
    for key in house.assets {
      let url=assets.appendingPathComponent(key)
      guard url.resolvingSymlinksInPath().path==url.standardizedFileURL.path,
        try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true,
        key.hasPrefix(try StreamingArchive.digest(url).sha+".") else{throw HouseError.message("Command original is missing, unsafe or has changed bytes.")}
    }
    return (house,assets)
  }
  static func execute(folder:URL)throws->[String:Any] {
    try validateFolder(folder)
    let request=try JSONDecoder().decode(Request.self,from:DurableFiles.read(folder.appendingPathComponent("request.json"),limit:4096))
    guard request.schema==1,request.command=="tour",request.duration.isFinite,(5...60).contains(request.duration),
      let preset=["overview":TourPreset.overview,"before-after":.beforeAfter,"services":.services][request.preset] else{throw HouseError.message("Unsupported developer command or tour request.")}
    let (house,assets)=try readInput(folder:folder,expectedHash:request.houseSHA256),hash=request.houseSHA256
    let options=SceneOptions(),plan=TourDirector.plan(house,duration:request.duration,options:options,preset:preset)
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
    let planBytes=try encoder.encode(plan)
    let output=folder.appendingPathComponent("output")
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    try DurableFiles.write(planBytes,to:output.appendingPathComponent("tour.json"))
    try DurableFiles.write(TourProvenance.metadata(house),to:output.appendingPathComponent("source-metadata.json"))
    guard !plan.shots.isEmpty else{return ["passed":false,"command":"tour","houseSHA256":hash,"sourceRevision":house.revision,"excluded":plan.excluded,"error":"No supported tour viewpoint. Inspect the excluded regions in tour.json.","physicalQualification":false]}
    var previews:[String]=[]
    // Bounded storyboard; the complete deterministic timeline stays in JSON.
    let count=min(8,plan.shots.count)
    for index in 0..<count {
      let shotIndex=index*plan.shots.count/count,shot=plan.shots[shotIndex]
      let name="preview-\(shotIndex).png"
      let png:Data?=try autoreleasepool {
        let scene=try TourReveal.scene(house,shot:shot,options:options,assetRoot:assets)
        TourReveal.apply(shot,to:scene,phase:(shot.startPhase+shot.endPhase)/2)
        let pose=TourDirector.camera(shot,phase:(shot.startPhase+shot.endPhase)/2),camera=SceneBuilder.camera(at:pose.0,yaw:pose.1,pitch:pose.2)
        scene.rootNode.addChildNode(camera)
        let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
        renderer.scene=scene;renderer.pointOfView=camera
        return renderer.snapshot(atTime:0,with:CGSize(width:640,height:360),antialiasingMode:.none).pngData()
      }
      guard let png else{throw HouseError.message("Tour storyboard could not render.")}
      try DurableFiles.write(png,to:output.appendingPathComponent(name));previews.append(name)
    }
    return ["passed":true,"command":"tour","houseSHA256":hash,"sourceRevision":house.revision,
      "appSource":Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local",
      "shots":plan.shots.count,"frames":plan.shots.reduce(0){$0+Int(($1.duration*30).rounded())},
      "excluded":plan.excluded,"previews":previews,"previewShotLimit":8,"originalsVerified":house.assets.count,
      "synthetic":house.isDemo,"physicalQualification":false,"sourceModified":false]
  }
  static func reconstruct(folder:URL)async throws->[String:Any] {
    try validateFolder(folder)
    let request=try JSONDecoder().decode(ReconstructionRequest.self,from:DurableFiles.read(folder.appendingPathComponent("request.json"),limit:4096))
    guard request.schema==1,request.command=="reconstruct",["points","surface","complete"].contains(request.kind) else{throw HouseError.message("Unsupported reconstruction request.")}
    let (original,_)=try readInput(folder:folder,expectedHash:request.houseSHA256)
    guard original.revision>=0,original.revision<Int.max else{throw HouseError.message("Source revision cannot advance.")}
    let selected=original.segments.filter{request.segmentID==nil || $0.id==request.segmentID}
    guard !selected.isEmpty,selected.count<=100 else{throw HouseError.message("Select one to 100 saved sessions, or choose an individual segment for a larger archive.")}
    let repo=try Repository(root:folder.appendingPathComponent("input"))
    var candidate=original,rows:[[String:Any]]=[]
    let progressURL=folder.appendingPathComponent("progress.json")
    for (index,segment) in selected.enumerated() {
      try Task.checkCancellation()
      let progress:@MainActor (String,Double)->Void={name,fraction in
        let value:[String:Any]=["action":name,"completedSessions":index,"sessions":selected.count,"fraction":(Double(index)+fraction)/Double(selected.count)]
        if let bytes=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]){try? DurableFiles.write(bytes,to:progressURL)}
      }
      do {
        let before=candidate.features.count
        if request.kind=="complete" {
          candidate=try await CaptureProcessing.build(house:candidate,segmentID:segment.id,repo:repo,progress:progress)
          guard let report=candidate.processingReports.first(where:{$0.segmentID==segment.id}) else{throw HouseError.message("Processing returned no stage report.")}
          rows.append(["segmentID":segment.id.uuidString,"passed":report.complete,"featuresAdded":candidate.features.count-before,
            "steps":report.steps.map{["name":$0.name,"passed":$0.passed,"detail":$0.detail] as [String:Any]}])
        }else{
          let feature:Feature
          if request.kind=="points" {feature=try await Reconstruction.fuse(house:candidate,segment:segment,repo:repo){progress("Fusing depth points",$0)}}
          else {feature=try await SurfaceReconstruction.build(house:candidate,segment:segment,repo:repo){progress("Reconstructing depth surfaces",$0)}}
          for i in candidate.features.indices where candidate.features[i].segmentID==segment.id && [GeometrySource.depthPoints,.depthFusion,.photoTexture].contains(candidate.features[i].resolvedGeometrySource ?? .capturedMesh) {
            candidate.features[i].artifactValid=false;candidate.features[i].hidden=true
          }
          candidate.features.append(feature)
          rows.append(["segmentID":segment.id.uuidString,"passed":true,"featuresAdded":1,"vertices":feature.mesh.vertices.count,"triangles":feature.mesh.triangles.count/3])
        }
      }catch is CancellationError {throw CancellationError()}
      catch {rows.append(["segmentID":segment.id.uuidString,"passed":false,"error":error.localizedDescription])}
    }
    candidate.revision=original.revision+1
    try candidate.validate()
    let verified=try repo.integrity(original)
    let originalEvidence=original.assets.subtracting(Set(original.visualMaps.map{$0.asset}))
    guard candidate.observations==original.observations,originalEvidence.isSubset(of:candidate.assets),
      try StreamingArchive.digest(folder.appendingPathComponent("input/house.json")).sha==request.houseSHA256 else{throw HouseError.message("Reconstruction did not preserve its original evidence.")}
    let output=folder.appendingPathComponent("output");try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let archiveHouse=candidate
    let archive=try await LocalWorker.run(priority:.utility){try Exporter.archive(archiveHouse,repo:repo)}
    defer{try? FileManager.default.removeItem(at:archive)}
    try FileManager.default.copyItem(at:archive,to:output.appendingPathComponent("reconstruction.hxray"))
    return ["passed":rows.allSatisfy{($0["passed"] as? Bool)==true},"completed":true,"command":"reconstruct","kind":request.kind,
      "houseSHA256":request.houseSHA256,"sourceRevision":original.revision,"outputRevision":candidate.revision,"archive":"reconstruction.hxray",
      "appSource":Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local","sessions":rows,"originalsVerified":verified,
      "physicalQualification":false,"sourceModified":false,"synthetic":candidate.isDemo]
  }
  static func launch(_ name:String,root:URL)async {
    guard let id=UUID(uuidString:name),id.uuidString==name.uppercased() else{return}
    let folder=root.appendingPathComponent("developer-commands").appendingPathComponent(id.uuidString)
    guard folder.resolvingSymlinksInPath().path==folder.standardizedFileURL.path else{return}
    let result:[String:Any]
    do {
      try validateFolder(folder)
      let header=try JSONDecoder().decode(Header.self,from:DurableFiles.read(folder.appendingPathComponent("request.json"),limit:4096))
      if header.command=="reconstruct" {result=try await reconstruct(folder:folder)}else{result=try execute(folder:folder)}
    }
    catch {result=["passed":false,"error":error.localizedDescription,"physicalQualification":false]}
    if let bytes=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]) {
      try? DurableFiles.write(bytes,to:folder.appendingPathComponent("result.json"))
    }
  }
}
