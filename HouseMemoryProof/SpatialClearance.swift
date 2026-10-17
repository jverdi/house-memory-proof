import Foundation

// Conservative, renderer-independent clearance. Expanded triangle bounds can reject
// a usable path, but never certify empty space outside captured geometry.
struct SpatialClearance {
  struct Bounds {
    var low: V3
    var high: V3
    var centre: V3 { (low + high) * 0.5 }
    func union(_ b: Bounds) -> Bounds {
      Bounds(low: V3(min(low.x,b.low.x),min(low.y,b.low.y),min(low.z,b.low.z)),
             high: V3(max(high.x,b.high.x),max(high.y,b.high.y),max(high.z,b.high.z)))
    }
    func intersects(_ a: V3, _ b: V3, radius: Double) -> Bool {
      var enter = 0.0, exit = 1.0
      let starts = [a.x,a.y,a.z], ends = [b.x,b.y,b.z]
      let lo = [low.x-radius,low.y-radius,low.z-radius], hi = [high.x+radius,high.y+radius,high.z+radius]
      for axis in 0..<3 {
        let delta = ends[axis] - starts[axis]
        if abs(delta) < 1e-12 { if starts[axis] < lo[axis] || starts[axis] > hi[axis] { return false } }
        else {
          let t0 = (lo[axis]-starts[axis])/delta, t1 = (hi[axis]-starts[axis])/delta
          enter = max(enter,min(t0,t1)); exit = min(exit,max(t0,t1))
          if enter > exit { return false }
        }
      }
      return true
    }
  }
  struct Node { var bounds: Bounds; var start: Int; var count: Int; var left = -1; var right = -1 }
  private var items: [Bounds] = []
  private var nodes: [Node] = []
  private(set) var complete = true
  init(features: [Feature], limit: Int = 500000) {
    for f in features {
      let m = f.mesh
      let required = m.triangles.isEmpty ? m.vertices.count : m.triangles.count/3
      guard required <= limit-items.count else { complete = false; items = []; return }
      if m.triangles.isEmpty { items += m.vertices.map { Bounds(low:$0,high:$0) } }
      else {
        for i in stride(from:0,to:m.triangles.count,by:3) {
          let a=m.vertices[Int(m.triangles[i])],b=m.vertices[Int(m.triangles[i+1])],c=m.vertices[Int(m.triangles[i+2])]
          items.append(Bounds(low:a,high:a).union(Bounds(low:b,high:b)).union(Bounds(low:c,high:c)))
        }
      }
    }
    if !items.isEmpty { _ = build(0,items.count) }
  }
  private mutating func build(_ start:Int,_ end:Int)->Int {
    var bounds=items[start]
    for i in (start+1)..<end { bounds=bounds.union(items[i]) }
    let index=nodes.count
    nodes.append(Node(bounds:bounds,start:start,count:end-start))
    if end-start>16 {
      let size=bounds.high-bounds.low
      let axis=size.x>=size.y && size.x>=size.z ? 0 : size.y>=size.z ? 1 : 2
      func coordinate(_ b:Bounds)->Double { axis==0 ? b.centre.x : axis==1 ? b.centre.y : b.centre.z }
      items.replaceSubrange(start..<end,with:items[start..<end].sorted{coordinate($0)<coordinate($1)})
      let middle=(start+end)/2
      let left=build(start,middle),right=build(middle,end)
      nodes[index].left=left;nodes[index].right=right;nodes[index].count=0
    }
    return index
  }
  func isClear(from a:V3,to b:V3,radius:Double)->Bool {
    guard complete,a.finite,b.finite,radius.isFinite,radius>=0 else{return false}
    guard !nodes.isEmpty else{return true}
    var stack=[0]
    while let index=stack.popLast() {
      let n=nodes[index]
      guard n.bounds.intersects(a,b,radius:radius) else{continue}
      if n.count>0 {
        for i in n.start..<(n.start+n.count) where items[i].intersects(a,b,radius:radius){return false}
      }else{stack.append(n.left);stack.append(n.right)}
    }
    return true
  }
}
