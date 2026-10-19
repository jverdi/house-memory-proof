import Foundation

@MainActor enum ServiceEnvelopeTests {
  static func linearTapers()throws->Bool {
    let origin=V3(100,-20,3)
    for delta in [V3(1,0,0),V3(0,1,0),V3(0,0,1),V3(0.6,0.8,0.5)] {
      for reverse in [false,true] {
        let route=reverse ? [origin+delta,origin]:[origin,origin+delta]
        let tangent=(route[1]-route[0]).normalized
        let axis=abs(tangent.z)<0.9 ? V3(0,0,1):V3(0,1,0)
        var house=House.empty("Analytic endpoint sections");house.isDemo=true
        let source=Feature(name:"Recorded centerline",trade:.hvac,roomID:house.rooms[0].id,stageID:house.stages[0].id,
          kind:.synthetic,mesh:Mesh(vertices:route,triangles:[]),route:route)
        house.features=[source]
        for section in EnvelopeSection.allCases {
          let round=section == .round
          // Historical envelopes validate against their exact stored mesh;
          // preserve the original arithmetic order, including translated axes.
          let legacy=ServiceEnvelope(sourceFeatureID:source.id,sourceRevision:1,sourceInterval:0,section:section,
            widthMetres:round ? 0.05:0.2,heightMetres:round ? nil:0.1,widthAxis:round ? nil:axis,evidence:"Legacy dimensions")
          let reference=round ? (abs(tangent.z)<0.9 ? V3(0,0,1):V3(0,1,0)):axis
          let w=(reference-tangent*reference.dot(tangent)).normalized,h=tangent.cross(w).normalized
          var crossSection:[V3]=[]
          if round {for i in 0..<64 {let a=2*Double.pi*Double(i)/64;crossSection.append((w*cos(a)+h*sin(a))*0.025)}}
          else {for (x,y) in [(-1.0,-1.0),(1.0,-1.0),(1.0,1.0),(-1.0,1.0)] {crossSection.append(w*(x*0.2/2)+h*(y*0.1/2))}}
          guard try legacy.mesh(along:route).vertices==route.flatMap({center in crossSection.map{center+$0}})+route else{return false}
          let envelope=try ServiceEnvelope.feature(source:source,interval:0,section:section,
            width:round ? 0.05:0.2,height:round ? nil:0.1,widthAxis:round ? nil:axis,tolerance:0.001,
            evidence:"Analytic endpoint sizes and checked linear transition",house:house,endWidth:round ? 0.09:0.08,endHeight:round ? nil:0.16)
          let ringCount=round ? 64:4,mesh=envelope.mesh
          guard envelope.envelope?.version==3,envelope.route==route,mesh.vertices.count==2*ringCount+2,
            Array(mesh.vertices.suffix(2))==route else{return false}
          // Signed closed-surface volume is independent of the writer's basis
          // and ring construction; subtracting the origin avoids cancellation.
          var volume=0.0
          for i in stride(from:0,to:mesh.triangles.count,by:3) {
            let a=mesh.vertices[Int(mesh.triangles[i])]-route[0]
            let b=mesh.vertices[Int(mesh.triangles[i+1])]-route[0]
            let c=mesh.vertices[Int(mesh.triangles[i+2])]-route[0]
            volume += a.dot(b.cross(c))/6
          }
          let length=delta.length
          let expected:Double
          if round {
            let r0=0.025,r1=0.045
            expected=Double(ringCount)/2*sin(2*Double.pi/Double(ringCount))*length*(r0*r0+r0*r1+r1*r1)/3
            for endpoint in 0..<2 {for vertex in mesh.vertices[(endpoint*64)..<((endpoint+1)*64)] {
              let offset=vertex-route[endpoint]
              guard abs(offset.dot(tangent))<1e-10,abs(offset.length-(endpoint==0 ? r0:r1))<1e-10 else{return false}
            }}
          }else {expected=length*(0.2*0.1+(0.2*0.06+0.1 * -0.12)/2+(-0.12*0.06)/3)}
          guard abs(volume-expected)<1e-10 else{throw HouseError.message("Taper volume differs from independent endpoint-section integration.")}
          var saved=house;saved.features.append(envelope);try saved.validate()
          let restored=try JSONDecoder().decode(House.self,from:JSONEncoder().encode(saved));try restored.validate()
          guard restored==saved,saved.features[0]==source else{return false}
          var forged=saved;forged.features[1].envelope?.endWidthMetres=0.12
          do{try forged.validate();return false}catch{}
          var stale=saved;stale.features[0].revision+=1
          guard !DerivedEvidence.currentIDs(stale).contains(envelope.id) else{return false}
          var value=envelope.envelope!
          value.version=1;guard !value.valid else{return false}
          value=envelope.envelope!;value.sourceEndInterval=1;guard !value.valid else{return false}
          value=envelope.envelope!;value.endWidthMetres=nil;guard !value.valid else{return false}
          for size in [0,-1,Double.nan,Double.infinity,4.1] {
            value=envelope.envelope!;value.endWidthMetres=size;guard !value.valid else{return false}
          }
          value=envelope.envelope!;value.endWidthMetres=0.001;value.dimensionToleranceMetres=0.001
          guard !value.valid else{return false}
          value=envelope.envelope!;value.endHeightMetres=round ? 0.1:nil;guard !value.valid else{return false}
        }
      }
    }
    return true
  }
}
