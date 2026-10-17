import Foundation
import CryptoKit

// Display-only reduction retains complete surfaces when admitted, otherwise
// presents sampled source points. Dropping faces made solid walls look like
// missing capture, so partial triangle soups are never used as a display LOD.
// Metric evidence, exports and collision geometry always use full originals.
enum DisplayGeometry {
  static let sceneVertexBudget=400000
  static let textureBudget=24
  static let textureByteBudget=64*1024*1024
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
      var seen=Set<Int32>()
      for face in stride(from:0,to:faces,by:step) {for offset in 0..<3 {
        let source=mesh.triangles[face*3+offset]
        if seen.insert(source).inserted {result.vertices.append(mesh.vertices[Int(source)]);if let uv {values.append(uv[Int(source)])}}
      }}
    }
    return(result,uv==nil ? nil:values)
  }
  static func notice(_ features:[Feature])->String {
    let vertices=features.reduce(0){$0+cost($1.mesh)},textures=Set(features.compactMap{$0.texture}).count
    return vertices>sceneVertexBudget || textures>textureBudget ? "Nearby surfaces retain full detail. Distant or over-budget detail may appear as source points. Select a room for more detail; measurements and exports use originals." : ""
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
      let factor:Int=separation<10 ? 1:16
      let wanted=max(3,min(50000,tiles[index].cost/factor))
      ranked.append(Ranked(tile:index,distance:separation,requested:wanted))
    }
    ranked.sort {a,b in
      if a.distance==b.distance {return a.tile<b.tile}
      return a.distance<b.distance
    }
    let ordered=Array(ranked.prefix(min(residents,budget/3)))
    // Reserve a minimum for distant context, then spend the remaining budget
    // nearest-first. Scaling every allocation also perforated the closest wall.
    var remaining=max(0,budget-ordered.count*3)
    var textures=Set<String>(),result:[Allocation]=[]
    for item in ordered {
      let tile=tiles[item.tile]
      var textured=false
      if let key=features[tile.feature].texture {
        if textures.contains(key) || textures.count<DisplayGeometry.textureBudget {textures.insert(key);textured=true}
      }
      let extra=min(max(0,item.requested-3),remaining),allocation=3+extra
      remaining-=extra
      result.append(Allocation(tile:item.tile,budget:allocation,textured:textured))
    }
    return result
  }

  func materialize(_ allocation:Allocation)->(Feature,Mesh,[UV]?) {
    let tile=tiles[allocation.tile],feature=features[tile.feature],source=feature.mesh,points=source.triangles.isEmpty
    let completeSurface = !points && allocation.budget>=tile.cost
    let capacity=max(1,allocation.budget/(points ? 1:3)),step=completeSurface ? 1:max(1,Int(ceil(Double(tile.primitives.count)/Double(capacity))))
    var mesh=Mesh(),uv:[UV]=[],lookup:[Int:Int32]=[:]
    for index in stride(from:0,to:tile.primitives.count,by:step) {
      let primitive=tile.primitives[index],indices=points ? [primitive]:(0..<3).map{Int(source.triangles[primitive*3+$0])}
      for original in indices {
        if lookup[original]==nil {lookup[original]=Int32(mesh.vertices.count);mesh.vertices.append(source.vertices[original]);if let coordinates=feature.uv {uv.append(coordinates[original])}}
        if completeSurface {mesh.triangles.append(lookup[original]!)}
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
      return Feature(id:identity(anchor:anchor,label:label),name:"Observed "+label+" surface",trade:trade,roomID:roomID,stageID:stage.id,kind:.observed,mesh:part,notes:"ARKit face classification suggestion; unreviewed. It does not identify hidden electrical, plumbing or HVAC systems.",segmentID:segmentID,captureClassification:label,captureAnchorID:anchor,geometrySource:.capturedMesh)
    }
  }
}

