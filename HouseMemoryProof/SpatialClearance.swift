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
  private(set) var complete = true
  private(set) var coverageCentre: V3?
  private var coverageRadius = 0.0
  var primitiveCount: Int { items.count }
  init(features: [Feature], limit: Int = 500000) {
    for f in features {
      let m = f.mesh
      let required = m.triangles.isEmpty ? m.vertices.count : m.triangles.count / 3
      guard required <= limit - items.count else {
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
          items.append(
            Bounds(low: a, high: a).union(Bounds(low: b, high: b)).union(Bounds(low: c, high: c)))
        }
      }
    }
    if !items.isEmpty { _ = build(0, items.count) }
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
        guard items.count < limit else { complete=false; items=[]; return }
        if mesh.triangles.isEmpty {
          let p=mesh.vertices[primitive]; items.append(Bounds(low:p,high:p))
        } else {
          let a=mesh.vertices[Int(mesh.triangles[primitive*3])]
          let b=mesh.vertices[Int(mesh.triangles[primitive*3+1])]
          let c=mesh.vertices[Int(mesh.triangles[primitive*3+2])]
          items.append(Bounds(low:a,high:a).union(Bounds(low:b,high:b)).union(Bounds(low:c,high:c)))
        }
      }
    }
    if !items.isEmpty { _ = build(0, items.count) }
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
