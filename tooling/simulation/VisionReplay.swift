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
      print(String(data:try JSONSerialization.data(withJSONObject:["passed":status==1,"status":status,"maxPositionErrorMetres":maximum,"randomCorrespondenceFalseAccepts":falseAccepts,"positiveCases":200,"negativeCases":300,"imageQualification":false],options:[.sortedKeys]),encoding:.utf8)!)
      guard status==1 else{throw HouseError.message("Native vision diagnostics failed.")};return
    }
    guard CommandLine.arguments.count==3 else{throw HouseError.message("Usage: vision-replay candidate-directory query-specification.json")}
    let root=URL(fileURLWithPath:CommandLine.arguments[1]),queriesURL=URL(fileURLWithPath:CommandLine.arguments[2])
    let house=try JSONDecoder().decode(House.self,from:Data(contentsOf:root.appendingPathComponent("house.json")));try house.validate()
    guard let segment=house.segments.first else{throw HouseError.message("No mapping segment.")}
    let map=try VisualMapping.build(house:house,segment:segment,repo:DiskEvidence(root))
    let queries=try JSONDecoder().decode(ReplayQueries.self,from:Data(contentsOf:queriesURL))
    var output:[[String:Any]]=[]
    for q in queries.queries {
      guard !q.image.contains("/"),!q.image.contains("..") else{throw HouseError.message("Unsafe query image path.")}
      let(gray,w,h)=try VisualMapping.image(Data(contentsOf:queriesURL.deletingLastPathComponent().appendingPathComponent(q.image)))
      let features=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
      let start=Date();let pose=VisualMapping.query(features,width:q.width,height:q.height,intrinsics:q.intrinsics,map:map)
      var result:[String:Any]=["image":q.image,"accepted":pose != nil,"queryFeatures":features.count,"seconds":Date().timeIntervalSince(start)]
      if let pose{result["worldFromARCamera"]=pose.transform.values;result["inliers"]=pose.inliers;result["rmsPixels"]=pose.rms;result["sourceIDs"]=pose.sources.map{$0.uuidString}}
      output.append(result)
    }
    print(String(data:try JSONSerialization.data(withJSONObject:["candidateFingerprint":map.fingerprint,"mapFeatures":map.points.count,"mapViews":map.views.count,"queries":output],options:[.sortedKeys]),encoding:.utf8)!)
  }
}
