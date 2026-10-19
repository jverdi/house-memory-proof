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
    case .rough: return f.trade != .finish
    case .finished:
      return f.trade == .finish || f.trade == .ceiling || f.trade == .floor || f.trade == .unknown
    case .ghost, .evidence: return true
    }
  }
  static func eligibleStages(_ h: House, options: SceneOptions) -> Set<UUID> {
    if let stage = options.stage { return [stage] }
    let finished = Set(h.stages.filter { $0.category == .finished }.map { $0.id })
    switch options.mode {
    case .rough: return Set(h.stages.filter{$0.category == .rough}.map{$0.id})
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
  static func features(_ h: House, options: SceneOptions,includeHiddenLayers:Bool=false) -> [Feature] {
    let stages = eligibleStages(h, options: options)
    let unregistered = activeUnregisteredSegment(h, options: options)
    let current=DerivedEvidence.currentIDs(h)
    return h.features.filter { f in
      let admitted=includeHiddenLayers ? (f.artifactValid != false && (options.room==nil || options.room==f.roomID)):visible(f,options)
      guard current.contains(f.id),admitted,
        stages.contains(f.stageID) || (f.trade == .floor && options.stage == nil)
      else { return false }
      if let sid = f.segmentID {
        if let unregistered { return sid == unregistered }
        return h.segments.first(where: { $0.id == sid })?.registration != nil
      }
      return unregistered == nil || h.isDemo
    }
  }
  static func geometry(_ mesh: Mesh, uv: [UV]? = nil, connectedLine:Bool=false) -> SCNGeometry {
    let points = mesh.vertices.map { SCNVector3($0.render) }
    let source = SCNGeometrySource(vertices: points)
    let data = mesh.triangles.withUnsafeBytes { Data($0) }
    let line=connectedLine && mesh.triangles.isEmpty && mesh.vertices.count>=2
    let indices: Data = line
      ? (1..<mesh.vertices.count).flatMap{[Int32($0-1),Int32($0)]}.withUnsafeBytes{Data($0)}
      : mesh.triangles.isEmpty
      ? (0..<mesh.vertices.count).map { Int32($0) }.withUnsafeBytes { Data($0) } : data
    let element = SCNGeometryElement(
      data: indices, primitiveType: line ? .line:mesh.triangles.isEmpty ? .point : .triangles,
      primitiveCount: line ? mesh.vertices.count-1:mesh.triangles.isEmpty ? mesh.vertices.count : mesh.triangles.count / 3,
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
  static func baseScene() -> SCNScene {
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
    return scene
  }
  static func scene(_ h: House, options: SceneOptions,assetRoot:URL?=nil) -> SCNScene {
    let scene=baseScene()
    // Unregistered sessions have independent frames; never silently overlay them.
    var textureCache: [String: UIImage] = [:]
    let visibleFeatures=features(h,options:options)
    let total=visibleFeatures.reduce(0){$0+DisplayGeometry.cost($1.mesh)}
    for f in visibleFeatures {
      let reduced=DisplayGeometry.reduce(f.mesh,uv:f.uv,budget:DisplayGeometry.budget(for:f.mesh,total:total,objects:visibleFeatures.count))
      var mesh = reduced.0
      if let sid = f.segmentID, let t = h.segments.first(where: { $0.id == sid })?.registration {
        mesh.vertices = mesh.vertices.map { t.apply($0) }
      }
      let n=node(f,mesh:mesh,uv:reduced.1,options:options,textures:&textureCache,assetRoot:assetRoot)
      scene.rootNode.addChildNode(n)
    }
    return scene
  }
  static func node(_ f:Feature,mesh:Mesh,uv:[UV]?,options:SceneOptions,textures:inout [String:UIImage],textured:Bool=true,assetRoot:URL?=nil)->SCNNode {
      // Reduced point previews must not connect skipped samples across gaps.
      let line=f.isPhotoCurve && mesh.vertices.count==f.mesh.vertices.count
      let n = SCNNode(geometry: geometry(mesh, uv: uv,connectedLine:line))
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
      if textured,let key = f.texture {
        let root = assetRoot ?? Repository.defaultRoot.appendingPathComponent("assets")
        if textures[key] == nil,textures.count<DisplayGeometry.textureBudget,
          let source = CGImageSourceCreateWithURL(root.appendingPathComponent(key) as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 768,
            ] as CFDictionary)
        {
          let used=decodedTextureBytes(textures)
          let (bytes,overflow)=cg.bytesPerRow.multipliedReportingOverflow(by:cg.height)
          if !overflow,bytes<=DisplayGeometry.textureByteBudget-used { textures[key] = UIImage(cgImage: cg) }
        }
        if let image = textures[key] { m.diffuse.contents = image }
      }
      n.geometry?.materials = [m]
      return n
  }
  static func decodedTextureBytes(_ textures:[String:UIImage])->Int {
    textures.values.reduce(0) {total,image in
      guard let cg=image.cgImage else{return total}
      return total+cg.bytesPerRow*cg.height
    }
  }
  static func camera(at p: V3, yaw: Double = 0, pitch: Double = 0) -> SCNNode {
    let n = SCNNode()
    n.camera = SCNCamera()
    n.camera?.zNear = 0.03
    n.camera?.zFar = 150
    n.camera?.projectionDirection = .vertical
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

@MainActor final class SpatialSceneStream {
  let index:SpatialDisplayIndex
  let scene:SCNScene
  let options:SceneOptions
  var nodes:[Int:SCNNode]=[:]
  var allocations:[Int:SpatialDisplayIndex.Allocation]=[:]
  var pending:[SpatialDisplayIndex.Allocation]=[]
  var textures:[String:UIImage]=[:]
  var lastCamera:V3?
  var lastUpdate=0.0
  private var lastPlan:[SpatialDisplayIndex.Allocation]=[]
  init(index:SpatialDisplayIndex,scene:SCNScene,options:SceneOptions){self.index=index;self.scene=scene;self.options=options}
  func update(camera:V3,time:Double) {
    if lastCamera==nil || (time-lastUpdate>=0.5 && (camera-lastCamera!).length>=1) {
      lastCamera=camera;lastUpdate=time
      let plan=index.plan(camera:camera,previous:lastPlan),needed=Set(plan.map{$0.tile})
      lastPlan=plan
      for id in Array(nodes.keys) where !needed.contains(id) {nodes.removeValue(forKey:id)?.removeFromParentNode();allocations.removeValue(forKey:id)}
      let textureKeys=Set(plan.filter{$0.textured}.compactMap{index.features[index.tiles[$0.tile].feature].texture})
      textures=textures.filter{textureKeys.contains($0.key)}
      pending=plan.filter{allocations[$0.tile] != $0}
      // Remove superseded GPU geometry before replacements allocate memory.
      for next in pending {nodes.removeValue(forKey:next.tile)?.removeFromParentNode();allocations.removeValue(forKey:next.tile)}
    }
    guard !pending.isEmpty else{return}
    let next=pending.removeFirst(),(feature,mesh,uv)=index.materialize(next)
    let node=SceneBuilder.node(feature,mesh:mesh,uv:uv,options:options,textures:&textures,textured:next.textured)
    scene.rootNode.addChildNode(node);nodes[next.tile]=node;allocations[next.tile]=next
  }
}

@MainActor final class WalkController: NSObject, ObservableObject {
  let view = SCNView(
    frame: .zero,
    options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
  @Published var selection: UUID?
  @Published var points: [V3] = []
  var pointRoomID: UUID?
  var pointFeatureIDs:[UUID]=[]
  @Published var tool = "Inspect"
  @Published var flying = false
  @Published var orbit = false
  private var clearance = SpatialClearance(features: [])
  private var stream:SpatialSceneStream?
  private var navigationIndex:SpatialDisplayIndex?
  private var collisionTask:Task<Void,Never>?
  private var collisionRequest=UUID()
  private var collisionTarget:V3?
  private var pendingWalkingLocation=false
  private var sceneTask:Task<Void,Never>?
  private var sceneRequest=UUID()
  private var resumeScene=false
  private var preparingScene=false
  var isPreparingNavigation:Bool {preparingScene || pendingWalkingLocation}
  private var cameraCorridor: [V3] = []
  private var recordedPaths:[NavigationGeometry.PathEdge]=[]
  private var walkEyeHeight:Double?
  // Low-level callers may retain captured height. The app supplies its saved
  // viewer preferences before loading a house, including the 1.7 m default.
  private var comfort:ViewerComfort?
  private(set) var motionVelocity=SIMD3<Float>.zero
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
  private var panTime:CFTimeInterval=0
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
    view.isPlaying=true
    if resumeScene,let h=house {resumeScene=false;revision = -1;load(h,options)}
    guard timer == nil else { return }
    let t = CADisplayLink(target: self, selector: #selector(tick(_:)))
    t.add(to: .main, forMode: .common)
    timer = t
  }
  func applyComfort(_ value:ViewerComfort) {
    let next=value.bounded
    guard comfort != next else{return}
    let changedHeight=comfort?.eyeHeight != next.eyeHeight
    comfort=next;camera.camera?.fieldOfView=CGFloat(next.fieldOfView)
    view.pointOfView?.camera?.fieldOfView=CGFloat(next.fieldOfView)
    clearMovement()
    if changedHeight {walkEyeHeight=nil;validateWalkPosition()}
  }
  private func clearMovement() {
    move = .zero;vertical=0;motionVelocity = .zero
  }
  func stop() {
    view.isPlaying=false
    timer?.invalidate()
    timer = nil
    clearMovement()
    lastTime = 0
    collisionTask?.cancel();collisionTask=nil;collisionRequest=UUID();collisionTarget=nil
    if sceneTask != nil {resumeScene=true}
    sceneTask?.cancel();sceneTask=nil;sceneRequest=UUID()
  }
  func setOrbit(_ enabled:Bool) {
    clearMovement();orbit=enabled
    view.allowsCameraControl=enabled
    if !enabled {view.pointOfView=camera;validateWalkPosition()}
  }
  func setFlying(_ enabled:Bool) {
    clearMovement();flying=enabled
    if enabled {pendingWalkingLocation=false}
    if !enabled {validateWalkPosition()}
  }
  func load(_ h: House, _ o: SceneOptions) {
    guard revision != h.revision || house?.id != h.id || options != o else { return }
    let oldFrame = house.flatMap { SceneBuilder.activeUnregisteredSegment($0, options: options) }
    let fresh =
      house?.id != h.id || oldFrame != SceneBuilder.activeUnregisteredSegment(h, options: o)
    points = []
    pointFeatureIDs=[]
    selection = nil
    house = h
    options = o
    revision = h.revision
    walkEyeHeight=nil;clearMovement()
    collisionTask?.cancel();collisionTask=nil;collisionRequest=UUID();collisionTarget=nil;pendingWalkingLocation=false
    sceneTask?.cancel();sceneTask=nil;sceneRequest=UUID();resumeScene=false
    stream=nil;navigationIndex=nil
    cameraCorridor = NavigationGeometry.positions(house:h,options:o)
    recordedPaths=NavigationGeometry.paths(house:h,options:o)
    let large=h.features.reduce(0){$0+DisplayGeometry.cost($1.mesh)}>DisplayGeometry.sceneVertexBudget || h.features.count>512
    let scene=large ? SceneBuilder.baseScene():SceneBuilder.scene(h,options:o)
    scene.rootNode.addChildNode(camera);view.scene=scene
    preparingScene=large
    if large {
      navigationNotice="Preparing nearby house detail…"
      let request=sceneRequest
      sceneTask=Task {
        defer {if self.sceneRequest==request {self.sceneTask=nil}}
        do {
          let position=V3(ar:self.camera.simdPosition)
          let prepared=try await LocalWorker.run { () throws -> (SpatialDisplayIndex,SpatialDisplayIndex,SpatialClearance) in
            let canonical=Exporter.canonicalFeatures(h,options:o)
            let index=try SpatialDisplayIndex(features:canonical)
            let navigation=try SpatialDisplayIndex(features:NavigationGeometry.collisionFeatures(h,options:o))
            return(index,navigation,try SpatialClearance(index:navigation,camera:position))
          }
          guard !Task.isCancelled,self.sceneRequest==request,self.house?.id==h.id,self.revision==h.revision,self.options==o,self.view.scene===scene else{return}
          self.navigationIndex=prepared.1;self.clearance=prepared.2;self.stream=SpatialSceneStream(index:prepared.0,scene:scene,options:o);self.preparingScene=false
          self.navigationNotice=prepared.2.complete ? "Dense or distant surfaces may appear as source points. Select a room for more detail. Measurements and exports use originals.":"Nearby collision detail exceeds the budget. Select a room or use Free fly."
          self.validateWalkPosition()
        }catch is CancellationError {}catch {
          guard self.sceneRequest==request,self.view.scene===scene else{return}
          self.navigationNotice=error.localizedDescription
        }
      }
    } else {
      clearance=SpatialClearance(features:NavigationGeometry.collisionFeatures(h,options:o))
      navigationNotice=clearance.complete ? "":"Walk collision budget exceeded. Choose one room or use Free fly."
    }
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
    validateWalkPosition()
  }
  private func validateWalkPosition() {
    guard !flying,!orbit,!preparingScene,let h=house else{return}
    let current=V3(ar:camera.simdPosition)
    if let target=collisionTarget,(current-target).length>=1 {
      collisionTask?.cancel();collisionTask=nil;collisionRequest=UUID();collisionTarget=nil
    }
    // A teleport can leave the resident collision window. Keep its requested
    // destination and pause movement while loading that location; looking for
    // a safe pose in the previous room would silently undo the room jump.
    if stream != nil,let centre=clearance.coverageCentre,(current-centre).length>=1 {
      pendingWalkingLocation=true;clearMovement()
      navigationNotice="Checking this viewpoint's floor and route…"
      updateCollision(at:current,replace:true)
      return
    }
    pendingWalkingLocation=false
    func usable(_ point:V3)->V3? {
      let adjusted:V3?
      if let comfort {adjusted=clearance.standingPosition(from:point,eyeHeight:comfort.eyeHeight)}
      else {adjusted=clearance.walkingDestination(from:point,toward:point)?.position}
      guard let adjusted,withinWalkingRecord(adjusted,house:h) else{return nil}
      return adjusted
    }
    if let adjusted=usable(current) {
      camera.simdPosition=adjusted.render;walkEyeHeight=comfort?.eyeHeight
      if navigationNotice.hasPrefix("No checked walking viewpoint") {navigationNotice=""}
      return
    }
    let candidates=h.isDemo && h.observations.isEmpty ? h.rooms.filter{options.room==nil || $0.id==options.room}.map{$0.origin+V3($0.size.x/2,$0.size.y/2,1.6)}:cameraCorridor
    if let safe=candidates.sorted(by:{($0-current).length<($1-current).length}).lazy.compactMap(usable).first {
      camera.simdPosition=safe.render;walkEyeHeight=comfort?.eyeHeight;clearMovement()
      navigationNotice="Moved to a checked viewpoint for this stage."
    } else {
      flying=true;clearMovement()
      navigationNotice="No checked walking viewpoint is available here. Free fly is enabled. Walking needs a captured floor and a clear route."
    }
  }
  private func withinWalkingRecord(_ point:V3,house:House)->Bool {
    guard comfort != nil else {
      return house.isDemo && house.observations.isEmpty ? NavigationGeometry.allowed(point,house:house):NavigationGeometry.observed(point,positions:cameraCorridor)
    }
    guard let floor=clearance.walkingFloorHeight(at:point) else{return false}
    if house.isDemo && house.observations.isEmpty {
      return NavigationGeometry.allowed(V3(point.x,point.y,floor+1.6),house:house)
    }
    // Compare floor levels, not phone-holding heights. The original horizontal
    // corridor and level tolerance stay bounded; stacked floors cannot connect.
    return cameraCorridor.contains { recorded in
      guard hypot(point.x-recorded.x,point.y-recorded.y)<0.65,
        let recordedFloor=clearance.walkingFloorHeight(at:recorded) else{return false}
      return abs(floor-recordedFloor)<0.4
    }
  }
  func resetView() {
    guard let h=house,let room=h.rooms.first(where:{$0.id==options.room}) ?? h.rooms.first else{return}
    setOrbit(false);flying=false;jump(room);validateWalkPosition()
  }
  private func updateCollision(at position:V3,replace:Bool=false) {
    guard let stream,let index=navigationIndex,
      clearance.coverageCentre.map({(position-$0).length>=1}) ?? true else{return}
    if replace {
      if collisionTask != nil,let target=collisionTarget,(target-position).length<0.25 {return}
      collisionTask?.cancel();collisionTask=nil
    }else if collisionTask != nil {return}
    let request=UUID();collisionRequest=request
    collisionTarget=position
    collisionTask=Task {
      defer {if self.collisionRequest==request {self.collisionTask=nil;self.collisionTarget=nil}}
      do {
        let next=try await LocalWorker.run {try SpatialClearance(index:index,camera:position)}
        guard !Task.isCancelled,self.collisionRequest==request,self.stream===stream else{return}
        self.clearance=next
        self.navigationNotice=next.complete ? "Dense or distant surfaces may appear as source points. Select a room for more detail. Measurements and exports use originals.":"Nearby collision detail exceeds the budget. Select a room or use Free fly."
        if self.pendingWalkingLocation {self.pendingWalkingLocation=false;self.validateWalkPosition()}
      }catch is CancellationError {}catch {
        guard self.collisionRequest==request else{return}
        if self.pendingWalkingLocation {
          self.pendingWalkingLocation=false;self.flying=true;self.clearMovement()
          self.navigationNotice="This viewpoint's floor and route could not be checked. Free fly is enabled. Choose a room or saved viewpoint to try again."
        }else {self.navigationNotice="Nearby collision preparation failed. Walking remains limited to the last checked area."}
      }
    }
  }
  func jump(_ room: Room) {
    walkEyeHeight=nil;clearMovement()
    var p = room.origin + V3(room.size.x / 2, room.size.y / 2, 1.6)
    var direction = V3(0.55, 1, -0.08)
    if let h = house,
      let observation = PoseRefinement.selectedForHouse(h).last(where: {
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
    validateWalkPosition()
  }
  func bookmark(_ b: Bookmark) {
    walkEyeHeight=nil;clearMovement()
    guard let h=house else{return}
    // Archive validation rejects nonfinite values, but finite Double values
    // can still overflow SceneKit's Float camera or belong to another frame.
    guard b.position.finite,max(abs(b.position.x),abs(b.position.y),abs(b.position.z))<=100000,
      b.yaw.isFinite,b.pitch.isFinite,h.rooms.contains(where:{$0.id==b.roomID}),
      options.room==nil || options.room==b.roomID,
      b.segmentID==SceneBuilder.activeUnregisteredSegment(h,options:options) else {
      resetView()
      navigationNotice="That saved viewpoint cannot be used in this view. "+(preparingScene ? "Checking the room's floor and route…":flying ? "No checked walking viewpoint is available; Free fly is enabled.":"Returned to a checked viewpoint.")
      return
    }
    if navigationNotice.hasPrefix("That saved viewpoint cannot be used") {navigationNotice=""}
    setOrbit(false)
    camera.simdPosition = b.position.render
    yaw = Float(b.yaw.truncatingRemainder(dividingBy:2 * .pi))
    pitch = Float(max(-1.35,min(1.35,b.pitch)))
    camera.eulerAngles = SCNVector3(pitch, yaw, 0)
    validateWalkPosition()
  }
  @objc func pan(_ g: UIPanGestureRecognizer) {
    guard !orbit else { return }
    let p = g.translation(in: view)
    let now=CACurrentMediaTime()
    if g.state == .began {panStart=p;panTime=now;return}
    dragLook(dx:Float(p.x-panStart.x),dy:Float(p.y-panStart.y),seconds:Float(now-panTime))
    panStart=p;panTime=now
  }
  func dragLook(dx:Float,dy:Float,seconds:Float) {
    guard !orbit,dx.isFinite,dy.isFinite,seconds.isFinite,seconds>0 else{return}
    let settings=comfort ?? ViewerComfort(),limit=Float(settings.turnDegreesPerSecond * .pi/180)*min(0.05,seconds)
    let scale=Float(settings.sensitivity)*0.004,verticalSign:Float=settings.invertY ? 1:-1
    let requested=SIMD2(-dx*scale,dy*scale*verticalSign)
    let bounded=requested*min(1,limit/max(0.000001,simd_length(requested)))
    yaw+=bounded.x;pitch=max(-1.35,min(1.35,pitch+bounded.y))
    camera.eulerAngles=SCNVector3(pitch,yaw,0)
  }
  @objc func tap(_ g: UITapGestureRecognizer) {
    let p = g.location(in: view)
    guard
      let hit = view.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first
    else { return }
    selection = hit.node.name.flatMap(UUID.init(uuidString:))
    let v = V3(ar: SIMD3(hit.worldCoordinates.x, hit.worldCoordinates.y, hit.worldCoordinates.z))
    if tool != "Inspect" {
      guard selection != nil else{return}
      if (tool == "Measure" && points.count >= 2) || (tool == "Boundary" && points.count >= 3) {points=[];pointFeatureIDs=[]}
      if points.isEmpty {pointRoomID=house?.features.first(where:{$0.id==selection})?.roomID;pointFeatureIDs=[]}
      if let selection,!pointFeatureIDs.contains(selection),pointFeatureIDs.count<64 {pointFeatureIDs.append(selection)}
      points.append(v)
      drawPoints()
    }
  }
  func clear() {
    points = []
    pointRoomID = nil
    pointFeatureIDs=[]
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
    let dt = Float(lastTime == 0 ? 0 : max(0,min(0.05,link.timestamp-lastTime)))
    lastTime = link.timestamp
    var look=SIMD2<Float>.zero
    if let pad = GCController.current?.extendedGamepad {
      hadController = true
      move = SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value)
      look=SIMD2(pad.rightThumbstick.xAxis.value,pad.rightThumbstick.yAxis.value)
    } else if hadController {
      clearMovement()
      hadController = false
    }
    let displayed=view.pointOfView?.presentation.simdWorldPosition ?? camera.simdPosition
    stream?.update(camera:V3(ar:displayed),time:link.timestamp)
    updateCollision(at:V3(ar:camera.simdPosition))
    advance(seconds:dt,look:look)
  }
  // Shared by the display link and native diagnostics. Frame stalls cannot
  // create long jumps; diagonal input cannot exceed the selected speed.
  func advance(seconds:Float,look:SIMD2<Float> = .zero) {
    guard !orbit,!preparingScene,seconds.isFinite,seconds>0 else{motionVelocity = .zero;return}
    let dt=min(0.05,seconds),settings=comfort ?? ViewerComfort()
    if look.x.isFinite,look.y.isFinite {
      let bounded=look/max(1,simd_length(look)),rate=Float(settings.turnDegreesPerSecond * .pi/180)
      yaw-=bounded.x*rate*dt
      pitch=max(-1.35,min(1.35,pitch+bounded.y*rate*dt*(settings.invertY ? -1:1)))
      camera.eulerAngles=SCNVector3(pitch,yaw,0)
    }
    guard move.x.isFinite,move.y.isFinite,vertical.isFinite else{clearMovement();return}
    let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    let raw=forward*max(-1,min(1,move.y))+right*max(-1,min(1,move.x))+SIMD3(0,flying ? max(-1,min(1,vertical)):0,0)
    guard simd_length(raw)>0.001 else{motionVelocity = .zero;return}
    let target=raw/max(1,simd_length(raw))*Float(settings.speed)
    if simd_dot(motionVelocity,target)<=0 {motionVelocity = .zero}
    let difference=target-motionVelocity,change=Float(settings.acceleration)*dt
    motionVelocity+=difference*min(1,change/max(0.000001,simd_length(difference)))
    let before=camera.simdPosition
    attemptMove(motionVelocity*dt)
    if simd_length(camera.simdPosition-before)<0.000001 {motionVelocity = .zero}
  }
  func stepMove(_ input: SIMD2<Float>) {
    clearMovement()
    guard input.x.isFinite,input.y.isFinite else{return}
    let bounded=input / max(1,simd_length(input))
    let forward=SIMD3<Float>(-sin(yaw),0,-cos(yaw)),right=SIMD3<Float>(cos(yaw),0,-sin(yaw))
    attemptMove((forward * bounded.y + right * bounded.x) * 0.2)
  }
  func stepLook(yaw deltaYaw:Float=0,pitch deltaPitch:Float=0) {
    guard !orbit,deltaYaw.isFinite,deltaPitch.isFinite else{return}
    clearMovement()
    yaw += max(-Float.pi/4,min(Float.pi/4,deltaYaw))
    pitch=max(-1.35,min(1.35,pitch+max(-Float.pi/4,min(Float.pi/4,deltaPitch))))
    camera.eulerAngles=SCNVector3(pitch,yaw,0)
  }
  private func attemptMove(_ delta:SIMD3<Float>) {
    guard !orbit,!isPreparingNavigation,house != nil,delta.x.isFinite,delta.y.isFinite,delta.z.isFinite,simd_length(delta)>0 else{return}
    let from = camera.simdPosition
    var to = from + delta
    if flying {
      walkEyeHeight=nil
      camera.simdPosition = to
      return
    }
    guard clearance.hasFloorSupport else{return}
    if comfort == nil,let adjusted=NavigationGeometry.followedHeight(from:V3(ar:from),to:V3(ar:to),paths:recordedPaths) {to=adjusted.render}
    if let destination=clearance.walkingDestination(from:V3(ar:from),toward:V3(ar:to),eyeHeight:walkEyeHeight) {
      to=destination.position.render
      if let h = house {
        guard withinWalkingRecord(V3(ar:to),house:h) else{return}
      }
      camera.simdPosition = to
      walkEyeHeight=destination.eyeHeight
    }
  }
}
struct WalkSurface: UIViewRepresentable {
  @ObservedObject var controller: WalkController
  var house: House
  var options: SceneOptions
  var comfort: ViewerComfort
  func makeUIView(context: Context) -> SCNView {
    controller.applyComfort(comfort)
    controller.load(house, options)
    controller.start()
    return controller.view
  }
  func updateUIView(_ uiView: SCNView, context: Context) {
    controller.applyComfort(comfort)
    controller.load(house, options)
    uiView.allowsCameraControl = controller.orbit
  }
  static func dismantleUIView(_ uiView: SCNView, coordinator: ()) { uiView.isPlaying = false }
}
struct Joystick: View {
  var action: (SIMD2<Float>) -> Void
  @State private var offset = CGSize.zero
  @GestureState private var dragging=false
  var body: some View {
    Circle().fill(.black.opacity(0.5)).overlay(Circle().stroke(.white.opacity(0.3))).frame(
      width: 112, height: 112
    ).overlay(Circle().fill(.white.opacity(0.7)).frame(width: 42, height: 42).offset(offset))
      .gesture(
        DragGesture(minimumDistance: 0).updating($dragging) { _,active,_ in active=true }.onChanged { v in
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
      // GestureState also resets when the system cancels a drag without
      // delivering onEnded (for example, an interruption or gesture takeover).
      .onChange(of:dragging) {_,active in if !active {offset = .zero;action(.zero)}}
      .onDisappear {offset = .zero;action(.zero)}
  }
}
struct StepMovementControls:View {
  @ObservedObject var controller:WalkController
  private func control(_ title:String,_ icon:String,_ action:@escaping ()->Void)->some View {
    Button(action:action) {Image(systemName:icon).frame(width:44,height:44).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:8))}
      .buttonStyle(.plain).accessibilityLabel(title)
  }
  var body:some View {
    VStack(spacing:4) {
      HStack(spacing:4) {
        control("Step left","arrow.left") {controller.stepMove(SIMD2(-1,0))}
        control("Step forward","arrow.up") {controller.stepMove(SIMD2(0,1))}
        control("Step backward","arrow.down") {controller.stepMove(SIMD2(0,-1))}
        control("Step right","arrow.right") {controller.stepMove(SIMD2(1,0))}
      }
      HStack(spacing:4) {
        control("Turn left 15 degrees","arrow.uturn.left") {controller.stepLook(yaw:Float.pi/12)}
        control("Look up 15 degrees","chevron.up") {controller.stepLook(pitch:Float.pi/12)}
        control("Look down 15 degrees","chevron.down") {controller.stepLook(pitch:-Float.pi/12)}
        control("Turn right 15 degrees","arrow.uturn.right") {controller.stepLook(yaw:-Float.pi/12)}
      }
    }.padding(4).background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12))
      .accessibilityElement(children:.contain).accessibilityLabel("Step navigation")
      .disabled(controller.orbit)
  }
}

enum NavigationGeometry {
  static func collisionFeatures(_ house:House,options:SceneOptions)->[Feature] {
    SceneBuilder.features(house,options:options,includeHiddenLayers:true).map { source in
      var feature=source
      if let sid=feature.segmentID,let transform=house.segments.first(where:{$0.id==sid})?.registration {
        feature.mesh.vertices=feature.mesh.vertices.map{transform.apply($0)}
      }
      return feature
    }
  }
  struct PathEdge {var a:V3;var b:V3}
  static func paths(house:House,options:SceneOptions)->[PathEdge] {
    let stages=SceneBuilder.eligibleStages(house,options:options),active=SceneBuilder.activeUnregisteredSegment(house,options:options)
    let observations=PoseRefinement.selectedForHouse(house).filter{stages.contains($0.stageID) && (options.room==nil || options.room==$0.roomID) && (active==nil || active==$0.segmentID)}
    let grouped=Dictionary(grouping:observations,by:{$0.segmentID});var result:[PathEdge]=[]
    for group in grouped.values {
      let sorted=group.sorted{$0.timestamp<$1.timestamp}
      for i in sorted.indices.dropFirst() {
        let a=sorted[i-1],b=sorted[i],p=TourDirector.pose(a,house:house).0,q=TourDirector.pose(b,house:house).0
        let horizontal=hypot(q.x-p.x,q.y-p.y)
        if b.timestamp-a.timestamp<=3 && (q-p).length<=1 && horizontal>=0.03 && abs(q.z-p.z)<=horizontal {result.append(PathEdge(a:p,b:q))}
      }
    };return result
  }
  static func followedHeight(from:V3,to:V3,paths:[PathEdge])->V3? {
    let step=hypot(to.x-from.x,to.y-from.y);guard step>0 else{return nil}
    var best:V3?,distance=Double.infinity
    for edge in paths {
      let d=edge.b-edge.a,denominator=d.x*d.x+d.y*d.y;guard denominator>1e-6 else{continue}
      let t=max(0,min(1,((to.x-edge.a.x)*d.x+(to.y-edge.a.y)*d.y)/denominator)),point=edge.a+d*t
      let separation=hypot(point.x-to.x,point.y-to.y)
      guard separation<0.35,abs(point.z-from.z)<0.4,separation<distance else{continue}
      // Only follow recorded gentle height changes, never an invented floor jump.
      best=V3(to.x,to.y,from.z+max(-step,min(step,point.z-from.z)));distance=separation
    };return best
  }
  static func positions(house:House,options:SceneOptions)->[V3] {
    let stages=SceneBuilder.eligibleStages(house,options:options)
    let active=SceneBuilder.activeUnregisteredSegment(house,options:options)
    return PoseRefinement.selectedForHouse(house).compactMap { o in
      guard stages.contains(o.stageID),options.room==nil || options.room==o.roomID,active==nil || active==o.segmentID else{return nil}
      return TourDirector.pose(o,house:house).0
    }
  }
  static func observed(_ p:V3,positions:[V3])->Bool {
    positions.contains{abs(p.z-$0.z)<0.4 && hypot(p.x-$0.x,p.y-$0.y)<0.65}
  }
  static func observed(_ p:V3,house:House,options:SceneOptions)->Bool {observed(p,positions:positions(house:house,options:options))}
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
