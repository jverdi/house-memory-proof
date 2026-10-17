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

// Canonical two-metre tiles store source primitive references, never resampled
// measurement geometry. GPU meshes are materialized only for resident tiles.
struct SpatialDisplayIndex {
  struct Key:Hashable,Comparable {
    var x:Int;var y:Int;var z:Int
    static func <(a:Key,b:Key)->Bool {a.x != b.x ? a.x<b.x:a.y != b.y ? a.y<b.y:a.z<b.z}
  }
  struct Tile {var feature:Int;var primitives:[Int];var low:V3;var high:V3;var cost:Int}
  struct Allocation:Equatable {var tile:Int;var budget:Int;var textured:Bool}
  var features:[Feature]
  var tiles:[Tile]=[]
  init(features:[Feature],primitiveLimit:Int=2_000_000)throws {
    self.features=features
    var used=0
    for (feature,f) in features.enumerated() {
      try Task.checkCancellation()
      let mesh=f.mesh,points=mesh.triangles.isEmpty,count=points ? mesh.vertices.count:mesh.triangles.count/3
      guard count<=primitiveLimit-used else{throw HouseError.message("Display index exceeds its memory budget. Select one room to explore its full detail.")};used+=count
      var groups:[Key:Tile]=[:]
      for primitive in 0..<count {
        if primitive%4096==0 {try Task.checkCancellation()}
        let indices=points ? [primitive]:(0..<3).map{Int(mesh.triangles[primitive*3+$0])}
        let vertices=indices.map{mesh.vertices[$0]},centre=vertices.reduce(V3(),+)*(1/Double(vertices.count))
        let key=Key(x:Int(floor(centre.x/2)),y:Int(floor(centre.y/2)),z:Int(floor(centre.z/2)))
        if groups[key]==nil {groups[key]=Tile(feature:feature,primitives:[],low:vertices[0],high:vertices[0],cost:0)}
        groups[key]!.primitives.append(primitive);groups[key]!.cost+=points ? 1:3
        for v in vertices {groups[key]!.low=V3(min(groups[key]!.low.x,v.x),min(groups[key]!.low.y,v.y),min(groups[key]!.low.z,v.z));groups[key]!.high=V3(max(groups[key]!.high.x,v.x),max(groups[key]!.high.y,v.y),max(groups[key]!.high.z,v.z))}
      }
      tiles += groups.keys.sorted().map{groups[$0]!}
    }
  }
  func plan(camera:V3,budget:Int=DisplayGeometry.sceneVertexBudget,residents:Int=512)->[Allocation] {
    guard camera.finite,budget>=3,residents>0 else{return []}
    func distance(_ tile:Tile)->Double {
      let dx=max(0,max(tile.low.x-camera.x,camera.x-tile.high.x)),dy=max(0,max(tile.low.y-camera.y,camera.y-tile.high.y)),dz=max(0,max(tile.low.z-camera.z,camera.z-tile.high.z))
      return sqrt(dx*dx+dy*dy+dz*dz)
    }
    let ordered=tiles.indices.map{($0,distance(tiles[$0]))}.sorted{a,b in a.1==b.1 ? a.0<b.0:a.1<b.1}.prefix(min(residents,budget/3))
    let desired=ordered.map{entry->Int in let factor=entry.1<4 ? 1:entry.1<10 ? 4:16;return max(3,min(50000,tiles[entry.0].cost/factor))}
    let extra=desired.reduce(0){$0+max(0,$1-3)},scale=min(1,Double(max(0,budget-ordered.count*3))/Double(max(1,extra)))
    var textures=Set<String>()
    return zip(ordered,desired).map { entry,wanted in
      let tile=tiles[entry.0];var textured=false
      if let key=features[tile.feature].texture {if textures.contains(key) || textures.count<DisplayGeometry.textureBudget {textures.insert(key);textured=true}}
      return Allocation(tile:entry.0,budget:3+Int(Double(wanted-3)*scale),textured:textured)
    }
  }
  func materialize(_ allocation:Allocation)->(Feature,Mesh,[UV]?) {
    let tile=tiles[allocation.tile],feature=features[tile.feature],source=feature.mesh,points=source.triangles.isEmpty
    let capacity=max(1,allocation.budget/(points ? 1:3)),step=max(1,Int(ceil(Double(tile.primitives.count)/Double(capacity))))
    var mesh=Mesh(),uv:[UV]=[],lookup:[Int:Int32]=[:]
    for index in stride(from:0,to:tile.primitives.count,by:step) {
      let primitive=tile.primitives[index],indices=points ? [primitive]:(0..<3).map{Int(source.triangles[primitive*3+$0])}
      for original in indices {
        if lookup[original]==nil {lookup[original]=Int32(mesh.vertices.count);mesh.vertices.append(source.vertices[original]);if let coordinates=feature.uv {uv.append(coordinates[original])}}
        if !points {mesh.triangles.append(lookup[original]!)}
      }
    }
    return(feature,mesh,feature.uv==nil ? nil:uv)
  }
}
