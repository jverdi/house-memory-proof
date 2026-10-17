import Foundation
import CryptoKit
import simd

struct RegistrationLink:Codable,Equatable {
  var anchorSegment:UUID;var boardIDs:[UUID];var fingerprint:String
}
enum ReferenceRegistration {
  struct Inputs:Codable {var anchor:UUID;var registration:Rigid?;var anchorPoses:[ReferencePose];var sourcePoses:[ReferencePose];var boards:[ReferenceBoard]}
  static func fingerprint(source:Segment,anchor:Segment,boards:[ReferenceBoard])throws->String {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let data=try encoder.encode(Inputs(anchor:anchor.id,registration:anchor.registration,anchorPoses:anchor.referencePoses,sourcePoses:source.referencePoses,boards:boards))
    return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  }
  static func fit(source:Segment,anchor:Segment,house:House)throws->(Rigid,Double,RegistrationLink) {
    guard source.id != anchor.id,let registration=anchor.registration else{throw HouseError.message("Choose a different session already registered in the house frame.")}
    var ancestor:Segment?=anchor;var visited=Set<UUID>()
    while let item=ancestor {guard item.id != source.id,visited.insert(item.id).inserted else{throw HouseError.message("Registration dependencies would form a cycle.")};ancestor=item.registrationLink.flatMap{link in house.segments.first{$0.id==link.anchorSegment}}}
    let boards=house.references.filter{b in b.valid && source.referencePoses.contains{$0.boardID==b.id} && anchor.referencePoses.contains{$0.boardID==b.id}}.sorted{$0.id.uuidString<$1.id.uuidString}
    guard boards.count>=3 else{throw HouseError.message("Both sessions need the same three fixed reference boards. Two fit the transform; the third independently checks it.")}
    let adapter=PoseRefinement.matrix([1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1])!,world=PoseRefinement.matrix(registration.values)!
    var candidates:[simd_double4x4]=[],pairs:[(simd_double4x4,simd_double4x4)]=[]
    for board in boards {
      guard let a=anchor.referencePoses.first(where:{$0.boardID==board.id}).flatMap({PoseRefinement.matrix($0.matrix)}),let b=source.referencePoses.first(where:{$0.boardID==board.id}).flatMap({PoseRefinement.matrix($0.matrix)}) else{throw HouseError.message("Invalid reference pose.")}
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
    return(result,worst,RegistrationLink(anchorSegment:anchor.id,boardIDs:boards.map{$0.id},fingerprint:try fingerprint(source:source,anchor:anchor,boards:boards)))
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
        let actual=anchor.flatMap{try? fingerprint(source:house.segments[i],anchor:$0,boards:boards)}
        if anchor?.registration==nil || actual != link.fingerprint || boards.contains(where:{!$0.valid}) {
          house.segments[i].registration=nil;house.segments[i].registrationResidual=nil;house.segments[i].registrationLink=nil;changed=true
        }
      }
      if !changed {break}
    }
  }
}
