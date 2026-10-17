import Foundation

struct ReplayQuery:Decodable {var image:String;var width:Int;var height:Int;var intrinsics:[Double];var segmentID:UUID?}
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
    if CommandLine.arguments.count==3,CommandLine.arguments[1]=="--reference-codebook" {
      var book:[String:[UInt8]]=[:]
      for code in 0..<587 {
        var raster=[UInt8](repeating:0,count:100)
        guard raster.withUnsafeMutableBufferPointer({hx_tag_image(UInt32(code),$0.baseAddress,100)})==10 else{throw HouseError.message("Tag family raster failed.")}
        book[String(code)]=raster
      }
      try JSONSerialization.data(withJSONObject:book,options:[.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]));return
    }
    if CommandLine.arguments.contains("--self-test") {
      var maximum=0.0;var falseAccepts:UInt32=0
      let status=hx_vision_selftest(&maximum,&falseAccepts)
      var graphError=0.0;let graphStatus=hx_graph_selftest(&graphError)
      var referenceError=0.0;let referenceStatus=hx_reference_selftest(&referenceError)
      print(String(data:try JSONSerialization.data(withJSONObject:["passed":status==1 && graphStatus==1 && referenceStatus==1,"referenceStatus":referenceStatus,"referenceMaxPositionErrorMetres":referenceError,"referenceAnalyticCases":50,"sourceBoardAnalyticCases":25,"status":status,"graphStatus":graphStatus,"graphMaxPositionErrorMetres":graphError,"maxPositionErrorMetres":maximum,"randomCorrespondenceFalseAccepts":falseAccepts,"positiveCases":200,"negativeCases":300,"imageQualification":false],options:[.sortedKeys]),encoding:.utf8)!)
      fflush(stdout)
      guard referenceStatus==1 else{throw HouseError.message("Reference pose diagnostics failed at gate \(referenceStatus).") }
      guard graphStatus==1 else{throw HouseError.message("Graph diagnostics failed at gate \(graphStatus).")}
      guard status==1 else{throw HouseError.message("Native vision diagnostics failed.")};return
    }
    guard (3...7).contains(CommandLine.arguments.count),CommandLine.arguments.dropFirst(3).allSatisfy({["--refine","--bundle","--house","--coded"].contains($0)}) else{throw HouseError.message("Usage: vision-replay candidate-directory query-specification.json")}
    let root=URL(fileURLWithPath:CommandLine.arguments[1]),queriesURL=URL(fileURLWithPath:CommandLine.arguments[2])
    if CommandLine.arguments.contains("--coded"){try runCodedHouse(root:root,queriesURL:queriesURL);return}
    if CommandLine.arguments.contains("--house"){try runHouse(root:root,queriesURL:queriesURL);return}
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
      if let pose {
        // Adversarial room/floor clones share appearance but have distinct
        // canonical placement. The exact runtime competing-map gate must hide.
        var rejectedClones=0
        for offset in [V3(8,0,0),V3(0,0,3.2)] {
          var clone=map;clone.roomID=UUID();clone.segmentID=UUID()
          clone.points=clone.points.map{$0+offset}
          clone.views=clone.views.map{var v=$0;v.position=v.position+offset;return v}
          if VisualMapping.competingMatch(features,width:q.width,height:q.height,intrinsics:q.intrinsics,maps:[clone]){rejectedClones+=1}
        }
        result["ambiguousRoomAndFloorRejected"]=rejectedClones==2
        result["ambiguityCases"]=2;result["ambiguityFalseAccepts"]=2-rejectedClones
        result["worldFromARCamera"]=pose.transform.values;result["inliers"]=pose.inliers;result["rmsPixels"]=pose.rms;result["sourceIDs"]=pose.sources.map{$0.uuidString}}
      output.append(result)
    }
    print(String(data:try JSONSerialization.data(withJSONObject:["candidateFingerprint":map.fingerprint,"mapFeatures":map.points.count,"mapViews":map.views.count,"queries":output,"optimizedCameras":activeSegment.poseSolution?.cameras ?? [:],"bundleCheckRMS":activeSegment.poseSolution?.bundleCheckRMS as Any? ?? NSNull(),"bundlePointCount":activeSegment.poseSolution?.bundlePointCount as Any? ?? NSNull()],options:[.sortedKeys]),encoding:.utf8)!)
  }
  static func runCodedHouse(root:URL,queriesURL:URL)throws {
    var house=try JSONDecoder().decode(House.self,from:Data(contentsOf:root.appendingPathComponent("house.json")));try house.validate()
    let assets=DiskEvidence(root)
    var maps:[UUID:CodedReferences.Map]=[:],mapDiagnostics:[[String:Any]]=[]
    for segmentIndex in house.segments.indices {
      let segmentID=house.segments[segmentIndex].id
      var measured:[UUID:ReferencePose]=[:],conflicted=Set<UUID>(),decoded=0,estimated=0
      // Treat all recorded marker poses/corners as untrusted input to this replay:
      // regenerate them from source pixels with the shipping capture adapter.
      house.segments[segmentIndex].referencePoses=[]
      for index in house.observations.indices where house.observations[index].segmentID==segmentID && !house.observations[index].documentary {
        var observation=house.observations[index]
        let (gray,w,h)=try VisualMapping.image(assets.read(observation.image))
        guard w==observation.width,h==observation.height else{throw HouseError.message("Capture dimensions differ from image pixels.")}
        let detections=try CodedReferences.detect(gray:gray,width:w,height:h,stride:w,boards:house.references)
        let poses=CodedReferences.measure(detections,camera:observation.camera,intrinsics:observation.intrinsics,width:w,height:h,boards:house.references)
        CodedReferences.accumulate(poses,current:&measured,conflicted:&conflicted)
        observation.codedDetections=detections;observation.referenceObservations=poses
        house.observations[index]=observation;decoded+=detections.count;estimated+=poses.count
      }
      house.segments[segmentIndex].referencePoses=Array(measured.values)
      let map=CodedReferences.build(house:house,segment:house.segments[segmentIndex]);maps[segmentID]=map
      mapDiagnostics.append(["segmentID":segmentID.uuidString,"decodedSourceDetections":decoded,"estimatedSourceBoards":estimated,"conflictedBoards":conflicted.count,"eligibleBoards":map.boards.count])
    }
    let queries=try JSONDecoder().decode(ReplayQueries.self,from:Data(contentsOf:queriesURL));var output:[[String:Any]]=[]
    for query in queries.queries {
      guard !query.image.contains("/"),!query.image.contains("..") else{throw HouseError.message("Unsafe query path.")}
      guard let selected=query.segmentID,let map=maps[selected] else{output.append(["image":query.image,"accepted":false,"reason":"No selected reference map"]);continue}
      let (gray,w,h)=try VisualMapping.image(Data(contentsOf:root.appendingPathComponent(query.image)))
      guard w==query.width,h==query.height else{throw HouseError.message("Query dimensions differ from pixels.")}
      let start=Date();var row:[String:Any]=["image":query.image,"accepted":false,"selectedSegmentID":selected.uuidString]
      do {
        let result=try CodedReferences.localize(gray:gray,width:w,height:h,stride:w,intrinsics:query.intrinsics,map:map)
        row["conflict"]=result.conflict
        if let pose=result.pose,!result.conflict {row["accepted"]=true;row["worldFromARCamera"]=pose.values}
      }catch{row["reason"]=error.localizedDescription}
      row["seconds"]=Date().timeIntervalSince(start);output.append(row)
    }
    let report:[String:Any]=["queries":output,"mapCount":maps.values.filter{$0.boards.count>=4}.count,"mapDiagnostics":mapDiagnostics,"mapFeatures":maps.values.reduce(0){$0+$1.boards.count*4},"mapViews":house.observations.count,"optimizedCameras":[String:[Double]](),"sourceBoardPosesFromPixels":true,"productionQualified":false]
    print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
  }
  static func runHouse(root:URL,queriesURL:URL)throws {
    var house=try JSONDecoder().decode(House.self,from:Data(contentsOf:root.appendingPathComponent("house.json")));try house.validate()
    guard house.segments.count<=24 else{throw HouseError.message("Competing-map budget exceeded; full search required.")}
    var maps:[UUID:VisualMap]=[:],failures:[String:String]=[:],cameras:[String:[Double]]=[:]
    for index in house.segments.indices {
      do {
        var segment=house.segments[index]
        if CommandLine.arguments.contains("--refine"){segment.poseSolution=try PoseGraph.build(house:house,segment:segment,repo:DiskEvidence(root));house.segments[index]=segment}
        if CommandLine.arguments.contains("--bundle"){let result=try BundleRefinement.build(house:house,segment:segment,repo:DiskEvidence(root));segment.poseSolution=result.solution;house.segments[index]=segment}
        maps[segment.id]=try VisualMapping.build(house:house,segment:segment,repo:DiskEvidence(root))
        for (id,pose) in segment.poseSolution?.cameras ?? [:]{cameras[id]=pose}
      }catch{failures[house.segments[index].id.uuidString]=error.localizedDescription}
    }
    let queries=try JSONDecoder().decode(ReplayQueries.self,from:Data(contentsOf:queriesURL));var output:[[String:Any]]=[]
    for q in queries.queries {
      guard !q.image.contains("/"),!q.image.contains("..") else{throw HouseError.message("Unsafe query image path.")}
      guard let selected=q.segmentID,let map=maps[selected] else{output.append(["image":q.image,"accepted":false,"reason":"Selected capture has no admitted map"]);continue}
      let (gray,w,h)=try VisualMapping.image(Data(contentsOf:root.appendingPathComponent(q.image)))
      let features=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w),start=Date()
      let competing=maps.filter{$0.key != selected && ($0.value.roomID != map.roomID || $0.value.frameID != map.frameID)}.map{$0.value}
      let ambiguous=VisualMapping.competingMatch(features,width:q.width,height:q.height,intrinsics:q.intrinsics,maps:competing)
      var diagnostics:[String]=[]
      let pose=ambiguous ? nil:VisualMapping.query(features,width:q.width,height:q.height,intrinsics:q.intrinsics,map:map,diagnostic:{diagnostics.append($0)})
      var result:[String:Any]=["image":q.image,"diagnostics":diagnostics,"queryFeatures":features.count,"accepted":pose != nil,"ambiguous":ambiguous,"selectedRoomID":map.roomID.uuidString,"selectedSegmentID":selected.uuidString,"seconds":Date().timeIntervalSince(start)]
      if let pose{result["worldFromARCamera"]=pose.transform.values;result["inliers"]=pose.inliers;result["rmsPixels"]=pose.rms}
      output.append(result)
    }
    let report:[String:Any]=["queries":output,"mapCount":maps.count,"mappingFailures":failures,"optimizedCameras":cameras,"mapFeatures":maps.values.reduce(0){$0+$1.points.count},"mapViews":maps.values.reduce(0){$0+$1.views.count},"productionQualified":false]
    print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
  }

}
