import Foundation

struct ReplayQuery:Decodable {var image:String;var width:Int;var height:Int;var intrinsics:[Double]}
struct ReplayQueries:Decodable {var queries:[ReplayQuery]}
final class DiskEvidence:EvidenceAssetReader {
  let root:URL
  init(_ root:URL){self.root=root}
  func read(_ key:String)throws->Data {
    guard !key.contains("/"),!key.contains(".."),!key.contains("\\") else{throw HouseError.message("Unsafe asset key.")}
    return try Data(contentsOf:root.appendingPathComponent("assets").appendingPathComponent(key))
  }
}
@main struct VisionReplay {
  static func main() throws {
    if CommandLine.arguments.contains("--self-test") {
      var maximum=0.0;var falseAccepts:UInt32=0
      let status=hx_vision_selftest(&maximum,&falseAccepts)
      var graphError=0.0;let graphStatus=hx_graph_selftest(&graphError)
      print(String(data:try JSONSerialization.data(withJSONObject:["passed":status==1 && graphStatus==1,"status":status,"graphStatus":graphStatus,"graphMaxPositionErrorMetres":graphError,"maxPositionErrorMetres":maximum,"randomCorrespondenceFalseAccepts":falseAccepts,"positiveCases":200,"negativeCases":300,"imageQualification":false],options:[.sortedKeys]),encoding:.utf8)!)
      guard graphStatus==1 else{throw HouseError.message("Graph diagnostics failed.")}
      guard status==1 else{throw HouseError.message("Native vision diagnostics failed.")};return
    }
    guard (3...5).contains(CommandLine.arguments.count),CommandLine.arguments.dropFirst(3).allSatisfy({["--refine","--bundle"].contains($0)}) else{throw HouseError.message("Usage: vision-replay candidate-directory query-specification.json")}
    let root=URL(fileURLWithPath:CommandLine.arguments[1]),queriesURL=URL(fileURLWithPath:CommandLine.arguments[2])
    var house=try JSONDecoder().decode(House.self,from:Data(contentsOf:root.appendingPathComponent("house.json")));try house.validate()
    guard let segment=house.segments.first else{throw HouseError.message("No mapping segment.")}
    var activeSegment=segment
    if CommandLine.arguments.contains("--refine") {activeSegment.poseSolution=try PoseGraph.build(house:house,segment:segment,repo:DiskEvidence(root));house.segments[0]=activeSegment}
    if CommandLine.arguments.contains("--bundle") {let result=try BundleRefinement.build(house:house,segment:activeSegment,repo:DiskEvidence(root));activeSegment.poseSolution=result.solution;house.segments[0]=activeSegment}
    let map=try VisualMapping.build(house:house,segment:activeSegment,repo:DiskEvidence(root))
    let queries=try JSONDecoder().decode(ReplayQueries.self,from:Data(contentsOf:queriesURL))
    var output:[[String:Any]]=[]
    for q in queries.queries {
      guard !q.image.contains("/"),!q.image.contains("..") else{throw HouseError.message("Unsafe query image path.")}
      let(gray,w,h)=try VisualMapping.image(Data(contentsOf:queriesURL.deletingLastPathComponent().appendingPathComponent(q.image)))
      let features=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
      var diagnostics:[String]=[]
      let start=Date();let pose=VisualMapping.query(features,width:q.width,height:q.height,intrinsics:q.intrinsics,map:map,diagnostic:{diagnostics.append($0)})
      var result:[String:Any]=["image":q.image,"diagnostics":diagnostics,"accepted":pose != nil,"queryFeatures":features.count,"seconds":Date().timeIntervalSince(start)]
      if let pose{result["worldFromARCamera"]=pose.transform.values;result["inliers"]=pose.inliers;result["rmsPixels"]=pose.rms;result["sourceIDs"]=pose.sources.map{$0.uuidString}}
      output.append(result)
    }
    print(String(data:try JSONSerialization.data(withJSONObject:["candidateFingerprint":map.fingerprint,"mapFeatures":map.points.count,"mapViews":map.views.count,"queries":output,"optimizedCameras":activeSegment.poseSolution?.cameras ?? [:],"bundleCheckRMS":activeSegment.poseSolution?.bundleCheckRMS as Any? ?? NSNull(),"bundlePointCount":activeSegment.poseSolution?.bundlePointCount as Any? ?? NSNull()],options:[.sortedKeys]),encoding:.utf8)!)
  }
}
