import Foundation

enum EnvelopeSection:String,Codable,CaseIterable {case round="Round",rectangular="Rectangular"}
struct ServiceEnvelope:Codable,Equatable {
  var version=1
  var sourceFeatureID:UUID;var sourceRevision:Int;var sourceInterval:Int
  var sourceEndInterval:Int?=nil
  var section:EnvelopeSection;var widthMetres:Double;var heightMetres:Double?=nil;var widthAxis:V3?=nil
  var dimensionToleranceMetres:Double?=nil;var evidence:String;var recorded=Date()
  var valid:Bool {
    guard [1,2].contains(version),sourceRevision>0,(0..<127).contains(sourceInterval),widthMetres.isFinite,(0.001...4).contains(widthMetres),
      !evidence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,evidence.utf8.count<=4096,!evidence.contains("\0"),recorded.timeIntervalSince1970.isFinite,
      dimensionToleranceMetres.map({$0.isFinite && $0>0 && $0<min(widthMetres,heightMetres ?? widthMetres)/2}) ?? true else{return false}
    if version==1 {guard sourceEndInterval==nil else{return false}}
    else {guard section == .round,let end=sourceEndInterval,end>sourceInterval,end<127 else{return false}}
    switch section {
    case .round:return heightMetres==nil && widthAxis==nil
    case .rectangular:
      guard let heightMetres,let widthAxis else{return false}
      return heightMetres.isFinite && (0.001...4).contains(heightMetres) && widthAxis.finite && abs(widthAxis.length-1)<1e-6
    }
  }
  func mesh(along route:[V3])throws->Mesh {
    if version==2 {return try bentMesh(along:route)}
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
  // Piecewise circular sections meet at bisector planes. No smoothing changes
  // the recorded centerline, and caps delimit evidence rather than physical ends.
  private func bentMesh(along route:[V3])throws->Mesh {
    guard valid,let end=sourceEndInterval,route.count==end-sourceInterval+2,
      (3...128).contains(route.count),route.allSatisfy({$0.finite}) else{throw HouseError.message("Choose connected recorded intervals with one measured outer diameter.")}
    let radius=widthMetres/2,count=64
    let deltas=zip(route,route.dropFirst()).map{pair in pair.1-pair.0}
    guard deltas.allSatisfy({$0.length>0.00001}) else{throw HouseError.message("The recorded route contains a zero-length interval.")}
    let tangents=deltas.map{$0.normalized}
    var normals=[tangents[0]],bends=[V3()],stretches=[1.0],extensions=[0.0]
    for i in 1..<route.count-1 {
      let a=tangents[i-1],b=tangents[i],cosine=max(-1,min(1,a.dot(b)))
      guard cosine>=0 else{throw HouseError.message("A bend exceeds 90 degrees. Record more centerline detail or separate measured intervals.")}
      let half=sqrt((1+cosine)/2),bend=(b-a).normalized
      normals.append((a+b).normalized);bends.append(bend);stretches.append(1/half)
      extensions.append(radius*sqrt(max(0,(1-cosine)/(1+cosine))))
    }
    normals.append(tangents.last!);bends.append(V3());stretches.append(1);extensions.append(0)
    for i in deltas.indices {guard deltas[i].length>extensions[i]+extensions[i+1]+0.00001 else{throw HouseError.message("This bend is too tight for the recorded diameter. Add measured detail or use separate intervals.")}}
    // Non-neighboring evidence intervals must remain separated even after the
    // largest allowed miter expansion. Ambiguous overlaps are not fabricated.
    if deltas.count>2 {for i in 0..<deltas.count-2 {for j in i+2..<deltas.count {
      guard Self.segmentDistance(route[i],route[i+1],route[j],route[j+1])>2*radius*sqrt(2) else{throw HouseError.message("The measured envelope would overlap a nonadjacent route interval.")}
    }}}
    let reference=abs(normals[0].z)<0.9 ? V3(0,0,1):V3(0,1,0)
    var width=(reference-normals[0]*reference.dot(normals[0])).normalized
    var vertices:[V3]=[],triangles:[Int32]=[]
    for i in route.indices {
      if i>0 {
        // Minimal rotation preserves the circular ring's ordering through bends.
        let axis=normals[i-1].cross(normals[i]),cosine=normals[i-1].dot(normals[i])
        width=(width+axis.cross(width)+axis.cross(axis.cross(width))*(1/(1+cosine))).normalized
      }
      let height=normals[i].cross(width).normalized
      for j in 0..<count {
        let angle=2*Double.pi*Double(j)/Double(count),radial=width*cos(angle)+height*sin(angle)
        vertices.append(route[i]+(radial+bends[i]*(radial.dot(bends[i])*(stretches[i]-1)))*radius)
      }
    }
    let firstCap=Int32(vertices.count),lastCap=firstCap+1,lastRing=Int32((route.count-1)*count)
    vertices += [route[0],route.last!]
    for ring in 0..<route.count-1 {for j in 0..<count {
      let a=Int32(ring*count+j),b=Int32(ring*count+(j+1)%count),n=Int32(count)
      triangles += [a,b,a+n,b,b+n,a+n]
    }}
    for j in 0..<count {let a=Int32(j),b=Int32((j+1)%count);triangles += [firstCap,b,a,lastCap,lastRing+a,lastRing+b]}
    let result=Mesh(vertices:vertices,triangles:triangles)
    guard result.valid else{throw HouseError.message("The envelope exceeds supported coordinates.")};return result
  }
  private static func segmentDistance(_ a:V3,_ b:V3,_ c:V3,_ d:V3)->Double {
    let u=b-a,v=d-c,w=a-c,aa=u.dot(u),bb=u.dot(v),cc=v.dot(v),dd=u.dot(w),ee=v.dot(w),denominator=aa*cc-bb*bb
    var s=denominator>1e-15 ? max(0,min(1,(bb*ee-cc*dd)/denominator)):0
    var t=(bb*s+ee)/cc
    if t<0 {t=0;s=max(0,min(1,-dd/aa))}
    else if t>1 {t=1;s=max(0,min(1,(bb-dd)/aa))}
    return (w+u*s-v*t).length
  }
  static func feature(source:Feature,interval:Int,endInterval:Int?=nil,section:EnvelopeSection,width:Double,height:Double?,widthAxis:V3?,tolerance:Double?,evidence:String,house:House)throws->Feature {
    guard house.features.contains(source),source.envelope==nil,(2...128).contains(source.route.count),
      interval>=0,interval<source.route.count-1,[EvidenceKind.observed,.synthetic].contains(source.kind),
      DerivedEvidence.currentIDs(house).contains(source.id) else{throw HouseError.message("Choose a current observed route with two to 128 points. Reopen it if its source changed.")}
    let end=endInterval ?? interval
    guard end>=interval,end<source.route.count-1 else{throw HouseError.message("Choose an end interval within the recorded route.")}
    let value=ServiceEnvelope(version:endInterval==nil ? 1:2,sourceFeatureID:source.id,sourceRevision:source.revision,sourceInterval:interval,sourceEndInterval:endInterval,section:section,widthMetres:width,heightMetres:height,widthAxis:widthAxis,dimensionToleranceMetres:tolerance,evidence:evidence)
    let route=Array(source.route[interval...(end+1)]),mesh=try value.mesh(along:route)
    var result=Feature(name:source.name+" · measured envelope",trade:source.trade,roomID:source.roomID,stageID:source.stageID,kind:source.kind,mesh:mesh,route:route,sourceIDs:source.sourceIDs,
      notes:"Owner-recorded outer dimensions along the selected source intervals. Centerline placement and physical accuracy remain uncalibrated. End caps delimit the recorded intervals; they do not assert a physical cap or a connection. Circular bends use piecewise miter sections without smoothing the recorded centerline. Hidden continuation, fittings and bundle members are not inferred.",segmentID:source.segmentID,annotationSources:DerivedEvidence.dependencies([source.id],house:house))
    result.envelope=value;return result
  }
}
