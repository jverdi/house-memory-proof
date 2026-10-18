import Foundation
import simd

enum PhotoTriangulation {
  static func curve(_ samples:[[PhotoControl]],house:House,segment:Segment,name:String,trade:Trade,visibleIntervalsConfirmed:Bool)throws->Feature {
    guard (2...128).contains(samples.count),visibleIntervalsConfirmed else {
      throw HouseError.message("Select two to 128 independently checked points and confirm that every joining interval is visible. Keep occluded continuations as separate evidence.")
    }
    guard zip(samples,samples.dropFirst()).allSatisfy({pair in
      Set(pair.0.map{$0.observationID}).intersection(Set(pair.1.map{$0.observationID})).count>=2
    }) else {throw HouseError.message("Neighboring curve points need at least two shared source photographs. Split sections without overlapping visible evidence.")}
    // Every point retains its own fitting pair and independent third view.
    // Background depth is deliberately absent from this operation.
    let points=try samples.map{try locate($0,house:house,segment:segment)}
    guard zip(points,points.dropFirst()).allSatisfy({($0.0-$0.1).length>0.00001}) else{
      throw HouseError.message("Consecutive curve points coincide. Remove the repeated selection.")
    }
    let sourceIDs=Set(samples.flatMap{$0.map{$0.observationID}}).sorted{$0.uuidString<$1.uuidString}
    return Feature(name:name.isEmpty ? "Photo-traced curve":name,trade:trade,roomID:segment.roomID,stageID:segment.stageID,
      kind:house.isDemo ? .synthetic:.observed,mesh:Mesh(vertices:points,triangles:[]),route:points,sourceIDs:sourceIDs,
      notes:"Manually selected visible centerline. Each point has two fitting photographs and an independent third-view check. The author confirmed visible joining intervals; no occluded continuation or crossing connection is inferred. Diameter, envelope, positional uncertainty and physical accuracy remain unknown. Display stroke has no metric thickness.",
      segmentID:segment.id,sourceFingerprint:try VisualMapping.fingerprint(house:house,segment:segment),pointTracks:samples.map{PointTrack(controls:$0)})
  }
  static func locate(_ controls:[PhotoControl],house:House,segment:Segment)throws->V3 {
    guard controls.count==3,Set(controls.map{$0.observationID}).count==3,controls.allSatisfy({$0.u.isFinite && $0.v.isFinite && (0...1).contains($0.u) && (0...1).contains($0.v)}) else{throw HouseError.message("Choose the same visible point in three different photographs.")}
    let candidates=PoseRefinement.selected(house.observations.filter{$0.segmentID==segment.id && !$0.documentary},segment:segment,house:house).0
    var cameras:[Observation]=[],origins:[SIMD3<Double>]=[],directions:[SIMD3<Double>]=[]
    for control in controls {
      guard let o=candidates.first(where:{$0.id==control.observationID}) else{throw HouseError.message("All three photographs must have compatible camera estimates in this segment.")}
      let m=o.camera,x=(control.u*Double(o.width)-o.intrinsics[2])/o.intrinsics[0],y = -(control.v*Double(o.height)-o.intrinsics[5])/o.intrinsics[4]
      let ar=SIMD3(m[0]*x+m[1]*y-m[2],m[4]*x+m[5]*y-m[6],m[8]*x+m[9]*y-m[10])
      origins.append(SIMD3(m[3],-m[11],m[7]));directions.append(simd_normalize(SIMD3(ar.x,-ar.z,ar.y)));cameras.append(o)
    }
    for i in 0..<3 {for j in 0..<i {guard simd_distance(origins[i],origins[j])>=0.10 else{throw HouseError.message("Choose photographs taken from positions at least 10 cm apart.")}}}
    guard simd_dot(directions[0],directions[1])<cos(5*Double.pi/180) else{throw HouseError.message("The first two views need more angular separation. Choose wider translated viewpoints.")}
    var normal=simd_double3x3(diagonal:SIMD3<Double>(repeating:0)),right=SIMD3<Double>(repeating:0)
    for i in 0..<2 {
      let d=directions[i];let projector=matrix_identity_double3x3-simd_double3x3(columns:(d*d.x,d*d.y,d*d.z))
      normal += projector;right += projector*origins[i]
    }
    guard abs(simd_determinant(normal))>1e-8 else{throw HouseError.message("Viewing rays cannot constrain this point.")}
    let result=simd_inverse(normal)*right;let point=V3(result.x,result.y,result.z)
    guard point.finite else{throw HouseError.message("Invalid triangulation result.")}
    for i in 0..<3 {
      let delta=result-origins[i],depth=simd_dot(delta,directions[i]);let miss=simd_length(delta-directions[i]*depth)
      guard depth>=0.15,depth<=8,miss<=0.015,let projected=TextureBuilder.project(point,through:cameras[i]) else{throw HouseError.message("Photograph rays disagree. Recheck the selected point and camera alignment.")}
      let dx=(projected.0.u-controls[i].u)*Double(cameras[i].width),dy=(projected.0.v-controls[i].v)*Double(cameras[i].height)
      guard hypot(dx,dy)<=2 else{throw HouseError.message("Independent image check exceeds two pixels. Refine the selections or use better-separated photographs.")}
    }
    return point
  }
}

extension Feature {
  var isPhotoCurve:Bool {pointTracks != nil && photoControls==nil && route.count>=2 && mesh.triangles.isEmpty && mesh.vertices==route}
}
