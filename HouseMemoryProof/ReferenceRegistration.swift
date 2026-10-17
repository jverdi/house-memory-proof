import Foundation
import CryptoKit
import simd

struct RegistrationLink:Codable,Equatable {
  var anchorSegment:UUID;var boardIDs:[UUID];var fingerprint:String
}
enum ReferenceRegistration {
  struct Inputs:Codable {var anchor:UUID;var registration:Rigid?;var anchorPoses:[ReferencePose];var sourcePoses:[ReferencePose];var boards:[ReferenceBoard];var anchorCorners:String?;var sourceCorners:String?}
  struct CornerInput:Codable {var id:UUID;var camera:[Double];var intrinsics:[Double];var width:Int;var height:Int;var detections:[CodedDetection]}
  static func fingerprint(source:Segment,anchor:Segment,boards:[ReferenceBoard],house:House)throws->String {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let codes=Set(boards.filter{$0.tagID != nil}.map{$0.id})
    func corners(_ segment:Segment)throws->String? {
      guard !codes.isEmpty else{return nil}
      let inputs=house.observations.filter{$0.segmentID==segment.id && !$0.documentary}.sorted{$0.id.uuidString<$1.id.uuidString}.compactMap{o->CornerInput? in
        let detections=(o.codedDetections ?? []).filter{codes.contains($0.boardID)}.sorted{$0.boardID.uuidString<$1.boardID.uuidString}
        return detections.isEmpty ? nil:CornerInput(id:o.id,camera:o.camera,intrinsics:o.intrinsics,width:o.width,height:o.height,detections:detections)
      }
      return SHA256.hash(data:try encoder.encode(inputs)).map{String(format:"%02x",$0)}.joined()
    }
    let data=try encoder.encode(Inputs(anchor:anchor.id,registration:anchor.registration,anchorPoses:anchor.referencePoses,sourcePoses:source.referencePoses,boards:boards,anchorCorners:try corners(anchor),sourceCorners:try corners(source)))
    return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  }
  static func currentPoses(segment:Segment,house:House)->[ReferencePose] {
    let legacyIDs=Set(house.references.filter{$0.valid && $0.tagID==nil}.map{$0.id})
    let legacy=segment.referencePoses.filter{legacyIDs.contains($0.boardID)}
    // Rebuild coded geometry from current print dimensions and raw captures;
    // the mutable aggregate checkpoint is never a coded registration input.
    return legacy+CodedReferences.build(house:house,segment:segment).boards.map{$0.pose}
  }
  static func fit(source:Segment,anchor:Segment,house:House)throws->(Rigid,Double,RegistrationLink) {
    guard source.id != anchor.id,let registration=anchor.registration else{throw HouseError.message("Choose a different session already registered in the house frame.")}
    var ancestor:Segment?=anchor;var visited=Set<UUID>()
    while let item=ancestor {guard item.id != source.id,visited.insert(item.id).inserted else{throw HouseError.message("Registration dependencies would form a cycle.")};ancestor=item.registrationLink.flatMap{link in house.segments.first{$0.id==link.anchorSegment}}}
    let sourcePoses=currentPoses(segment:source,house:house),anchorPoses=currentPoses(segment:anchor,house:house)
    let boards=house.references.filter{b in b.valid && sourcePoses.contains{$0.boardID==b.id} && anchorPoses.contains{$0.boardID==b.id}}.sorted{$0.id.uuidString<$1.id.uuidString}
    guard boards.count>=3 else{throw HouseError.message("Both sessions need the same three fixed reference boards. Two fit the transform; the third independently checks it.")}
    let adapter=PoseRefinement.matrix([1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1])!,world=PoseRefinement.matrix(registration.values)!
    var candidates:[simd_double4x4]=[],pairs:[(simd_double4x4,simd_double4x4)]=[]
    for board in boards {
      guard let a=anchorPoses.first(where:{$0.boardID==board.id}).flatMap({PoseRefinement.matrix($0.matrix)}),let b=sourcePoses.first(where:{$0.boardID==board.id}).flatMap({PoseRefinement.matrix($0.matrix)}) else{throw HouseError.message("Invalid reference pose.")}
      let target=world*adapter*a,local=adapter*b
      candidates.append(target*simd_inverse(local));pairs.append((local,target))
    }
    func rotation(_ m:simd_double4x4)->simd_quatd {simd_quatd(simd_double3x3(SIMD3(m.columns.0.x,m.columns.0.y,m.columns.0.z),SIMD3(m.columns.1.x,m.columns.1.y,m.columns.1.z),SIMD3(m.columns.2.x,m.columns.2.y,m.columns.2.z)))}
    guard simd_distance(pairs[0].0.columns.3,pairs[1].0.columns.3)>=0.25,
      pairs.dropFirst(2).allSatisfy({check in pairs.prefix(2).allSatisfy{simd_distance(check.0.columns.3,$0.0.columns.3)>=0.2}}) else{throw HouseError.message("Use well-separated reference boards; coincident targets do not provide an independent check.")}
    let a=candidates[0],b=candidates[1]
    guard VisualMapping.agree(Rigid(values:PoseRefinement.array(a)),Rigid(values:PoseRefinement.array(b))) else{throw HouseError.message("The fitting reference boards disagree; no registration was applied.")}
    var transform=simd_double4x4(simd_slerp(rotation(a),rotation(b),0.5));transform.columns.3=(a.columns.3+b.columns.3)*0.5
    var worst=0.0
    for i in pairs.indices {
      let half=boards[i].width/2
      // AR image anchors lie in local X/Z; corners test orientation as well as centre.
      for p in [SIMD4<Double>(0,0,0,1),SIMD4(-half,0,-half,1),SIMD4(half,0,half,1)] {
        let error=simd_distance(transform*pairs[i].0*p,pairs[i].1*p)
        guard error<=0.025 else{throw HouseError.message("Shared reference check exceeds 25 mm. A board may have moved or tracked poorly; registration remains unchanged.")}
        if i>=2 {worst=max(worst,error)}
      }
    }
    let result=Rigid(values:PoseRefinement.array(transform));guard result.valid else{throw HouseError.message("Reference registration produced an invalid transform.")}
    return(result,worst,RegistrationLink(anchorSegment:anchor.id,boardIDs:boards.map{$0.id},fingerprint:try fingerprint(source:source,anchor:anchor,boards:boards,house:house)))
  }
  static func invalidateChangedInputs(_ house:inout House) {
    // Imported dependency graphs may contain cycles or missing targets. Remove
    // every invalid chain before any derived registration can be displayed.
    let byID=Dictionary(house.segments.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    var invalid=Set<UUID>()
    for segment in house.segments where segment.registrationLink != nil {
      var visited=Set<UUID>(),current:Segment?=segment
      while let item=current,let link=item.registrationLink {
        guard visited.insert(item.id).inserted,let next=byID[link.anchorSegment],link.boardIDs.count>=3,Set(link.boardIDs).count==link.boardIDs.count else{invalid.insert(segment.id);break}
        current=next
      }
    }
    for i in house.segments.indices where invalid.contains(house.segments[i].id) {house.segments[i].registration=nil;house.segments[i].registrationResidual=nil;house.segments[i].registrationLink=nil}
    for _ in 0..<house.segments.count {
      var changed=false
      for i in house.segments.indices {
        guard let link=house.segments[i].registrationLink else{continue}
        let boards=house.references.filter{link.boardIDs.contains($0.id)}.sorted{$0.id.uuidString<$1.id.uuidString}
        let anchor=house.segments.first{$0.id==link.anchorSegment}
        let actual=anchor.flatMap{try? fingerprint(source:house.segments[i],anchor:$0,boards:boards,house:house)}
        if anchor?.registration==nil || actual != link.fingerprint || boards.contains(where:{!$0.valid}) {
          house.segments[i].registration=nil;house.segments[i].registrationResidual=nil;house.segments[i].registrationLink=nil;changed=true
        }
      }
      if !changed {break}
    }
  }
}

// Placement advice uses recorded board centres, not a claimed camera-error bound.
// Two vertical columns on different walls can still have coplanar centres.
enum ReferenceLayout {
  struct Assessment {
    var count:Int;var variances:[Double]
    var distributed:Bool {count>=4 && variances.count==3 && variances[0]>=0.09 && variances[1]>=0.0225 && variances[2]>=0.0016}
    var advice:String {
      if count<4 {return "Record at least four distinct fixed references to check three-dimensional placement. Stagger their heights and horizontal positions."}
      if !distributed {return "Reference centres are clustered or nearly coplanar. Stagger upper, middle and lower targets across different horizontal positions on two walls; avoid two straight columns."}
      return "Recorded reference centres have useful three-dimensional spread. Capture sharp, overlapping views with visible texture. This placement check does not establish accuracy."
    }
  }
  static func assess(_ points:[V3])->Assessment {
    guard points.count>=4,points.count<=100,points.allSatisfy({$0.finite}) else{return Assessment(count:points.count,variances:[])}
    let centre=points.reduce(V3(),+)*(1/Double(points.count))
    var covariance=simd_double3x3(diagonal:SIMD3<Double>(repeating:0))
    for point in points {let p=point-centre,v=SIMD3(p.x,p.y,p.z);covariance += simd_double3x3(columns:(v*v.x,v*v.y,v*v.z))*(1/Double(points.count))}
    let q=(covariance[0][0]+covariance[1][1]+covariance[2][2])/3
    var square=0.0
    for row in 0..<3 {for column in 0..<3 {let value=covariance[column][row]-(row==column ? q:0);square+=value*value}}
    let p=sqrt(square/6)
    if p<1e-12 {return Assessment(count:points.count,variances:[max(0,q),max(0,q),max(0,q)])}
    let unit=(covariance-simd_double3x3(diagonal:SIMD3<Double>(repeating:q)))*(1/p)
    let angle=acos(max(-1,min(1,simd_determinant(unit)/2)))/3
    let high=q+2*p*cos(angle),low=q+2*p*cos(angle+2*Double.pi/3),middle=3*q-high-low
    return Assessment(count:points.count,variances:[high,middle,low].map{max(0,$0)}.sorted(by:>))
  }
  static func assess(segment:Segment,house:House)->Assessment {
    let valid=Set(house.references.filter{$0.valid}.map{$0.id})
    let poses=Dictionary(segment.referencePoses.filter{valid.contains($0.boardID) && Rigid(values:$0.matrix).valid}.map{($0.boardID,$0)},uniquingKeysWith:{a,_ in a})
    return assess(poses.values.map{p in V3(p.matrix[3],-p.matrix[11],p.matrix[7])})
  }
}
