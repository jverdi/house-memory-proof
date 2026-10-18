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
  static func execute(folder:URL)throws->[String:Any] {
    for name in ["request.json","input","input/assets","output"] {
      let url=folder.appendingPathComponent(name)
      guard url.resolvingSymlinksInPath().path==url.standardizedFileURL.path else{throw HouseError.message("Command directories may not contain symlinks.")}
    }
    let request=try JSONDecoder().decode(Request.self,from:DurableFiles.read(folder.appendingPathComponent("request.json"),limit:4096))
    guard request.schema==1,request.command=="tour",request.duration.isFinite,(5...60).contains(request.duration),
      let preset=["overview":TourPreset.overview,"before-after":.beforeAfter,"services":.services][request.preset] else{throw HouseError.message("Unsupported developer command or tour request.")}
    let input=folder.appendingPathComponent("input"),metadataURL=input.appendingPathComponent("house.json")
    guard metadataURL.resolvingSymlinksInPath().path==metadataURL.standardizedFileURL.path else{throw HouseError.message("Command input may not contain symlinks.")}
    let bytes=try DurableFiles.read(metadataURL,limit:100_000_000)
    let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    guard hash==request.houseSHA256 else{throw HouseError.message("Command input changed after staging.")}
    let house=try JSONDecoder().decode(House.self,from:bytes);try house.validate()
    let assets=input.appendingPathComponent("assets")
    for key in house.assets {
      let url=assets.appendingPathComponent(key)
      guard url.resolvingSymlinksInPath().path==url.standardizedFileURL.path,
        try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true,
        key.hasPrefix(try StreamingArchive.digest(url).sha+".") else{throw HouseError.message("Command original is missing, unsafe or has changed bytes.")}
    }
    let options=SceneOptions(),plan=TourDirector.plan(house,duration:request.duration,options:options,preset:preset)
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
    let planBytes=try encoder.encode(plan)
    let output=folder.appendingPathComponent("output")
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    try DurableFiles.write(planBytes,to:output.appendingPathComponent("tour.json"))
    guard !plan.shots.isEmpty else{return ["passed":false,"command":"tour","houseSHA256":hash,"sourceRevision":house.revision,"excluded":plan.excluded,"error":"No supported tour viewpoint. Inspect the excluded regions in tour.json.","physicalQualification":false]}
    var previews:[String]=[]
    // Bounded storyboard; the complete deterministic timeline stays in JSON.
    let count=min(8,plan.shots.count)
    for index in 0..<count {
      let shotIndex=index*plan.shots.count/count,shot=plan.shots[shotIndex]
      let name="preview-\(shotIndex).png"
      let png:Data?=autoreleasepool {
        let scope=SceneOptions(mode:shot.layerMode.flatMap(ViewMode.init(rawValue:)) ?? options.mode,trades:shot.tradeNames.map{Set($0.compactMap(Trade.init(rawValue:)))} ?? options.trades,ceilings:options.ceilings,room:shot.roomID,stage:nil)
        let scene=SceneBuilder.scene(house,options:scope,assetRoot:assets)
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
  static func launch(_ name:String,root:URL) {
    guard let id=UUID(uuidString:name),id.uuidString==name.uppercased() else{return}
    let folder=root.appendingPathComponent("developer-commands").appendingPathComponent(id.uuidString)
    guard folder.resolvingSymlinksInPath().path==folder.standardizedFileURL.path else{return}
    let result:[String:Any]
    do {result=try execute(folder:folder)}
    catch {result=["passed":false,"command":"tour","error":error.localizedDescription,"physicalQualification":false]}
    if let bytes=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted]) {
      try? DurableFiles.write(bytes,to:folder.appendingPathComponent("result.json"))
    }
  }
}
