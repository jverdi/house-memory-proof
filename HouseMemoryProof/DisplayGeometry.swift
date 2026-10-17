import Foundation

// Display-only reduction retains original triangles/points and interpolates nothing.
// Metric evidence, exports and collision geometry always use full originals.
enum DisplayGeometry {
  static let sceneVertexBudget=400000
  static let textureBudget=24
  static func cost(_ mesh:Mesh)->Int {max(mesh.vertices.count,mesh.triangles.count)}
  static func budget(for mesh:Mesh,total:Int,objects:Int)->Int {
    let minimum=3,maxShared=max(0,sceneVertexBudget-minimum*objects)
    return max(minimum,min(cost(mesh),minimum+Int(Double(maxShared)*Double(cost(mesh))/Double(max(1,total)))))
  }
  static func reduce(_ mesh:Mesh,uv:[UV]?,budget:Int)->(Mesh,[UV]?) {
    guard cost(mesh)>budget else{return(mesh,uv)}
    var result=Mesh(),values:[UV]=[]
    if mesh.triangles.isEmpty {
      let step=max(1,Int(ceil(Double(mesh.vertices.count)/Double(max(1,budget)))))
      for i in stride(from:0,to:mesh.vertices.count,by:step) {result.vertices.append(mesh.vertices[i]);if let uv {values.append(uv[i])}}
    } else {
      let faces=mesh.triangles.count/3,step=max(1,Int(ceil(Double(faces)/Double(max(1,budget/3)))))
      var indices:[Int32:Int32]=[:]
      for face in stride(from:0,to:faces,by:step) {for offset in 0..<3 {let source=mesh.triangles[face*3+offset];if indices[source]==nil {indices[source]=Int32(result.vertices.count);result.vertices.append(mesh.vertices[Int(source)]);if let uv {values.append(uv[Int(source)])}};result.triangles.append(indices[source]!)}}
    }
    return(result,uv==nil ? nil:values)
  }
  static func notice(_ features:[Feature])->String {
    let vertices=features.reduce(0){$0+cost($1.mesh)},textures=Set(features.compactMap{$0.texture}).count
    return vertices>sceneVertexBudget || textures>textureBudget ? "Display detail limited for memory. Select a room for more detail; originals and exports are unchanged." : ""
  }
}
