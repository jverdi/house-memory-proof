import Foundation
import simd

enum PhotoTriangulation {
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
    var normal=simd_double3x3(repeating:0),right=SIMD3<Double>(repeating:0)
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
