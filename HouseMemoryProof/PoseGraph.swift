import Foundation
import simd

struct PoseGraphSolution: Codable, Equatable {
  var fingerprint:String
  var cameras:[String:[Double]]
  var edges:Int
  var maximumEdgeResidual:Double
  var excludedFrameCount:Int?=nil
  var anchorObservationID:UUID?=nil
  var date=Date()
}
enum PoseGraph {
  static func fingerprint(house:House,segment:Segment)throws->String {
    var raw=segment;raw.poseSolution=nil
    return try VisualMapping.fingerprint(house:house,segment:raw)
  }
  static func selected(_ observations:[Observation],segment:Segment,house:House)->[Observation]? {
    guard let solution=segment.poseSolution,
      let current=try? fingerprint(house:house,segment:segment),current==solution.fingerprint else{return nil}
    let corrected=observations.compactMap { observation -> Observation? in
      guard let pose=solution.cameras[observation.id.uuidString],Rigid(values:pose).valid else{return nil}
      var o=observation;o.camera=pose;return o
    }
    return corrected
  }
  static func build(house:House,segment:Segment,repo:any EvidenceAssetReader)throws->PoseGraphSolution {
    var raw=segment;raw.poseSolution=nil
    let input=house.observations.filter{$0.segmentID==segment.id}
    let observations=PoseRefinement.selected(input,segment:raw,house:house).0
    let byID=Dictionary(uniqueKeysWithValues:observations.map{($0.id,$0)})
    let map=try VisualMapping.build(house:house,segment:raw,repo:repo)
    guard map.views.count>=3 else{throw HouseError.message("Pose refinement needs at least three overlapping textured depth views.")}
    let adapter=PoseRefinement.matrix([1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1])!
    let registration=PoseRefinement.matrix((segment.registration ?? Rigid()).values)!
    var cameraPoints:[[Double]]=[],descriptors:[Data]=[],priors:[Double]=[],ids:[UUID]=[]
    for view in map.views {
      guard let observation=byID[view.observationID],let native=PoseRefinement.matrix(observation.camera) else{throw HouseError.message("Visual view has no valid camera provenance.")}
      let inverse=simd_inverse(registration*adapter*native)
      var points:[Double]=[]
      for point in map.points[view.start..<(view.start+view.count)] {let p=inverse*SIMD4(point.x,point.y,point.z,1);points += [p.x,p.y,p.z]}
      cameraPoints.append(points);descriptors.append(map.descriptors.subdata(in:view.start*32..<(view.start+view.count)*32));priors += observation.camera;ids.append(observation.id)
    }
    var edges:[HXGraphEdge]=[]
    for a in map.views.indices {for b in map.views.indices where b>a {
      try Task.checkCancellation()
      var pairs=[UInt32](repeating:0,count:2400)
      let count=descriptors[a].withUnsafeBytes{x in descriptors[b].withUnsafeBytes{y in pairs.withUnsafeMutableBufferPointer{p in hx_vision_match(x.bindMemory(to:UInt8.self).baseAddress,UInt32(map.views[a].count),y.bindMemory(to:UInt8.self).baseAddress,UInt32(map.views[b].count),p.baseAddress,1200)}}}
      guard count>=30 else{continue}
      var source:[Double]=[],target:[Double]=[]
      for i in 0..<Int(count){let x=Int(pairs[i*2])*3,y=Int(pairs[i*2+1])*3;target += cameraPoints[a][x..<x+3];source += cameraPoints[b][y..<y+3]}
      var transform=[Double](repeating:0,count:16),rms=0.0
      let accepted=source.withUnsafeBufferPointer{x in target.withUnsafeBufferPointer{y in transform.withUnsafeMutableBufferPointer{m in hx_depth_transform(x.baseAddress,y.baseAddress,UInt32(count),m.baseAddress,&rms)}}}
      guard accepted>=30,Rigid(values:transform).valid else{continue}
      let pa=PoseRefinement.matrix(Array(priors[a*16..<(a+1)*16]))!,pb=PoseRefinement.matrix(Array(priors[b*16..<(b+1)*16]))!
      let estimate=simd_inverse(pa)*pb,measured=PoseRefinement.matrix(transform)!
      guard simd_distance(estimate.columns.3,measured.columns.3)<0.25 else{continue}
      var edge=HXGraphEdge();edge.a=UInt32(a);edge.b=UInt32(b)
      withUnsafeMutableBytes(of:&edge.a_from_b){bytes in for i in 0..<16{bytes.storeBytes(of:transform[i],toByteOffset:i*8,as:Double.self)}}
      edges.append(edge)
    }}
    // A sharp photograph can still have no trustworthy overlap. Use the
    // largest connected component, anchored at its earliest original camera
    // prior in the SAME capture frame. Other images remain explicitly unsupported.
    var unseen=Set(ids.indices),components:[[Int]]=[]
    while let start=unseen.min() {
      var connected:Set<Int>=[start],pending=[start];unseen.remove(start)
      while let node=pending.popLast() {
        for edge in edges {
          let next=Int(edge.a)==node ? Int(edge.b):Int(edge.b)==node ? Int(edge.a):(-1)
          if next>=0,connected.insert(next).inserted {pending.append(next);unseen.remove(next)}
        }
      }
      components.append(connected.sorted())
    }
    let kept=components.sorted{a,b in a.count==b.count ? a[0]<b[0]:a.count>b.count}.first ?? []
    guard kept.count>=3 else{throw HouseError.message("Fewer than three photographs share reliable overlap. Capture more translated views; originals remain unchanged.")}
    if kept.count<ids.count {
      let remap=Dictionary(uniqueKeysWithValues:kept.enumerated().map{($0.element,UInt32($0.offset))})
      edges=edges.compactMap{edge in guard let a=remap[Int(edge.a)],let b=remap[Int(edge.b)] else{return nil};var changed=edge;changed.a=a;changed.b=b;return changed}
      priors=kept.flatMap{Array(priors[$0*16..<($0+1)*16])};ids=kept.map{ids[$0]}
    }
    guard edges.count>=ids.count else{throw HouseError.message("Insufficient independently matched overlap to close a local pose graph. Capture translated corner views; no camera corrections were applied.")}
    var output=[Double](repeating:0,count:priors.count),residual=0.0
    let status=priors.withUnsafeBufferPointer{p in edges.withUnsafeBufferPointer{e in output.withUnsafeMutableBufferPointer{o in hx_graph_optimize(p.baseAddress,UInt32(ids.count),e.baseAddress,UInt32(edges.count),o.baseAddress,&residual)}}}
    guard status==1 else{throw HouseError.message("Pose graph rejected disconnected, inconsistent or excessive corrections (status \(status), \(edges.count) edges, maximum edge residual \(Int((residual*1000).rounded())) mm). Raw camera evidence is unchanged.")}
    var corrected:[String:[Double]]=[:]
    for i in ids.indices{corrected[ids[i].uuidString]=Array(output[i*16..<(i+1)*16])}
    return PoseGraphSolution(fingerprint:try fingerprint(house:house,segment:segment),cameras:corrected,edges:edges.count,maximumEdgeResidual:residual,excludedFrameCount:max(0,input.count-ids.count),anchorObservationID:ids.first)
  }
}

// Derived geometry follows the exact capture/pose/reference inputs that produced it.
enum DerivedEvidence {
  static func currentIDs(_ house:House)->Set<UUID> {
    let needed=Set(house.features.filter{$0.sourceFingerprint != nil}.compactMap{$0.segmentID})
    var fingerprints:[UUID:String]=[:]
    for segment in house.segments where needed.contains(segment.id) {
      fingerprints[segment.id]=try? VisualMapping.fingerprint(house:house,segment:segment)
    }
    return Set(house.features.filter { feature in
      guard let expected=feature.sourceFingerprint else{return true}
      guard let segment=feature.segmentID else{return false}
      return fingerprints[segment]==expected
    }.map{$0.id})
  }
}
