import GameController
import Metal
import SceneKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
  case rough = "Rough-in"
  case finished = "Finished"
  case ghost = "Ghost"
  case evidence = "All evidence"
  var id: String { rawValue }
}
struct SceneOptions: Equatable {
  var mode: ViewMode = .rough
  var trades: Set<Trade> = Set(Trade.allCases)
  var ceilings = false
  var room: UUID?
  var stage: UUID?
}
enum SceneBuilder {
  static func visible(_ f: Feature, _ o: SceneOptions) -> Bool {
    guard !f.hidden, f.artifactValid != false, o.trades.contains(f.trade),
      o.room == nil || o.room == f.roomID
    else { return false }
    if f.trade == .ceiling && !o.ceilings { return false }
    if let stage = o.stage, f.stageID != stage { return false }
    switch o.mode {
    case .rough: return f.trade != .finish && f.trade != .ceiling
    case .finished:
      return f.trade == .finish || f.trade == .ceiling || f.trade == .floor || f.trade == .unknown
    case .ghost, .evidence: return true
    }
  }
  static func eligibleStages(_ h: House, options: SceneOptions) -> Set<UUID> {
    if let stage = options.stage { return [stage] }
    let finished = Set(h.stages.filter { $0.name.lowercased().contains("finish") }.map { $0.id })
    switch options.mode {
    case .rough: return Set(h.stages.map { $0.id }).subtracting(finished)
    case .finished: return finished
    case .ghost, .evidence: return Set(h.stages.map { $0.id })
    }
  }
  static func activeUnregisteredSegment(_ h: House, options: SceneOptions) -> UUID? {
    let stages = eligibleStages(h, options: options)
    return h.segments.last(where: {
      (options.room == nil || $0.roomID == options.room) && stages.contains($0.stageID)
        && $0.registration == nil
    })?.id
  }
  static func features(_ h: House, options: SceneOptions) -> [Feature] {
    let stages = eligibleStages(h, options: options)
    let unregistered = activeUnregisteredSegment(h, options: options)
    let current=DerivedEvidence.currentIDs(h)
    return h.features.filter { f in
      guard current.contains(f.id),visible(f, options),
        stages.contains(f.stageID) || (f.trade == .floor && options.stage == nil)
      else { return false }
      if let sid = f.segmentID {
        if let unregistered { return sid == unregistered }
        return h.segments.first(where: { $0.id == sid })?.registration != nil
      }
      return unregistered == nil || h.isDemo
    }
  }
  static func geometry(_ mesh: Mesh, uv: [UV]? = nil) -> SCNGeometry {
    let points = mesh.vertices.map { SCNVector3($0.render) }
    let source = SCNGeometrySource(vertices: points)
    let data = mesh.triangles.withUnsafeBytes { Data($0) }
    let indices: Data =
      mesh.triangles.isEmpty
      ? (0..<mesh.vertices.count).map { Int32($0) }.withUnsafeBytes { Data($0) } : data
    let element = SCNGeometryElement(
      data: indices, primitiveType: mesh.triangles.isEmpty ? .point : .triangles,
      primitiveCount: mesh.triangles.isEmpty ? mesh.vertices.count : mesh.triangles.count / 3,
      bytesPerIndex: 4)
    element.pointSize = 3
    element.minimumPointScreenSpaceRadius = 1
    element.maximumPointScreenSpaceRadius = 5
    var sources = [source]
    if let uv, uv.count == mesh.vertices.count {
      sources.append(
        SCNGeometrySource(textureCoordinates: uv.map { CGPoint(x: $0.u, y: 1 - $0.v) }))
    }
    return SCNGeometry(sources: sources, elements: [element])
  }
  static func scene(_ h: House, options: SceneOptions) -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = UIColor(red: 0.035, green: 0.055, blue: 0.08, alpha: 1)
    scene.lightingEnvironment.intensity = 0.8
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 650
    scene.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 1100
    sun.eulerAngles = SCNVector3(-0.7, -0.5, 0)
    scene.rootNode.addChildNode(sun)
    // Unregistered sessions have independent frames; never silently overlay them.
    var textureCache: [String: UIImage] = [:]
    for f in features(h, options: options) {
      var mesh = f.mesh
      if let sid = f.segmentID, let t = h.segments.first(where: { $0.id == sid })?.registration {
        mesh.vertices = mesh.vertices.map { t.apply($0) }
      }
      let n = SCNNode(geometry: geometry(mesh, uv: f.uv))
      n.name = f.id.uuidString
      let m = SCNMaterial()
      m.lightingModel = .physicallyBased
      m.diffuse.contents = UIColor(rgb: f.trade.hex)
      m.roughness.contents = 0.8
      m.isDoubleSided = true
      if options.mode == .ghost && (f.trade == .finish || f.trade == .ceiling) {
        m.transparency = 0.17
        m.writesToDepthBuffer = false
      }
      if let key = f.texture {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
          0
        ].appendingPathComponent("HouseXray/assets")
        if textureCache[key] == nil,
          let source = CGImageSourceCreateWithURL(root.appendingPathComponent(key) as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1024,
            ] as CFDictionary)
        {
          textureCache[key] = UIImage(cgImage: cg)
        }
        if let image = textureCache[key] { m.diffuse.contents = image }
      }
      n.geometry?.materials = [m]
      scene.rootNode.addChildNode(n)
    }
    return scene
  }
  static func camera(at p: V3, yaw: Double = 0, pitch: Double = 0) -> SCNNode {
    let n = SCNNode()
    n.camera = SCNCamera()
    n.camera?.zNear = 0.03
    n.camera?.zFar = 150
    n.camera?.fieldOfView = 65
    n.simdPosition = p.render
    n.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
    return n
  }
}
extension UIColor {
  convenience init(rgb: UInt32) {
    self.init(
      red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
      blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
}

@MainActor final class WalkController: NSObject, ObservableObject {
  let view = SCNView(
    frame: .zero,
    options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
  @Published var selection: UUID?
  @Published var points: [V3] = []
  var pointRoomID: UUID?
  @Published var tool = "Inspect"
  @Published var flying = false
  @Published var orbit = false
  private var clearance = SpatialClearance(features: [])
  @Published var navigationNotice = ""
  var house: House?
  var options = SceneOptions()
  var revision = -1
  var move = SIMD2<Float>.zero
  var vertical: Float = 0
  var yaw: Float = 0
  var pitch: Float = 0
  private var timer: CADisplayLink?
  private var lastTime: CFTimeInterval = 0
  private var panStart = CGPoint.zero
  private var hadController = false
  var camera = SceneBuilder.camera(at: V3(3, 2, 1.6))
  override init() {
    super.init()
    view.backgroundColor = .black
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 30
    view.isPlaying = true
    view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
  }
  func start() {
    guard timer == nil else { return }
    let t = CADisplayLink(target: self, selector: #selector(tick(_:)))
    t.add(to: .main, forMode: .common)
    timer = t
  }
  func stop() {
    timer?.invalidate()
    timer = nil
    move = .zero
    vertical = 0
    lastTime = 0
  }
  func load(_ h: House, _ o: SceneOptions) {
    guard revision != h.revision || house?.id != h.id || options != o else { return }
    let oldFrame = house.flatMap { SceneBuilder.activeUnregisteredSegment($0, options: options) }
    let fresh =
      house?.id != h.id || oldFrame != SceneBuilder.activeUnregisteredSegment(h, options: o)
    points = []
    selection = nil
    house = h
    options = o
    revision = h.revision
    clearance = SpatialClearance(features: Exporter.canonicalFeatures(h, options: o))
    navigationNotice = clearance.complete ? "" : "Walk collision budget exceeded. Choose one room or use Free fly."
    let scene = SceneBuilder.scene(h, options: o)
    scene.rootNode.addChildNode(camera)
    view.scene = scene
    view.pointOfView = camera
    if fresh, let room = h.rooms.first(where: { $0.id == o.room }) ?? h.rooms.first {
      jump(room)
      if !h.isDemo, h.observations.isEmpty {
        let vertices = Exporter.canonicalFeatures(h, options: o).flatMap { $0.mesh.vertices }
        if !vertices.isEmpty {
          let low = V3(
            vertices.map { $0.x }.min()!, vertices.map { $0.y }.min()!, vertices.map { $0.z }.min()!
          )
          let high = V3(
            vertices.map { $0.x }.max()!, vertices.map { $0.y }.max()!, vertices.map { $0.z }.max()!
          )
          let center = (low + high) * 0.5
          let radius = max(2, (high - low).length)
          camera.simdPosition = (center + V3(0, -radius, radius * 0.35)).render
          camera.look(at: SCNVector3(center.render))
          yaw = camera.eulerAngles.y
          pitch = camera.eulerAngles.x
          flying = true
        }
      }
    }
  }
  func jump(_ room: Room) {
    var p = room.origin + V3(room.size.x / 2, room.size.y / 2, 1.6)
    var direction = V3(0.55, 1, -0.08)
    if let h = house,
      let observation = h.observations.last(where: {
        $0.roomID == room.id
          && SceneBuilder.eligibleStages(h, options: options).contains($0.stageID)
          && (SceneBuilder.activeUnregisteredSegment(h, options: options) == nil
            || $0.segmentID == SceneBuilder.activeUnregisteredSegment(h, options: options))
          && !$0.documentary
      })
    {
      let m = observation.camera
      p = V3(m[3], -m[11], m[7])
      direction = V3(-m[2], m[10], -m[6])
      if let t = h.segments.first(where: { $0.id == observation.segmentID })?.registration {
        p = t.apply(p)
        direction = t.apply(direction) - t.apply(V3())
      }
    }
    camera.simdPosition = p.render
    yaw = Float(atan2(-direction.x, direction.y))
    pitch = Float(asin(max(-1, min(1, direction.normalized.z))))
    camera.eulerAngles = SCNVector3(pitch, yaw, 0)
    move = .zero
  }
  func bookmark(_ b: Bookmark) {
    camera.simdPosition = b.position.render
    yaw = Float(b.yaw)
    pitch = Float(b.pitch)
    camera.eulerAngles = SCNVector3(pitch, yaw, 0)
  }
  @objc func pan(_ g: UIPanGestureRecognizer) {
    guard !orbit else { return }
    let p = g.translation(in: view)
    if g.state == .began { panStart = p }
    yaw -= Float(p.x - panStart.x) * 0.004
    pitch = max(-1.35, min(1.35, pitch - Float(p.y - panStart.y) * 0.004))
    panStart = p
    camera.eulerAngles = SCNVector3(pitch, yaw, 0)
  }
  @objc func tap(_ g: UITapGestureRecognizer) {
    let p = g.location(in: view)
    guard
      let hit = view.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first
    else { return }
    selection = hit.node.name.flatMap(UUID.init(uuidString:))
    let v = V3(ar: SIMD3(hit.worldCoordinates.x, hit.worldCoordinates.y, hit.worldCoordinates.z))
    if tool != "Inspect" {
      if points.isEmpty {
        pointRoomID = house?.features.first(where: { $0.id == selection })?.roomID
      }
      if tool == "Measure" && points.count >= 2 { points = [] }
      points.append(v)
      drawPoints()
    }
  }
  func clear() {
    points = []
    pointRoomID = nil
    drawPoints()
  }
  func drawPoints() {
    view.scene?.rootNode.childNode(withName: "selection-points", recursively: false)?
      .removeFromParentNode()
    let group = SCNNode()
    group.name = "selection-points"
    for p in points {
      let n = SCNNode(geometry: SCNSphere(radius: 0.025))
      n.geometry?.firstMaterial?.diffuse.contents = UIColor.white
      n.simdPosition = p.render
      group.addChildNode(n)
    }
    view.scene?.rootNode.addChildNode(group)
  }
  @objc func tick(_ link: CADisplayLink) {
    let dt = Float(lastTime == 0 ? 0 : min(0.05, link.timestamp - lastTime))
    lastTime = link.timestamp
    if let pad = GCController.current?.extendedGamepad {
      hadController = true
      move = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
      yaw -= pad.rightThumbstick.xAxis.value * dt * 1.8
      pitch = max(-1.35, min(1.35, pitch + pad.rightThumbstick.yAxis.value * dt * 1.2))
      camera.eulerAngles = SCNVector3(pitch, yaw, 0)
    } else if hadController {
      move = .zero
      hadController = false
    }
    guard !orbit else { return }
    let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    let delta = (forward * move.y + right * move.x + SIMD3(0, vertical, 0)) * dt * 1.3
    guard simd_length(delta) > 0 else { return }
    let from = camera.simdPosition
    let to = from + delta
    if flying {
      camera.simdPosition = to
      return
    }
    let direction = simd_normalize(delta)
    let ahead = to + direction * 0.23
    if clearance.isClear(from: V3(ar: from), to: V3(ar: ahead), radius: 0.15) {
      if let h = house {
        if h.isDemo && h.observations.isEmpty {
          guard NavigationGeometry.allowed(V3(ar: to), house: h) else { return }
        } else {
          guard NavigationGeometry.observed(V3(ar: to), house: h, options: options) else { return }
        }
      }
      camera.simdPosition = to
    }
  }
}
struct WalkSurface: UIViewRepresentable {
  @ObservedObject var controller: WalkController
  var house: House
  var options: SceneOptions
  func makeUIView(context: Context) -> SCNView {
    controller.load(house, options)
    controller.start()
    return controller.view
  }
  func updateUIView(_ uiView: SCNView, context: Context) {
    controller.load(house, options)
    uiView.allowsCameraControl = controller.orbit
  }
  static func dismantleUIView(_ uiView: SCNView, coordinator: ()) { uiView.isPlaying = false }
}
struct Joystick: View {
  var action: (SIMD2<Float>) -> Void
  @State private var offset = CGSize.zero
  var body: some View {
    Circle().fill(.black.opacity(0.5)).overlay(Circle().stroke(.white.opacity(0.3))).frame(
      width: 112, height: 112
    ).overlay(Circle().fill(.white.opacity(0.7)).frame(width: 42, height: 42).offset(offset))
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { v in
          let x = max(-35, min(35, v.translation.width))
          let y = max(-35, min(35, v.translation.height))
          offset = CGSize(width: x, height: y)
          action(SIMD2(Float(x / 35), Float(-y / 35)))
        }.onEnded { _ in
          offset = .zero
          action(.zero)
        }
      ).accessibilityLabel("Move joystick").accessibilityHint(
        "Drag to walk. Drag the scene to look.")
  }
}

enum NavigationGeometry {
  static func observed(_ p: V3, house: House, options: SceneOptions) -> Bool {
    let stages = SceneBuilder.eligibleStages(house, options: options)
    let active = SceneBuilder.activeUnregisteredSegment(house, options: options)
    return house.observations.contains { o in
      guard !o.documentary, stages.contains(o.stageID),
        options.room == nil || options.room == o.roomID, active == nil || active == o.segmentID
      else { return false }
      let m = o.camera
      var q = V3(m[3], -m[11], m[7])
      if let t = house.segments.first(where: { $0.id == o.segmentID })?.registration {
        q = t.apply(q)
      }
      return abs(p.z - q.z) < 0.4 && hypot(p.x - q.x, p.y - q.y) < 0.65
    }
  }
  static func allowed(_ p: V3, house: House) -> Bool {
    let rooms = house.rooms.filter { abs(($0.origin.z + 1.6) - p.z) < 0.5 }
    for r in rooms {
      let q = p - r.origin
      if q.x >= 0.2 && q.x <= r.size.x - 0.2 && q.y >= 0.2 && q.y <= r.size.y - 0.2 { return true }
    }
    // Only geometrically adjacent doorways form a connection; floors never do.
    for a in rooms {
      for b in rooms where a.id != b.id {
        let left = a.origin.x + a.size.x
        let right = b.origin.x
        if right - left >= 0 && right - left < 0.5 && abs(a.origin.y - b.origin.y) < 0.01
          && p.x >= left - 0.3 && p.x <= right + 0.3 && p.y >= a.origin.y + 1.95
          && p.y <= a.origin.y + 2.55
        {
          return true
        }
      }
    }
    return false
  }
}
