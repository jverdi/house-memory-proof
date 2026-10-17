import Foundation

// Conservative, renderer-independent clearance. Expanded triangle bounds can reject
// a usable path, but never certify empty space outside captured geometry.
struct SpatialClearance {
  struct Bounds {
    var low: V3
    var high: V3
    var centre: V3 { (low + high) * 0.5 }
    func union(_ b: Bounds) -> Bounds {
      Bounds(
        low: V3(min(low.x, b.low.x), min(low.y, b.low.y), min(low.z, b.low.z)),
        high: V3(max(high.x, b.high.x), max(high.y, b.high.y), max(high.z, b.high.z)))
    }
    func intersects(_ a: V3, _ b: V3, radius: Double) -> Bool {
      intersects(a,b,below:radius,above:radius,radius:radius)
    }
    // Minkowski bounds for a swept upright body. This encloses the capsule,
    // conservatively refusing corner grazes instead of leaving vertical gaps.
    func intersects(_ a:V3,_ b:V3,below:Double,above:Double,radius:Double)->Bool {
      var enter = 0.0
      var exit = 1.0
      let starts = [a.x, a.y, a.z]
      let ends = [b.x, b.y, b.z]
      let lo = [low.x - radius, low.y - radius, low.z - above]
      let hi = [high.x + radius, high.y + radius, high.z + below]
      for axis in 0..<3 {
        let delta = ends[axis] - starts[axis]
        if abs(delta) < 1e-12 {
          if starts[axis] < lo[axis] || starts[axis] > hi[axis] { return false }
        } else {
          let t0 = (lo[axis] - starts[axis]) / delta
          let t1 = (hi[axis] - starts[axis]) / delta
          enter = max(enter, min(t0, t1))
          exit = min(exit, max(t0, t1))
          if enter > exit { return false }
        }
      }
      return true
    }
  }
  struct Node {
    var bounds: Bounds
    var start: Int
    var count: Int
    var left = -1
    var right = -1
  }
  private var items: [Bounds] = []
  private var nodes: [Node] = []
  private var floors=FloorSupport()
  private(set) var complete = true
  private(set) var coverageCentre: V3?
  private var coverageRadius = 0.0
  var primitiveCount: Int { items.count+floors.triangles.count }
  var hasFloorSupport:Bool {!floors.isEmpty}
  init(features: [Feature], limit: Int = 500000) {
    for f in features {
      let m = f.mesh
      let required = m.triangles.isEmpty ? m.vertices.count : m.triangles.count / 3
      guard required <= limit - primitiveCount else {
        complete = false
        items = []
        return
      }
      if m.triangles.isEmpty {
        items += m.vertices.map { Bounds(low: $0, high: $0) }
      } else {
        for i in stride(from: 0, to: m.triangles.count, by: 3) {
          let a = m.vertices[Int(m.triangles[i])]
          let b = m.vertices[Int(m.triangles[i + 1])]
          let c = m.vertices[Int(m.triangles[i + 2])]
          if f.trade == .floor,floors.append(a,b,c) {continue}
          items.append(
            Bounds(low: a, high: a).union(Bounds(low: b, high: b)).union(Bounds(low: c, high: c)))
        }
      }
    }
    if !items.isEmpty { _ = build(0, items.count) };floors.finish()
  }
  // Use original primitive bounds, not display LOD. The tile bounds include
  // crossing triangles whose centres lie outside this neighbourhood.
  init(index: SpatialDisplayIndex, camera: V3, radius: Double = 4, limit: Int = 500000) throws {
    coverageCentre = camera
    coverageRadius = radius
    guard camera.finite, radius.isFinite, radius > 0, limit > 0 else { complete = false; return }
    for tile in index.tiles {
      try Task.checkCancellation()
      let dx=max(0,max(tile.low.x-camera.x,camera.x-tile.high.x))
      let dy=max(0,max(tile.low.y-camera.y,camera.y-tile.high.y))
      let dz=max(0,max(tile.low.z-camera.z,camera.z-tile.high.z))
      guard dx*dx+dy*dy+dz*dz <= radius*radius else { continue }
      let mesh=index.features[tile.feature].mesh
      for (offset,primitive) in tile.primitives.enumerated() {
        if offset%4096==0 { try Task.checkCancellation() }
        guard primitiveCount < limit else { complete=false; items=[]; return }
        if mesh.triangles.isEmpty {
          let p=mesh.vertices[primitive]; items.append(Bounds(low:p,high:p))
        } else {
          let a=mesh.vertices[Int(mesh.triangles[primitive*3])]
          let b=mesh.vertices[Int(mesh.triangles[primitive*3+1])]
          let c=mesh.vertices[Int(mesh.triangles[primitive*3+2])]
          if index.features[tile.feature].trade == .floor,floors.append(a,b,c) {continue}
          items.append(Bounds(low:a,high:a).union(Bounds(low:b,high:b)).union(Bounds(low:c,high:c)))
        }
      }
    }
    if !items.isEmpty { _ = build(0, items.count) };floors.finish()
    try Task.checkCancellation()
  }
  private mutating func build(_ start: Int, _ end: Int) -> Int {
    var bounds = items[start]
    for i in (start + 1)..<end { bounds = bounds.union(items[i]) }
    let index = nodes.count
    nodes.append(Node(bounds: bounds, start: start, count: end - start))
    if end - start > 16 {
      let size = bounds.high - bounds.low
      let axis = size.x >= size.y && size.x >= size.z ? 0 : size.y >= size.z ? 1 : 2
      func coordinate(_ b: Bounds) -> Double {
        axis == 0 ? b.centre.x : axis == 1 ? b.centre.y : b.centre.z
      }
      items.replaceSubrange(
        start..<end, with: items[start..<end].sorted { coordinate($0) < coordinate($1) })
      let middle = (start + end) / 2
      let left = build(start, middle)
      let right = build(middle, end)
      nodes[index].left = left
      nodes[index].right = right
      nodes[index].count = 0
    }
    return index
  }
  func isClear(from a: V3, to b: V3, radius: Double) -> Bool {
    sweptClear(from:a,to:b,below:radius,above:radius,radius:radius)
  }
  // Eye-relative virtual walker: 20 cm horizontal radius, feet 1.55 m below
  // the camera and head 22 cm above it. It does not infer a physical floor.
  func isWalkClear(from a:V3,to b:V3)->Bool {
    sweptClear(from:a,to:b,below:1.55,above:0.22,radius:0.20)
  }
  // Follow observed floor triangles without assuming the phone was held at
  // standing eye height. Preserve its actual height above the floor while
  // checking a 1.77 m upright body, a 24 cm step and head clearance throughout.
  // Point clouds or regions with no classified floor keep the camera-corridor
  // fallback. A floor hole in an otherwise observed floor is never bridged.
  func walkingDestination(from a:V3,toward b:V3,eyeHeight savedHeight:Double?=nil)->(position:V3,eyeHeight:Double)? {
    guard complete,a.finite,b.finite else{return nil}
    guard !floors.isEmpty else{return isWalkClear(from:a,to:b) ? (b,1.6):nil}
    func support(at point:V3)->Double? {
      var heights:[Double]=[]
      for x in [-0.20,0,0.20] {for y in [-0.20,0,0.20] {
        guard let height=floors.height(at:point+V3(x,y,0)) else{return nil};heights.append(height)
      }}
      guard let high=heights.max(),let low=heights.min(),high-low<=0.48 else{return nil}
      return high
    }
    guard let start=support(at:a) else{return nil}
    let eyeHeight=savedHeight ?? (a.z-start),horizontal=hypot(b.x-a.x,b.y-a.y)
    guard eyeHeight.isFinite,eyeHeight>=0.4,eyeHeight<=2.2 else{return nil}
    guard horizontal<=2 else{return nil}
    let steps=max(1,Int(ceil(horizontal/0.05)))
    var previous=a,previousFloor=start
    for step in 1...steps {
      let fraction=Double(step)/Double(steps)
      var next=a+(b-a)*fraction;next.z=previousFloor+eyeHeight
      guard let floor=support(at:next),abs(floor-previousFloor)<=0.24 else{return nil}
      next.z=floor+eyeHeight
      let high=max(floor,previousFloor),raisedFrom=V3(previous.x,previous.y,high+eyeHeight),raisedTo=V3(next.x,next.y,high+eyeHeight)
      let below=eyeHeight-0.03,above=max(0.22,1.80-eyeHeight)
      guard sweptClear(from:previous,to:raisedFrom,below:below,above:above,radius:0.20),
        sweptClear(from:raisedFrom,to:raisedTo,below:below,above:above,radius:0.20),
        sweptClear(from:raisedTo,to:next,below:below,above:above,radius:0.20) else{return nil}
      previous=next;previousFloor=floor
    }
    return (previous,eyeHeight)
  }
  private func sweptClear(from a:V3,to b:V3,below:Double,above:Double,radius:Double)->Bool {
    guard complete,a.finite,b.finite,radius.isFinite,radius>=0,
      below.isFinite,above.isFinite,below>=0,above>=0 else{return false}
    if let centre=coverageCentre {
      // Bound every corner of both end boxes. Their convex hull contains the
      // complete swept body, including its feet outside the camera's vicinity.
      for end in [a,b] {for x in [-radius,radius] {for y in [-radius,radius] {for z in [-below,above] {
        guard (end+V3(x,y,z)-centre).length<=coverageRadius else{return false}
      }}}}
    }
    guard !floors.intersects(from:a,to:b,below:below,above:above,radius:radius) else{return false}
    guard !nodes.isEmpty else { return true }
    var stack = [0]
    while let index = stack.popLast() {
      let n = nodes[index]
      guard n.bounds.intersects(a,b,below:below,above:above,radius:radius) else { continue }
      if n.count > 0 {
        for i in n.start..<(n.start + n.count) where items[i].intersects(a,b,below:below,above:above,radius:radius) {
          return false
        }
      } else {
        stack.append(n.left)
        stack.append(n.right)
      }
    }
    return true
  }
}