extension MeshSemantics {
  static func publishCaptured(_ snapshot:[Feature],segmentID:UUID,into house:inout House) {
    let old=Dictionary(house.features.filter{$0.segmentID==segmentID && $0.resolvedGeometrySource == .capturedMesh}.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    let replacements=snapshot.filter{$0.segmentID==segmentID && $0.resolvedGeometrySource == .capturedMesh}.map{input in
      var feature=input
      if let prior=old[input.id] {
        feature.revision=prior.revision+(prior.mesh==input.mesh ? 0:1)
        feature.name=prior.name;feature.hidden=prior.hidden
        if prior.reviewed {feature.trade=prior.trade;feature.reviewed=true}
      }
      return feature
    }
    house.features.removeAll{$0.segmentID==segmentID && $0.resolvedGeometrySource == .capturedMesh}
    house.features.append(contentsOf:replacements)
  }
  // Transfer display labels only where every fused triangle vertex agrees with
  // nearby, similarly oriented original faces. Unseen/ambiguous faces stay
  // unclassified; no geometry or measurement is inferred from a label.
  static func transfer(_ surface:Feature,from originals:[Feature])throws->[Feature] {
    guard surface.mesh.valid else{throw HouseError.message("Invalid reconstructed surface.")}
    let sources=originals.filter{$0.segmentID==surface.segmentID && $0.resolvedGeometrySource == .capturedMesh}
    let index=try CapturedFaceLabels(sources)
    // Reference-owned accumulators avoid copying each growing mesh/dictionary
    // out of another dictionary on every triangle (quadratic copy-on-write).
    final class Part {var mesh=Mesh();var lookup:[Int32:Int32]=[:];var trade=Trade.unknown}
    var parts:[String:Part]=[:]
    for face in stride(from:0,to:surface.mesh.triangles.count,by:3) {
      if face%3000==0 {try Task.checkCancellation()}
      let ids=Array(surface.mesh.triangles[face..<face+3]),p=ids.map{surface.mesh.vertices[Int($0)]}
      let normal=(p[1]-p[0]).cross(p[2]-p[0]).normalized
      let labels=p.map{index.label(at:$0,normal:normal)}
      let same=labels[0] != nil && labels.allSatisfy{$0?.0==labels[0]?.0 && $0?.1==labels[0]?.1}
      let label=same ? labels[0]!.0:"unknown",trade=same ? labels[0]!.1:Trade.unknown
      let part:Part
      if let existing=parts[label] {part=existing}else{part=Part();part.trade=trade;parts[label]=part}
      for id in ids {
        if part.lookup[id]==nil {part.lookup[id]=Int32(part.mesh.vertices.count);part.mesh.vertices.append(surface.mesh.vertices[Int(id)])}
        part.mesh.triangles.append(part.lookup[id]!)
      }
    }
    return parts.keys.sorted().map{label in
      let part=parts[label]!
      var result=surface;result.id=identity(anchor:surface.id,label:label);result.mesh=part.mesh
      result.captureClassification=label;result.captureAnchorID=nil;result.trade=part.trade
      result.name="Reconstructed \(label) surface";result.hidden=false
      result.notes += " Display classification transferred only within 3 cm of agreeing captured faces; unreviewed and not a service identification."
      return result
    }
  }
}

private struct CapturedFaceLabels {
  struct Face {var a:V3;var b:V3;var c:V3;var normal:V3;var label:String;var trade:Trade;var bounds:SpatialClearance.Bounds}
  struct Node {var bounds:SpatialClearance.Bounds;var start:Int;var count:Int;var left = -1;var right = -1}
  var faces:[Face]=[];var nodes:[Node]=[]
  init(_ originals:[Feature])throws {
    for f in originals {
      guard let label=f.captureClassification,label != "unknown",f.mesh.valid else{continue}
      guard f.mesh.triangles.count/3<=500000-faces.count else{throw HouseError.message("Classified surface exceeds the local processing budget. Reconstruct a smaller capture session.")}
      for i in stride(from:0,to:f.mesh.triangles.count,by:3) {
        if i%3000==0 {try Task.checkCancellation()}
        let a=f.mesh.vertices[Int(f.mesh.triangles[i])],b=f.mesh.vertices[Int(f.mesh.triangles[i+1])],c=f.mesh.vertices[Int(f.mesh.triangles[i+2])]
        let n=(b-a).cross(c-a);guard n.length>1e-9 else{continue}
        let bounds=SpatialClearance.Bounds(low:a,high:a).union(.init(low:b,high:b)).union(.init(low:c,high:c))
        faces.append(Face(a:a,b:b,c:c,normal:n.normalized,label:label,trade:f.trade,bounds:bounds))
      }
    }
    if !faces.isEmpty {_ = try build(0,faces.count)}
  }
  private mutating func build(_ start:Int,_ end:Int)throws->Int {
    try Task.checkCancellation()
    var bounds=faces[start].bounds
    for i in start+1..<end {bounds=bounds.union(faces[i].bounds)}
    let index=nodes.count;nodes.append(Node(bounds:bounds,start:start,count:end-start))
    if end-start>16 {
      let size=bounds.high-bounds.low,axis=size.x>=size.y && size.x>=size.z ? 0:size.y>=size.z ? 1:2
      func coordinate(_ f:Face)->Double {let c=f.bounds.centre;return axis==0 ? c.x:axis==1 ? c.y:c.z}
      faces.replaceSubrange(start..<end,with:faces[start..<end].sorted{coordinate($0)<coordinate($1)})
      let middle=(start+end)/2,left=try build(start,middle),right=try build(middle,end)
      nodes[index].left=left;nodes[index].right=right;nodes[index].count=0
    }
    return index
  }
  private func closest(_ p:V3,_ f:Face)->V3 {
    let ab=f.b-f.a,ac=f.c-f.a,ap=p-f.a,d1=ab.dot(ap),d2=ac.dot(ap)
    if d1<=0 && d2<=0{return f.a}
    let bp=p-f.b,d3=ab.dot(bp),d4=ac.dot(bp)
    if d3>=0 && d4<=d3{return f.b}
    let vc=d1*d4-d3*d2
    if vc<=0 && d1>=0 && d3<=0{return f.a+ab*(d1/(d1-d3))}
    let cp=p-f.c,d5=ab.dot(cp),d6=ac.dot(cp)
    if d6>=0 && d5<=d6{return f.c}
    let vb=d5*d2-d1*d6
    if vb<=0 && d2>=0 && d6<=0{return f.a+ac*(d2/(d2-d6))}
    let va=d3*d6-d5*d4
    if va<=0 && d4-d3>=0 && d5-d6>=0{return f.b+(f.c-f.b)*((d4-d3)/((d4-d3)+(d5-d6)))}
    let denominator=va+vb+vc
    guard abs(denominator)>1e-18 else{return f.a}
    return f.a+ab*(vb/denominator)+ac*(vc/denominator)
  }
  func label(at p:V3,normal:V3)->(String,Trade)? {
    guard !nodes.isEmpty,normal.length>0.9 else{return nil}
    var stack=[0],result:(String,Trade)?
    while let i=stack.popLast() {
      let node=nodes[i];guard node.bounds.intersects(p,p,radius:0.03) else{continue}
      if node.count==0 {stack.append(node.left);stack.append(node.right);continue}
      for j in node.start..<node.start+node.count {
        let f=faces[j]
        guard abs(normal.dot(f.normal))>=0.95,(closest(p,f)-p).length<=0.03 else{continue}
        if let prior=result,prior.0 != f.label || prior.1 != f.trade{return nil}
        result=(f.label,f.trade)
      }
    }
    return result
  }
}
