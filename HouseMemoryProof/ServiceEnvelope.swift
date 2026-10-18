import Foundation

enum EnvelopeSection:String,Codable,CaseIterable {case round="Round",rectangular="Rectangular"}
struct ServiceEnvelope:Codable,Equatable {
  var version=1
  var sourceFeatureID:UUID;var sourceRevision:Int;var sourceInterval:Int
  var section:EnvelopeSection;var widthMetres:Double;var heightMetres:Double?=nil;var widthAxis:V3?=nil
  var dimensionToleranceMetres:Double?=nil;var evidence:String;var recorded=Date()
  var valid:Bool {
    guard version==1,sourceRevision>0,(0..<127).contains(sourceInterval),widthMetres.isFinite,(0.001...4).contains(widthMetres),
      !evidence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,evidence.utf8.count<=4096,!evidence.contains("\0"),recorded.timeIntervalSince1970.isFinite,
      dimensionToleranceMetres.map({$0.isFinite && $0>0 && $0<min(widthMetres,heightMetres ?? widthMetres)/2}) ?? true else{return false}
    switch section {
    case .round:return heightMetres==nil && widthAxis==nil
    case .rectangular:
      guard let heightMetres,let widthAxis else{return false}
      return heightMetres.isFinite && (0.001...4).contains(heightMetres) && widthAxis.finite && abs(widthAxis.length-1)<1e-6
    }
  }
  func mesh(along route:[V3])throws->Mesh {
    guard valid,route.count==2,route.allSatisfy({$0.finite}),
      (route[1]-route[0]).length>0.00001 else{throw HouseError.message("Select one nonzero straight route interval and record its measured outer size.")}
    let tangent=(route[1]-route[0]).normalized
    let reference=widthAxis ?? (abs(tangent.z)<0.9 ? V3(0,0,1):V3(0,1,0))
    let projected=reference-tangent*reference.dot(tangent)
    guard projected.length>=0.1 else{throw HouseError.message("The width direction is nearly parallel to this route. Choose the direction of the measured width across the duct.")}
    let w=projected.normalized,h=tangent.cross(w).normalized
    let count=section == .round ? 64:4
    var crossSection:[V3]=[]
    if section == .round {
      for i in 0..<count {let angle=2*Double.pi*Double(i)/Double(count);crossSection.append((w*cos(angle)+h*sin(angle))*(widthMetres/2))}
    }else {
      for (x,y) in [(-1.0,-1.0),(1.0,-1.0),(1.0,1.0),(-1.0,1.0)] {crossSection.append(w*(x*widthMetres/2)+h*(y*heightMetres!/2))}
    }
    var vertices=route.flatMap{center in crossSection.map{center+$0}},triangles:[Int32]=[]
    vertices += route
    for i in 0..<count {
      let a=Int32(i),b=Int32((i+1)%count),n=Int32(count)
      triangles += [a,b,a+n,b,b+n,a+n,2*n,b,a,2*n+1,a+n,b+n]
    }
    let mesh=Mesh(vertices:vertices,triangles:triangles)
    guard mesh.valid else{throw HouseError.message("The envelope exceeds supported coordinates.")};return mesh
  }
  static func feature(source:Feature,interval:Int,section:EnvelopeSection,width:Double,height:Double?,widthAxis:V3?,tolerance:Double?,evidence:String,house:House)throws->Feature {
    guard house.features.contains(source),source.envelope==nil,(2...128).contains(source.route.count),
      interval>=0,interval<source.route.count-1,[EvidenceKind.observed,.synthetic].contains(source.kind),
      DerivedEvidence.currentIDs(house).contains(source.id) else{throw HouseError.message("Choose a current observed route with two to 128 points. Reopen it if its source changed.")}
    let value=ServiceEnvelope(sourceFeatureID:source.id,sourceRevision:source.revision,sourceInterval:interval,section:section,widthMetres:width,heightMetres:height,widthAxis:widthAxis,dimensionToleranceMetres:tolerance,evidence:evidence)
    let route=[source.route[interval],source.route[interval+1]],mesh=try value.mesh(along:route)
    var result=Feature(name:source.name+" · measured envelope",trade:source.trade,roomID:source.roomID,stageID:source.stageID,kind:source.kind,mesh:mesh,route:route,sourceIDs:source.sourceIDs,
      notes:"Owner-recorded outer dimensions on one straight source interval. Centerline placement and physical accuracy remain uncalibrated. End caps delimit the recorded interval; they do not assert a physical cap or a connection. Bends, hidden continuation and bundle members are not inferred.",segmentID:source.segmentID,annotationSources:DerivedEvidence.dependencies([source.id],house:house))
    result.envelope=value;return result
  }
}