// Only actual, approximately horizontal triangles labelled as floor support
// walking. Triangle bounds alone cannot fill a stairwell or an absent surface.
private struct FloorSupport {
  struct Triangle {var a:V3;var b:V3;var c:V3;var bounds:SpatialClearance.Bounds}
  var triangles:[Triangle]=[]
  var nodes:[SpatialClearance.Node]=[]
  var isEmpty:Bool {triangles.isEmpty}
  mutating func append(_ a:V3,_ b:V3,_ c:V3)->Bool {
    let u=b-a,v=c-a,n=V3(u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x)
    guard n.finite,n.length>1e-10,abs(n.z)/n.length>=0.707 else{return false}
    let bounds=SpatialClearance.Bounds(low:a,high:a).union(.init(low:b,high:b)).union(.init(low:c,high:c))
    triangles.append(Triangle(a:a,b:b,c:c,bounds:bounds))
    return true
  }
  mutating func finish(){if !triangles.isEmpty {_=build(0,triangles.count)}}
  private mutating func build(_ start:Int,_ end:Int)->Int {
    var bounds=triangles[start].bounds
    for i in (start+1)..<end {bounds=bounds.union(triangles[i].bounds)}
    let index=nodes.count;nodes.append(.init(bounds:bounds,start:start,count:end-start))
    if end-start>16 {
      let x=bounds.high.x-bounds.low.x>=bounds.high.y-bounds.low.y
      triangles.replaceSubrange(start..<end,with:triangles[start..<end].sorted{x ? $0.bounds.centre.x<$1.bounds.centre.x:$0.bounds.centre.y<$1.bounds.centre.y})
      let middle=(start+end)/2,left=build(start,middle),right=build(middle,end)
      nodes[index].left=left;nodes[index].right=right;nodes[index].count=0
    }
    return index
  }
  func height(at point:V3)->Double? {
    guard !nodes.isEmpty else{return nil}
    var stack=[0],highest:Double?
    while let index=stack.popLast() {
      let node=nodes[index],bounds=node.bounds
      guard point.x>=bounds.low.x-1e-8,point.x<=bounds.high.x+1e-8,point.y>=bounds.low.y-1e-8,point.y<=bounds.high.y+1e-8,
        bounds.low.z<=point.z-0.35,bounds.high.z>=point.z-2.5 else{continue}
      if node.count==0 {stack.append(node.left);stack.append(node.right);continue}
      for i in node.start..<(node.start+node.count) {
        let t=triangles[i],u=t.b-t.a,v=t.c-t.a,p=point-t.a,denominator=u.x*v.y-u.y*v.x
        guard abs(denominator)>1e-10 else{continue}
        let b=(p.x*v.y-p.y*v.x)/denominator,c=(u.x*p.y-u.y*p.x)/denominator
        guard b >= -1e-8,c >= -1e-8,b+c<=1+1e-8 else{continue}
        let z=t.a.z+b*u.z+c*v.z
        guard z<=point.z-0.35,z>=point.z-2.5 else{continue}
        highest=max(highest ?? z,z)
      }
    }
    return highest
  }
  // A sloping floor's bounding box contains empty space above its low end.
  // Use continuous triangle/axis-aligned-box SAT after BVH pruning, retaining
  // exact floor geometry for collision as well as for support. No display LOD
  // or hidden-layer state participates in this check.
  func intersects(from a:V3,to b:V3,below:Double,above:Double,radius:Double)->Bool {
    guard !nodes.isEmpty else{return false}
    var stack=[0]
    while let index=stack.popLast() {
      let node=nodes[index]
      guard node.bounds.intersects(a,b,below:below,above:above,radius:radius) else{continue}
      if node.count==0 {stack.append(node.left);stack.append(node.right);continue}
      for i in node.start..<(node.start+node.count) {
        let triangle=triangles[i]
        guard triangle.bounds.intersects(a,b,below:below,above:above,radius:radius) else{continue}
        if triangle.intersects(from:a,to:b,below:below,above:above,radius:radius){return true}
      }
    }
    return false
  }
}

