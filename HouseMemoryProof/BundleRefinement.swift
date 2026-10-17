import Foundation
import simd

enum BundleRefinement {
  struct Result {var solution:PoseGraphSolution;var feature:Feature}
  static func build(house:House,segment:Segment,repo:any EvidenceAssetReader)throws->Result {
    var feature=try PhotoReconstruction.build(house:house,segment:segment,repo:repo)
    guard let allTracks=feature.pointTracks else{throw HouseError.message("Photograph points have no image-track provenance.")}
    let pointCount=min(2000,allTracks.count)
    let indices=(0..<pointCount).map{$0*allTracks.count/pointCount}
    let tracks=indices.map{allTracks[$0]},vertices=indices.map{feature.mesh.vertices[$0]}
    let raw=house.observations.filter{$0.segmentID==segment.id}
    let selected=PoseRefinement.selected(raw,segment:segment,house:house).0
    let used=Set(tracks.flatMap{$0.controls.map{$0.observationID}})
    var fits:[UUID:Int]=[:];for track in tracks {for control in track.controls.prefix(2) {fits[control.observationID,default:0]+=1}}
    // Camera zero fixes the solver gauge. Preserve the pose graph's original
    // anchor rather than freezing an arbitrary already-corrected camera.
    let supported=selected.filter{used.contains($0.id)}.sorted{a,b in a.timestamp==b.timestamp ? a.id.uuidString<b.id.uuidString:a.timestamp<b.timestamp}
    let anchorID=segment.poseSolution?.anchorObservationID ?? supported.first(where:{fits[$0.id,default:0]>=20})?.id
    guard let anchorID,let anchor=supported.first(where:{$0.id==anchorID}),fits[anchorID,default:0]>=20 else{throw HouseError.message("Joint refinement needs twenty independently checked tracks on the established anchor. Capture more overlap; the reference frame was not changed.")}
    let observations=[anchor]+supported.filter{$0.id != anchorID}
    guard observations.count>=3,observations.count<=120 else{throw HouseError.message("Joint refinement needs three to 120 supported cameras.")}
    let lookup=Dictionary(uniqueKeysWithValues:observations.enumerated().map{($0.element.id,$0.offset)})
    let cameras=observations.flatMap{$0.camera},points=vertices.flatMap{[$0.x,$0.z,-$0.y]}
    let intrinsics=observations.flatMap{[$0.intrinsics[0],$0.intrinsics[4],$0.intrinsics[2],$0.intrinsics[5]]}
    var depths:[UUID:Data]=[:],confidences:[UUID:Data]=[:]
    for o in observations {try Task.checkCancellation();if let key=o.depth {depths[o.id]=try repo.read(key)};if let key=o.confidence {confidences[o.id]=try repo.read(key)}}
    var evidence:[HXBundleObservation]=[]
    for (point,track) in tracks.enumerated() {
      for (order,control) in track.controls.enumerated() {
        guard let camera=lookup[control.observationID] else{throw HouseError.message("Track references an unavailable camera estimate.")}
        let o=observations[camera]
        // Remaining views are held out of the objective. Their image residuals
        // are checked after solving, including when their camera fits other points.
        let fitting=order<2
        let depth=fitting ? measuredDepth(control,point:vertices[point],observation:o,data:depths[o.id],confidence:confidences[o.id]):0
        evidence.append(HXBundleObservation(camera:UInt32(camera),point:UInt32(point),fit:fitting ? 1:0,u:control.u*Double(o.width),v:control.v*Double(o.height),depth:depth))
      }
    }
    var outputCameras=[Double](repeating:0,count:cameras.count),outputPoints=[Double](repeating:0,count:points.count),quality=HXBundleQuality()
    let status=cameras.withUnsafeBufferPointer{c in points.withUnsafeBufferPointer{p in intrinsics.withUnsafeBufferPointer{k in evidence.withUnsafeBufferPointer{e in outputCameras.withUnsafeMutableBufferPointer{oc in outputPoints.withUnsafeMutableBufferPointer{op in
      hx_bundle_optimize(c.baseAddress,UInt32(observations.count),p.baseAddress,UInt32(pointCount),k.baseAddress,e.baseAddress,UInt32(evidence.count),oc.baseAddress,op.baseAddress,&quality)
    }}}}}}
    try Task.checkCancellation()
    guard status==1 else{throw HouseError.message("Joint refinement did not pass its held-out image/depth checks (status \(status)). Existing camera estimates and originals remain unchanged.")}
    var solved:[String:[Double]]=[:]
    for i in observations.indices {solved[observations[i].id.uuidString]=Array(outputCameras[i*16..<(i+1)*16])}
    var solution=PoseGraphSolution(fingerprint:try PoseGraph.fingerprint(house:house,segment:segment),cameras:solved,edges:segment.poseSolution?.edges ?? 0,maximumEdgeResidual:segment.poseSolution?.maximumEdgeResidual ?? 0,excludedFrameCount:max(0,raw.count-observations.count),anchorObservationID:observations.first?.id)
    solution.bundleCheckRMS=quality.final_check_rms;solution.bundleFitRMS=quality.fit_rms;solution.bundlePointCount=pointCount
    var updated=house;guard let index=updated.segments.firstIndex(where:{$0.id==segment.id}) else{throw HouseError.message("Capture session is missing.")};updated.segments[index].poseSolution=solution
    feature.name="Optimized photograph details"
    feature.mesh=Mesh(vertices:(0..<pointCount).map{V3(outputPoints[$0*3],-outputPoints[$0*3+2],outputPoints[$0*3+1])},triangles:[])
    feature.pointTracks=tracks;feature.sourceIDs=observations.map{$0.id}
    feature.sourceFingerprint=try VisualMapping.fingerprint(house:updated,segment:updated.segments[index])
    feature.notes="Ceres joint camera/point refinement. Two fitting views per point; remaining image observations excluded from the objective and checked afterward. Optional continuous depth patches constrain metric scale. Held-out RMS \(String(format:"%.3f",quality.final_check_rms)) px, fit RMS \(String(format:"%.3f",quality.fit_rms)) px. These residuals are not physical accuracy. Raw evidence remains immutable."
    return Result(solution:solution,feature:feature)
  }
  static func measuredDepth(_ control:PhotoControl,point:V3,observation o:Observation,data:Data?,confidence:Data?)->Double {
    let w=o.depthWidth,h=o.depthHeight
    guard w>=3,h>=3,w*h<=1000000,let data,data.count==w*h*4,let confidence,confidence.count==w*h else{return 0}
    let px=control.u*Double(w),py=control.v*Double(h),x=Int(px),y=Int(py)
    guard x>0,y>0,x<w-1,y<h-1 else{return 0}
    var values:[Double]=[]
    for dy in -1...1 {for dx in -1...1 {let i=(y+dy)*w+x+dx;guard confidence[i]>=2 else{return 0};let value=Double(data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:i*4,as:Float.self)});guard value.isFinite,value>=0.15,value<=5 else{return 0};values.append(value)}}
    guard values.max()!-values.min()!<0.04 else{return 0}
    let tx=px-Double(x),ty=py-Double(y),depth=values[4]*(1-tx)*(1-ty)+values[5]*tx*(1-ty)+values[7]*(1-tx)*ty+values[8]*tx*ty
    let native=SIMD4(point.x,point.z,-point.y,1),camera=simd_inverse(PoseRefinement.matrix(o.camera)!)*native
    return abs(-camera.z-depth)<=0.025 ? depth:0
  }
}
