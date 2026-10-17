import Foundation

// Exact polygon clipping keeps the opposite wall outside a reveal, including
// triangles crossing the boundary. UVs are interpolated at new vertices.
enum RevealVolumes {
  struct Vertex {var p:V3;var uv:UV}
  static func clip(_ feature:Feature,to boundary:RevealBoundary)throws->Feature {
    guard boundary.valid else{throw HouseError.message("Invalid wall or ceiling boundary.")}
    var result=feature;var mesh=Mesh();var uv:[UV]=[]
    func coordinate(_ p:V3,_ axis:Int)->Double {let q=boundary.coordinates(p);return axis==0 ? q.x : axis==1 ? q.y : q.z}
    let planes:[(Int,Double,Double)]=[(0,1,0),(0,-1,boundary.width),(1,1,0),(1,-1,boundary.height),(2,1,boundary.finishOffset),(2,-1,boundary.depth)]
    if feature.mesh.triangles.isEmpty {
      for (i,p) in feature.mesh.vertices.enumerated() where boundary.contains(p) {mesh.vertices.append(p);if let values=feature.uv {uv.append(values[i])}}
    } else {
      for face in stride(from:0,to:feature.mesh.triangles.count,by:3) {
        if face%3000==0 {try Task.checkCancellation()}
        var polygon=(0..<3).map { offset -> Vertex in let i=Int(feature.mesh.triangles[face+offset]);return Vertex(p:feature.mesh.vertices[i],uv:feature.uv?[i] ?? UV(u:0,v:0))}
        for (axis,sign,offset) in planes {
          guard !polygon.isEmpty else{break};var output:[Vertex]=[]
          var a=polygon.last!;var da=sign*coordinate(a.p,axis)+offset
          for b in polygon {
            let db=sign*coordinate(b.p,axis)+offset
            if (da>=0) != (db>=0) {let t=da/(da-db);output.append(Vertex(p:a.p+(b.p-a.p)*t,uv:UV(u:a.uv.u+(b.uv.u-a.uv.u)*t,v:a.uv.v+(b.uv.v-a.uv.v)*t)))}
            if db>=0 {output.append(b)};a=b;da=db
          };polygon=output
        }
        if polygon.count>=3 {for i in 1..<(polygon.count-1) {for item in [polygon[0],polygon[i],polygon[i+1]] {mesh.triangles.append(Int32(mesh.vertices.count));mesh.vertices.append(item.p);uv.append(item.uv)}}}
        guard mesh.vertices.count<=500000 else{throw HouseError.message("Reveal volume exceeds its geometry budget. Use a smaller capture segment.")}
      }
    }
    result.mesh=mesh;result.uv=feature.uv == nil ? nil : uv;result.route=[];return result
  }
  static func current(_ boundary:RevealBoundary,house:House)->Bool {
    guard boundary.valid,let segment=house.segments.first(where:{$0.id==boundary.segmentID}),let fingerprint=try? VisualMapping.fingerprint(house:house,segment:segment) else{return false}
    return fingerprint==boundary.sourceFingerprint
  }
}
