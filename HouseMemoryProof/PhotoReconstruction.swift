import Foundation
import simd

enum PhotoReconstruction {
  struct Ray {var origin:SIMD3<Double>;var direction:SIMD3<Double>;var view:Int;var control:PhotoControl;var focal:Double}
  static func pair(_ a:Ray,_ b:Ray,minimumAngle:Double)->SIMD3<Double>? {
    guard simd_distance(a.origin,b.origin)>=0.10,simd_dot(a.direction,b.direction)<cos(minimumAngle) else{return nil}
    let cross=simd_cross(a.direction,b.direction);guard simd_length(cross)>1e-5,abs(simd_dot(b.origin-a.origin,simd_normalize(cross)))<=0.015 else{return nil}
    var normal=simd_double3x3(diagonal:SIMD3<Double>(repeating:0)),right=SIMD3<Double>(repeating:0)
    for ray in [a,b] {let d=ray.direction,p=matrix_identity_double3x3-simd_double3x3(columns:(d*d.x,d*d.y,d*d.z));normal += p;right += p*ray.origin}
    guard abs(simd_determinant(normal))>1e-8 else{return nil}
    let point=simd_inverse(normal)*right
    guard consistent(point,a),consistent(point,b) else{return nil};return point
  }
  static func consistent(_ point:SIMD3<Double>,_ ray:Ray)->Bool {
    let delta=point-ray.origin,depth=simd_dot(delta,ray.direction)
    return depth>=0.15 && depth<=8 && simd_length(delta-ray.direction*depth)/depth*ray.focal<=2
  }
  static func build(house:House,segment:Segment,repo:any EvidenceAssetReader)throws->Feature {
    let input=PoseRefinement.selected(house.observations.filter{$0.segmentID==segment.id && !$0.documentary},segment:segment,house:house).0.filter{$0.sharpness>=0.02}
    guard input.count>=3 else{throw HouseError.message("Photograph triangulation needs three sharp, translated views with compatible camera estimates.")}
    let count=min(12,input.count),observations=(0..<count).map{input[$0*input.count/count]}
    var rays:[Ray]=[],features:[VisualMapping.Features]=[],offsets:[Int]=[]
    for (index,o) in observations.enumerated() {
      try Task.checkCancellation();let(gray,w,h)=try VisualMapping.image(repo.read(o.image));let detected=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
      offsets.append(rays.count);features.append(detected);let m=o.camera
      for i in 0..<detected.count {
        let u=Double(detected.xy[i*2]),v=Double(detected.xy[i*2+1]),x=(u*Double(o.width)-o.intrinsics[2])/o.intrinsics[0],y = -(v*Double(o.height)-o.intrinsics[5])/o.intrinsics[4]
        let ar=SIMD3(m[0]*x+m[1]*y-m[2],m[4]*x+m[5]*y-m[6],m[8]*x+m[9]*y-m[10])
        rays.append(Ray(origin:SIMD3(m[3],-m[11],m[7]),direction:simd_normalize(SIMD3(ar.x,-ar.z,ar.y)),view:index,control:PhotoControl(observationID:o.id,u:u,v:v),focal:max(o.intrinsics[0],o.intrinsics[4])))
      }
    }
    var parents=Array(rays.indices)
    func root(_ index:Int)->Int {var i=index;while parents[i] != i {i=parents[i]};return i}
    for a in features.indices {for b in features.indices where b>a {
      try Task.checkCancellation();var pairs=[UInt32](repeating:0,count:2400)
      let n=features[a].descriptors.withUnsafeBytes{x in features[b].descriptors.withUnsafeBytes{y in pairs.withUnsafeMutableBufferPointer{p in hx_vision_match(x.bindMemory(to:UInt8.self).baseAddress,UInt32(features[a].count),y.bindMemory(to:UInt8.self).baseAddress,UInt32(features[b].count),p.baseAddress,1200)}}}
      for i in 0..<max(0,Int(n)) {let x=offsets[a]+Int(pairs[i*2]),y=offsets[b]+Int(pairs[i*2+1]);guard pair(rays[x],rays[y],minimumAngle:Double.pi/180) != nil else{continue};let rx=root(x),ry=root(y);if rx != ry {parents[max(rx,ry)]=min(rx,ry)}}
    }}
    var tracks:[Int:[Int]]=[:];for i in rays.indices {tracks[root(i),default:[]].append(i)}
    var points:[V3]=[],evidence:[PointTrack]=[]
    for key in tracks.keys.sorted() {
      try Task.checkCancellation();let indices=tracks[key]!
      guard indices.count>=3,indices.count<=12,Set(indices.map{rays[$0].view}).count==indices.count else{continue}
      var best:(Int,Int)?,dot=1.0
      for a in indices {for b in indices where b>a {let value=simd_dot(rays[a].direction,rays[b].direction);if value<dot {dot=value;best=(a,b)}}}
      guard let (a,b)=best,let point=pair(rays[a],rays[b],minimumAngle:5*Double.pi/180),indices.allSatisfy({consistent(point,rays[$0])}) else{continue}
      let independent=indices.filter{$0 != a && $0 != b}
      guard independent.contains(where:{simd_distance(rays[$0].origin,rays[a].origin)>=0.10 && simd_distance(rays[$0].origin,rays[b].origin)>=0.10}) else{continue}
      points.append(V3(point.x,point.y,point.z));evidence.append(PointTrack(controls:([a,b]+independent).map{rays[$0].control}))
    }
    guard points.count>=20 else{throw HouseError.message("Too few independently checked photograph details. Add translated views of distinct texture; repetitive framing or blank walls cannot constrain this reconstruction.")}
    return Feature(name:"Photograph detail points",trade:.unknown,roomID:segment.roomID,stageID:segment.stageID,kind:house.isDemo ? .synthetic:.observed,mesh:Mesh(vertices:points,triangles:[]),sourceIDs:observations.map{$0.id},notes:"Sparse RGB triangulation from known camera estimates. Every point uses two fitting views and at least one independent image check, ≥5° parallax and ≤2 pixel residuals. No depth or oracle geometry supplied; physical accuracy and completeness remain unqualified.",segmentID:segment.id,sourceFingerprint:try VisualMapping.fingerprint(house:house,segment:segment),pointTracks:evidence)
  }
}
