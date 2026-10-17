import Foundation
import CryptoKit

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
    struct Ranked {var tile:Int;var distance:Double;var requested:Int}
    var ranked:[Ranked]=[]
    for index in tiles.indices {
      let separation=distance(tiles[index])
      let factor:Int=separation<4 ? 1:(separation<10 ? 4:16)
      let wanted=max(3,min(50000,tiles[index].cost/factor))
      ranked.append(Ranked(tile:index,distance:separation,requested:wanted))
    }
    ranked.sort {a,b in
      if a.distance==b.distance {return a.tile<b.tile}
      return a.distance<b.distance
    }
    let ordered=Array(ranked.prefix(min(residents,budget/3)))
    var extra=0
    for item in ordered {extra+=max(0,item.requested-3)}
    let remaining=max(0,budget-ordered.count*3)
    let scale=min(1.0,Double(remaining)/Double(max(1,extra)))
    var textures=Set<String>(),result:[Allocation]=[]
    for item in ordered {
      let tile=tiles[item.tile]
      var textured=false
      if let key=features[tile.feature].texture {
        if textures.contains(key) || textures.count<DisplayGeometry.textureBudget {textures.insert(key);textured=true}
      }
      let allocation=3+Int(Double(item.requested-3)*scale)
      result.append(Allocation(tile:item.tile,budget:allocation,textured:textured))
    }
    return result
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

// ARKit's face labels are suggestions. Preserve their provenance separately
// from reviewed service identities, and retain unclassified faces explicitly.
enum MeshSemantics {
  static func identity(anchor:UUID,label:String)->UUID {
    var bytes=Array(SHA256.hash(data:Data((anchor.uuidString+"|"+label).utf8)).prefix(16))
    bytes[6]=(bytes[6]&15)|80;bytes[8]=(bytes[8]&63)|128
    let groups=[0..<4,4..<6,6..<8,8..<10,10..<16]
    return UUID(uuidString:groups.map{range in range.map{String(format:"%02x",bytes[$0])}.joined()}.joined(separator:"-"))!
  }
  static func partition(_ mesh:Mesh,labels:[String],anchor:UUID,roomID:UUID,stage:Stage,segmentID:UUID)->[Feature] {
    guard mesh.valid,!mesh.triangles.isEmpty else{return []}
    let admitted=Set(["wall","floor","ceiling","door","window","table","seat","unknown"])
    var groups:[String:[Int]] = [:]
    for face in 0..<(mesh.triangles.count/3) {
      let supplied=face<labels.count ? labels[face]:"unknown",label=admitted.contains(supplied) ? supplied:"unknown"
      groups[label,default:[]].append(face)
    }
    return groups.keys.sorted().map{label in
      var part=Mesh(),indices:[Int32:Int32]=[:]
      for face in groups[label]! {for corner in 0..<3 {
        let source=mesh.triangles[face*3+corner]
        if indices[source]==nil {indices[source]=Int32(part.vertices.count);part.vertices.append(mesh.vertices[Int(source)])}
        part.triangles.append(indices[source]!)
      }}
      let trade:Trade=label=="floor" ? .floor:label=="ceiling" ? .ceiling:label=="wall" ? (stage.category == .finished ? .finish:.structure):.unknown
      return Feature(id:identity(anchor:anchor,label:label),name:"Observed "+label+" surface",trade:trade,roomID:roomID,stageID:stage.id,kind:.observed,mesh:part,notes:"ARKit face classification suggestion; unreviewed. It does not identify hidden electrical, plumbing or HVAC systems.",segmentID:segmentID,captureClassification:label,captureAnchorID:anchor)
    }
  }
}