private extension FloorSupport.Triangle {
  func intersects(from start:V3,to end:V3,below:Double,above:Double,radius:Double)->Bool {
    func dot(_ u:V3,_ v:V3)->Double {u.x*v.x+u.y*v.y+u.z*v.z}
    func cross(_ u:V3,_ v:V3)->V3 {V3(u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x)}
    let centre=start+V3(0,0,(above-below)/2),motion=end-start
    let vertices=[a-centre,b-centre,c-centre],edges=[b-a,c-b,a-c]
    let basis=[V3(1,0,0),V3(0,1,0),V3(0,0,1)]
    var axes=basis+[cross(edges[0],edges[1])]
    for edge in edges {for axis in basis {axes.append(cross(edge,axis))}}
    var enter=0.0,exit=1.0
    for raw in axes {
      let length=raw.length;guard length>1e-12 else{continue}
      let axis=raw*(1/length),extent=(abs(axis.x)+abs(axis.y))*radius+abs(axis.z)*(below+above)/2
      let projected=vertices.map{dot($0,axis)}
      let low=projected.min()!-extent-1e-9,high=projected.max()!+extent+1e-9,speed=dot(motion,axis)
      if abs(speed)<1e-12 {if low>0 || high<0 {return false}}
      else {
        let first=low/speed,last=high/speed
        enter=max(enter,min(first,last));exit=min(exit,max(first,last))
        if enter>exit{return false}
      }
    }
    return true
  }
}

