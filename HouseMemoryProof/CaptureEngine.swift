import ARKit
import AVFoundation
import ImageIO
import SceneKit
import SwiftUI
import Vision

@MainActor final class CaptureController: NSObject, ObservableObject, ARSessionDelegate {
  let view = ARSCNView(frame: .zero)
  @Published var running = false
  @Published var message = "Choose a room and stage, then start."
  @Published var count = 0
  @Published var tracking = "Not started"
  @Published var supported = ARWorldTrackingConfiguration.isSupported
  @Published var hasDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
  @Published var processing = false
  @Published var coverageCells = 0
  private var cellSet = Set<String>()
  private var model: AppModel?
  private var houseID: UUID?
  private var segment: Segment?
  private var lastFrameTime: TimeInterval = 0
  private var lastPosition = SIMD3<Float>(repeating: 0)
  private var lastForward = SIMD3<Float>(0, 0, -1)
  private var meshes: [UUID: [Feature]] = [:]
  private var pending = 0
  private var stopping = false
  private var generation = UUID()
  private var starting: UUID?
  private var captureLease:UUID?
  private var mapRequest:UUID?
  private var mapWatchdog:Task<Void,Never>?
  var reveal = false
  private var revealBoundary:RevealBoundary?
  private var revealedNodes: [SCNNode] = []
  private let overlayRoot = SCNNode()
  private var referenceConflict = false
  private var loadedWorldMap = false
  private var markerSeen: TimeInterval = 0
  private var markerTransform: simd_float4x4?
  private var visualTransform: simd_float4x4?
  private var visualSeen: TimeInterval = 0
  private var lastVisualQuery: TimeInterval = 0
  private var visualBusy = false
  private var visualReferences: [(VisualMap, Rigid)] = []
  private var competingVisualReferences: [VisualMap] = []
  private var visualConflict = false
  private var currentReferencePoses: [UUID: ReferencePose] = [:]
  init(model: AppModel) {
    self.model = model
    super.init()
    view.session.delegate = self
    view.session.delegateQueue = .main
    view.automaticallyUpdatesLighting = true
    view.scene = SCNScene()
  }
  deinit {
    mapWatchdog?.cancel()
    let owner=model,token=captureLease
    if let token {Task { @MainActor in owner?.endCapture(token) }}
  }
  func start(room: Room, stage: Stage, prior: Segment? = nil, reveal: Bool = false, boundary:RevealBoundary? = nil) {
    guard supported, let h = model?.house else {
      message = "AR tracking is unavailable. You can still view, import, annotate and export."
      return
    }
    guard !running, !processing, starting == nil else { return }
    let startToken = UUID()
    starting = startToken
    Task {
      defer {
        if starting == startToken {starting=nil}
        if !running && !processing {releaseCaptureLease(startToken)}
      }
      let granted = await AVCaptureDevice.requestAccess(for: .video)
      guard granted else {
        message =
          "Camera permission is denied. Enable it in iPhone Settings to capture; saved projects remain available."
        return
      }
      // Capture owns the next heavy-work interval. Let reconstruction/movie
      // work reach its existing cancellation checkpoint before starting AR.
      if model?.busy==true {
        model?.cancelOperation()
        message="Finishing the previous operation before starting capture…"
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while model?.busy==true,starting==startToken,!Task.isCancelled,ProcessInfo.processInfo.systemUptime<deadline {
          try? await Task.sleep(nanoseconds:50_000_000)
        }
        guard model?.busy != true else{message="The previous operation is still stopping safely. Start capture again when it finishes.";return}
      }
      guard starting == startToken, model?.selected == h.id, UIApplication.shared.applicationState == .active else { return }
      guard let repo = model?.repository, repo.freeBytes() > 750_000_000 else {
        message = "Free at least 750 MB before starting a capture."
        return
      }
      guard model?.beginCapture(startToken)==true else{message="Another operation is active. Finish it before starting capture.";return}
      captureLease=startToken
      self.reveal = reveal
      self.revealBoundary = boundary
      houseID = h.id
      generation = UUID()
      count = 0
      meshes = [:]
      cellSet = []
      coverageCells = 0
      lastFrameTime = 0
      stopping = false
      let config = ARWorldTrackingConfiguration()
      config.planeDetection = [.horizontal, .vertical]
      config.detectionImages = await BoardGenerator.images(h, repo: repo)
      guard starting == startToken, model?.selected == h.id, UIApplication.shared.applicationState == .active else { return }
      config.maximumNumberOfTrackedImages = 2
      currentReferencePoses = [:]
      markerTransform = nil
      markerSeen = 0
      visualTransform = nil; visualSeen = 0; lastVisualQuery = 0; visualBusy = false; visualReferences = []; competingVisualReferences = []; visualConflict = false
      loadedWorldMap = false
      referenceConflict = false
      if hasDepth { config.frameSemantics.insert(.sceneDepth) }
      if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
        config.sceneReconstruction = .meshWithClassification
      }
      if let prior, let key = prior.worldMap {
        do {
          let data = try repo.read(key)
          config.initialWorldMap = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self, from: data)
          loadedWorldMap = config.initialWorldMap != nil
        } catch {
          message = "Saved map could not be loaded: \(error.localizedDescription)"
          return
        }
      }
      if reveal {
        guard let prior else {
          message = "This session has no saved AR map. Open source photographs instead."
          return
        }
        segment = prior
        var visualBytes=0
        for reference in (h.visualMaps.count<=24 ? h.visualMaps:[]).sorted(by: { $0.date > $1.date }) {
          guard let source = h.segments.first(where: { $0.id == reference.segmentID }),
            let fingerprint = try? VisualMapping.fingerprint(house: h, segment: source), fingerprint == reference.fingerprint,
            let data = try? repo.read(reference.asset), data.count < 20000000,
            let map = try? JSONDecoder().decode(VisualMap.self, from: data), map.valid, map.segmentID == source.id, map.roomID == source.roomID, map.stageID == source.stageID, map.frameID == (source.registration == nil ? source.id:nil), map.fingerprint == fingerprint,
            map.views.allSatisfy({ view in h.observations.contains(where: { $0.id == view.observationID && $0.segmentID == source.id }) })
          else { continue }
          visualBytes += data.count
          if visualBytes > 32_000_000 {visualReferences=[];competingVisualReferences=[];break}
          if VisualMapping.isCompeting(map,prior:prior) {competingVisualReferences.append(map);continue}
          if map.frameID == prior.id { visualReferences.append((map, Rigid())) }
          else if map.frameID == nil, let registration = prior.registration, let matrix = PoseRefinement.matrix(registration.values) {
            visualReferences.append((map, Rigid(values: PoseRefinement.array(simd_inverse(matrix)))))
          }
        }
        guard config.initialWorldMap != nil || !prior.referencePoses.isEmpty || !visualReferences.isEmpty else {
          message = "No usable saved alignment. Build a visual reference or use source photographs."
          return
        }
        guard let boundary,boundary.segmentID==prior.id,RevealVolumes.current(boundary,house:h) else {message="Choose a current wall or ceiling boundary before revealing this capture.";return}
        var scoped = h
        let current=DerivedEvidence.currentIDs(h)
        scoped.features = h.features.filter { $0.segmentID == prior.id && current.contains($0.id) }.map { feature in var f=feature;f.sourceFingerprint=nil;return f }
        do {
          guard scoped.features.reduce(0,{$0+$1.mesh.vertices.count})<=500000 else{throw HouseError.message("Capture exceeds the reveal geometry budget. Reconstruct a smaller segment first.")}
          scoped.features=try scoped.features.map{try RevealVolumes.clip($0,to:boundary)}
        }
        catch {message=error.localizedDescription;return}
        var localSegment=prior;localSegment.registration=nil
        scoped.segments=[localSegment]
        let scene = SceneBuilder.scene(scoped, options: SceneOptions(mode: .rough, ceilings: true))
        view.scene = scene
        overlayRoot.removeFromParentNode()
        overlayRoot.simdTransform=matrix_identity_float4x4
        overlayRoot.childNodes.forEach { $0.removeFromParentNode() }
        revealedNodes = scene.rootNode.childNodes.filter { $0.geometry != nil }
        for n in revealedNodes {
          n.removeFromParentNode()
          overlayRoot.addChildNode(n)
          n.isHidden = true
        }
        scene.rootNode.addChildNode(overlayRoot)
      } else {
        let s = Segment(roomID: room.id, stageID: stage.id)
        segment = s
        guard model?.edit(projectID: h.id, { $0.segments.append(s) }) == true else {
          message = "Could not create a durable capture session. Resolve storage before capturing."
          return
        }
        view.scene = SCNScene()
      }
      view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
      running = true
      message =
        reveal
        ? "Find the original viewpoint. Overlay stays hidden until ARKit relocalizes. Alignment remains approximate."
        : "Move slowly sideways. Capture the cavity, not just stud faces."
    }
  }
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard running else { return }
    let normal: Bool
    switch frame.camera.trackingState {
    case .normal:
      tracking = "Tracking"
      normal = true
    case .notAvailable:
      tracking = "Unavailable"
      normal = false
    case .limited(let reason):
      tracking = "Limited: \(reason)"
      normal = false
    }
    if reveal {
      if normal, !visualBusy, !visualReferences.isEmpty, frame.timestamp - lastVisualQuery > 1.5 { requestVisualLocalization(frame) }
      let markerFresh = frame.timestamp - markerSeen < 2 && markerTransform != nil
      let visualFresh = frame.timestamp - visualSeen < 2 && visualTransform != nil
      var disagreement = false
      if markerFresh, visualFresh, let a = markerTransform, let b = visualTransform {
        let av = (0..<4).flatMap { row in (0..<4).map { col in Double(a[col][row]) } }
        let bv = (0..<4).flatMap { row in (0..<4).map { col in Double(b[col][row]) } }
        disagreement = !VisualMapping.agree(Rigid(values: av), Rigid(values: bv))
      }
      let eligible = normal && !referenceConflict && !visualConflict && !disagreement
        && (markerFresh || visualFresh || (loadedWorldMap && markerTransform == nil && visualTransform == nil && frame.worldMappingStatus == .mapped))
      if markerFresh, let transform = markerTransform { overlayRoot.simdTransform = transform }
      else if visualFresh, let transform = visualTransform { overlayRoot.simdTransform = transform }
      let localCamera=simd_inverse(overlayRoot.simdWorldTransform)*frame.camera.transform.columns.3
      let front=revealBoundary?.viewedFromFront(V3(ar:SIMD3(localCamera.x,localCamera.y,localCamera.z))) == true
      revealedNodes.forEach { $0.isHidden = !eligible || !front }
      message =
        eligible
        ? (front ? "Approximate reveal: \(revealBoundary?.name ?? "selected volume"). Verify against photographs and physical references." : "You are on the opposite side of the selected boundary — overlay hidden.")
        : (visualConflict ? "Visual matches are ambiguous or inconsistent — overlay hidden. Use physical references." : "Alignment unavailable — overlay hidden. Return to the original capture viewpoint.")
      return
    }
    guard pending == 0 else { return }
    if ProcessInfo.processInfo.thermalState == .critical
      || ProcessInfo.processInfo.thermalState == .serious
    {
      message = "Phone is warm. Capture paused; let it cool."
      return
    }
    guard normal else {
      message =
        "Tracking limited. Hold still and aim at textured structure. Use Detail photo for documentary evidence."
      return
    }
    let t = frame.camera.transform
    let p = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    let f = -SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
    guard frame.timestamp - lastFrameTime > 0.8,
      lastFrameTime == 0 || simd_distance(p, lastPosition) > 0.12 || simd_dot(f, lastForward) < 0.99
    else { return }
    lastFrameTime = frame.timestamp
    lastPosition = p
    lastForward = f
    retain(frame, documentary: false)
  }
  func detail() {
    guard running, !reveal, pending == 0 else { return }
    view.session.captureHighResolutionFrame { [weak self] frame, error in
      Task { @MainActor in
        guard let self else { return }
        if let frame {
          self.retain(frame, documentary: true)
        } else {
          self.message = error?.localizedDescription ?? "Detail capture unavailable."
        }
      }
    }
  }
  private func requestVisualLocalization(_ frame: ARFrame) {
    let buffer = frame.capturedImage
    guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return }
    let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0), stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    guard width <= 4096, height <= 4096, stride * height <= 20000000 else { return }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); return }
    let gray = Data(bytes: base, count: stride * height)
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    let k = frame.camera.intrinsics
    let calibration = (0..<3).flatMap { row in (0..<3).map { col in Double(k[col][row]) } }
    let liveCamera = frame.camera.transform, timestamp = frame.timestamp, token = generation, references = visualReferences, competitors = competingVisualReferences
    visualBusy = true; lastVisualQuery = timestamp
    Task {
      let outcome = await Task.detached(priority: .userInitiated) { () -> ([Rigid],Bool) in
        guard let features = try? VisualMapping.detect(gray: gray, width: width, height: height, stride: stride) else { return ([],false) }
        if VisualMapping.competingMatch(features,width:width,height:height,intrinsics:calibration,maps:competitors) {return ([],true)}
        let estimates: [Rigid] = references.compactMap { reference in
          guard let result = VisualMapping.query(features, width: width, height: height, intrinsics: calibration, map: reference.0),
            let pose = PoseRefinement.matrix(result.transform.values), let prior = PoseRefinement.matrix(reference.1.values) else { return nil }
          return Rigid(values: PoseRefinement.array(prior * pose))
        }
        return (estimates,false)
      }.value
      guard self.generation == token else { return }
      defer { self.visualBusy = false }
      if outcome.1 {self.visualConflict=true;return}
      let estimates=outcome.0
      guard self.running, self.reveal, let first = estimates.first else { return }
      // Multiple accepted references must agree in the same saved frame.
      for estimate in estimates.dropFirst() {
        guard VisualMapping.agree(first, estimate) else { self.visualConflict = true; return }
      }
      let liveValues = (0..<4).flatMap { row in (0..<4).map { col in Double(liveCamera[col][row]) } }
      guard let alignment = VisualMapping.overlay(liveCamera: Rigid(values: liveValues), savedCanonicalCamera: first) else { return }
      var transform = matrix_identity_float4x4
      for row in 0..<4 { for col in 0..<4 { transform[col][row] = Float(alignment.values[row*4+col]) } }
      self.visualConflict = false
      self.visualTransform = transform
      self.visualSeen = timestamp
    }
  }
  private func retain(_ frame: ARFrame, documentary: Bool) {
    guard let segment, let houseID, let repo = model?.repository,
      let project=model?.houses.first(where:{$0.id==houseID}),
      let room=project.rooms.first(where:{$0.id==segment.roomID}),let stage=project.stages.first(where:{$0.id==segment.stageID}) else { return }
    guard repo.freeBytes() > 500_000_000 else {
      message = "Storage reserve reached. Saving this session."
      stop()
      return
    }
    pending += 1
    let token = generation
    let orientation: Int
    switch (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation {
    case .landscapeRight: orientation = 1
    case .landscapeLeft: orientation = 3
    case .portraitUpsideDown: orientation = 8
    default: orientation = 6
    }
    // One retained frame maximum; no unbounded ARFrame queue.
    let observedReferences = frame.anchors.compactMap { a -> ReferencePose? in
      guard let image = a as? ARImageAnchor, image.isTracked, let name = image.referenceImage.name,
        let id = UUID(uuidString: name)
      else { return nil }
      let values = (0..<4).flatMap { r in (0..<4).map { c in Double(image.transform[c][r]) } }
      return ReferencePose(boardID: id, matrix: values)
    }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      do {
        let ci = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let image = context.createCGImage(ci, from: ci.extent),
          let jpg = UIImage(cgImage: image).jpegData(compressionQuality: 0.95)
        else { throw HouseError.message("Image encoding failed.") }
        let imageKey = try repo.put(jpg, ext: "jpg")
        var depthKey: String?
        var confidenceKey: String?
        var dw = 0
        var dh = 0
        if !documentary, let depth = frame.sceneDepth {
          let buffer = depth.depthMap
          dw = CVPixelBufferGetWidth(buffer)
          dh = CVPixelBufferGetHeight(buffer)
          CVPixelBufferLockBaseAddress(buffer, .readOnly)
          var data = Data()
          if let base = CVPixelBufferGetBaseAddress(buffer) {
            for row in 0..<dh {
              data.append(
                base.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(
                  to: UInt8.self), count: dw * 4)
            }
          }
          CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
          depthKey = try repo.put(data, ext: "depth32")
          if let cb = depth.confidenceMap {
            CVPixelBufferLockBaseAddress(cb, .readOnly)
            var d = Data()
            if let base = CVPixelBufferGetBaseAddress(cb) {
              for row in 0..<dh {
                d.append(
                  base.advanced(by: row * CVPixelBufferGetBytesPerRow(cb)).assumingMemoryBound(
                    to: UInt8.self), count: dw)
              }
            }
            CVPixelBufferUnlockBaseAddress(cb, .readOnly)
            confidenceKey = try repo.put(d, ext: "confidence8")
          }
        }
        let k = frame.camera.intrinsics
        let t = frame.camera.transform
        var camera: [Double] = []
        var intrinsics: [Double] = []
        for row in 0..<4 { for col in 0..<4 { camera.append(Double(t[col][row])) } }
        for row in 0..<3 { for col in 0..<3 { intrinsics.append(Double(k[col][row])) } }
        let quality = Self.sharpness(image)
        let obs = Observation(
          roomID: segment.roomID, stageID: segment.stageID, segmentID: segment.id,
          timestamp: frame.timestamp, image: imageKey, depth: depthKey, confidence: confidenceKey,
          depthWidth: dw, depthHeight: dh, width: image.width, height: image.height, camera: camera,
          intrinsics: intrinsics, tracking: String(describing: frame.camera.trackingState),
          light: Double(frame.lightEstimate?.ambientIntensity ?? 0), sharpness: quality,
          documentary: documentary, imageOrientation: orientation,
          referenceObservations: observedReferences)
        try repo.journalCapture(projectID: houseID, observation: obs)
        try repo.stageCapture(obs,projectID:houseID,room:room,stage:stage,segment:segment)
        try repo.finishCaptureJournal(obs.id)
        Task { @MainActor in
          guard let self else { return }
          self.pending -= 1
          guard self.generation == token else { return }
          var saved = self.model?.acceptStagedCapture(obs,projectID:houseID) == true
          if saved,self.count % 5 == 0 {
            saved = self.model?.edit(projectID: houseID) { h in
              MeshSemantics.publishCaptured(self.meshes.values.flatMap{$0},segmentID:segment.id,into:&h)
              if let i = h.segments.firstIndex(where: { $0.id == segment.id }) {
                h.segments[i].referencePoses = Array(self.currentReferencePoses.values)
              }
            } == true
          }
          guard saved == true else {
            self.message = "The project checkpoint could not be committed. Durable photo records are preserved; reopen the app after resolving storage."
            if self.running { self.stop() } else if self.stopping && self.pending == 0 { self.finishStop() }
            return
          }
          self.count += 1
          let p = self.lastPosition
          self.cellSet.insert("\(Int(floor(p.x/0.25))):\(Int(floor(p.z/0.25)))")
          self.coverageCells = self.cellSet.count
          self.message =
            obs.light < 150
            ? "Low light: add illumination and revisit dark cavities."
            : quality < 0.02
              ? "Low detail or blur: hold still and move closer."
              : "Saved locally. Change your viewing angle; unseen cavity depth remains unverified."
          if self.stopping { self.finishStop() }
        }
      } catch {
        Task { @MainActor in
          guard let self else { return }
          self.pending -= 1
          self.message = error.localizedDescription
          if self.stopping { self.finishStop() }
        }
      }
    }
  }
  nonisolated static func sharpness(_ image: CGImage) -> Double {
    let n = 64
    var data = [UInt8](repeating: 0, count: n * n)
    guard
      let c = CGContext(
        data: &data, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
    else { return 0 }
    c.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
    var sum = 0.0
    for y in 1..<n {
      for x in 1..<n {
        sum +=
          abs(Double(data[y * n + x]) - Double(data[y * n + x - 1]))
          + abs(Double(data[y * n + x]) - Double(data[(y - 1) * n + x]))
      }
    }
    return sum / Double((n - 1) * (n - 1) * 510)
  }
  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    references(anchors)
    collect(anchors)
  }
  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    references(anchors)
    collect(anchors)
  }
  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    for a in anchors { meshes.removeValue(forKey: a.identifier) }
  }
  private func references(_ anchors: [ARAnchor]) {
    guard running else { return }
    for item in anchors {
      guard let anchor = item as? ARImageAnchor, anchor.isTracked,
        let name = anchor.referenceImage.name, let id = UUID(uuidString: name),
        model?.house?.references.first(where: { $0.id == id })?.valid == true
      else { continue }
      var values: [Double] = []
      for row in 0..<4 { for col in 0..<4 { values.append(Double(anchor.transform[col][row])) } }
      if reveal {
        currentReferencePoses[id] = ReferencePose(boardID: id, matrix: values)
      } else if currentReferencePoses[id] == nil {
        currentReferencePoses[id] = ReferencePose(boardID: id, matrix: values)
      }
    }
    if reveal, let s = segment, let h = model?.house, let frame = view.session.currentFrame {
      let recent = currentReferencePoses.values.filter {
        Date().timeIntervalSince($0.observed) < 1.5
      }
      if recent.count >= 2 {
        let camera = (0..<4).flatMap { r in
          (0..<4).map { c in Double(frame.camera.transform[c][r]) }
        }
        let input = Observation(
          roomID: s.roomID, stageID: s.stageID, segmentID: s.id, timestamp: frame.timestamp,
          image: "alignment", width: 1, height: 1, camera: camera,
          intrinsics: [1, 0, 0, 0, 1, 0, 0, 0, 1], tracking: "live", light: 0, sharpness: 0,
          referenceObservations: Array(recent))
        if let result = PoseRefinement.refine(
          input, segment: s, house: h, maximumCorrection: .infinity),
          let corrected = PoseRefinement.matrix(result.observation.camera),
          let current = PoseRefinement.matrix(camera)
        {
          let alignment = current * simd_inverse(corrected)
          var transform = matrix_identity_float4x4
          for row in 0..<4 { for col in 0..<4 { transform[col][row] = Float(alignment[col][row]) } }
          markerTransform = transform
          markerSeen = frame.timestamp
          referenceConflict = false
        } else {
          referenceConflict = true
          markerTransform = nil
          markerSeen = 0
        }
      }

    }
  }
  private func collect(_ anchors: [ARAnchor]) {
    guard running, !reveal, let segment else { return }
    for anchor in anchors {
      guard let a = anchor as? ARMeshAnchor, a.geometry.vertices.count < 30000 else { continue }
      let g = a.geometry
      var vertices: [V3] = []
      vertices.reserveCapacity(g.vertices.count)
      for i in 0..<g.vertices.count {
        let ptr = g.vertices.buffer.contents().advanced(
          by: g.vertices.offset + g.vertices.stride * i
        ).assumingMemoryBound(to: Float.self)
        let p = a.transform * SIMD4(ptr[0], ptr[1], ptr[2], 1)
        vertices.append(V3(ar: SIMD3(p.x, p.y, p.z)))
      }
      var triangles: [Int32] = []
      triangles.reserveCapacity(g.faces.count * 3)
      for i in 0..<g.faces.count * 3 {
        let ptr = g.faces.buffer.contents().advanced(by: i * g.faces.bytesPerIndex)
        let value =
          g.faces.bytesPerIndex == 4 ? ptr.load(as: UInt32.self) : UInt32(ptr.load(as: UInt16.self))
        triangles.append(Int32(value))
      }
      var labels:[String]=[]
      for face in 0..<g.faces.count {
        var label="unknown"
        if let source=g.classification,face<source.count {
          let offset=source.offset+face*source.stride
          if offset>=0,offset<source.buffer.length {
            let raw=Int(source.buffer.contents().advanced(by:offset).load(as:UInt8.self))
            switch ARMeshClassification(rawValue:raw) ?? .none {
            case .wall:label="wall"
            case .floor:label="floor"
            case .ceiling:label="ceiling"
            case .door:label="door"
            case .window:label="window"
            case .table:label="table"
            case .seat:label="seat"
            default:break
            }
          }
        }
        labels.append(label)
      }
      guard let stage=model?.house?.stages.first(where:{$0.id==segment.stageID}) else{continue}
      var parts=MeshSemantics.partition(Mesh(vertices:vertices,triangles:triangles),labels:labels,anchor:a.identifier,roomID:segment.roomID,stage:stage,segmentID:segment.id)
      for i in parts.indices {let id=parts[i].id;parts[i].revision=(meshes[a.identifier]?.first(where:{$0.id==id})?.revision ?? 0)+1}
      let total=meshes.values.flatMap{$0}.reduce(0){$0+$1.mesh.vertices.count}-(meshes[a.identifier] ?? []).reduce(0){$0+$1.mesh.vertices.count}+parts.reduce(0){$0+$1.mesh.vertices.count}
      if (meshes.count < 120 || meshes[a.identifier] != nil) && total <= 250000 {
        meshes[a.identifier] = parts
      } else {
        message =
          "Surface budget reached. Stop and start a new segment; original photographs continue saving."
      }
    }
  }
  func stop() {
    starting = nil
    guard running else { return }
    running = false
    stopping = true
    processing = true
    if reveal {
      view.session.pause()
      revealedNodes.forEach { $0.isHidden = true }
      finishCaptureState()
      return
    }
    if pending == 0 { finishStop() }
  }
  private func releaseCaptureLease(_ token:UUID) {
    model?.endCapture(token)
    if captureLease==token {captureLease=nil}
  }
  private func finishCaptureState() {
    mapWatchdog?.cancel();mapWatchdog=nil;mapRequest=nil
    view.session.pause();processing=false;stopping=false
    if let captureLease {releaseCaptureLease(captureLease)}
  }
  private func finishStop() {
    guard processing,mapRequest==nil else{return}
    guard let segment,let houseID,let model,let repo=model.repository else{finishCaptureState();return}
    let features = meshes.values.flatMap{$0}
    let saved = model.edit(projectID: houseID) { h in
      MeshSemantics.publishCaptured(features,segmentID:segment.id,into:&h)
      if let i = h.segments.firstIndex(where: { $0.id == segment.id }) {
        h.segments[i].referencePoses = Array(currentReferencePoses.values)
      }
    }
    guard saved else {
      finishCaptureState()
      message = "Surface checkpoint failed. Existing photographs and capture recovery records remain preserved."
      return
    }
    let request=UUID();mapRequest=request
    mapWatchdog=Task { [weak self] in
      do{try await Task.sleep(nanoseconds:8_000_000_000)}catch{return}
      guard let self,self.mapRequest==request else{return}
      self.finishCaptureState()
      self.message="Photos and geometry saved. ARKit did not return a world map; use reference boards or a visual reference for alignment."
      model.processCapture(projectID:houseID,segmentID:segment.id,automatic:true)
    }
    view.session.getCurrentWorldMap { [weak self] map, error in
      Task { @MainActor in
        guard let self,self.mapRequest==request else{return}
        defer {
          self.finishCaptureState()
          model.processCapture(projectID:houseID,segmentID:segment.id,automatic:true)
        }
        do {
          if let error {throw error}
          if let map {
            let data = try NSKeyedArchiver.archivedData(
              withRootObject: map, requiringSecureCoding: true)
            let key = try repo.put(data, ext: "armap")
            let mapSaved = model.edit(projectID: houseID) { h in
              if let i = h.segments.firstIndex(where: { $0.id == segment.id }) {
                h.segments[i].worldMap = key
              }
            }
            guard mapSaved else { throw HouseError.message("Map metadata save failed.") }
          }
          self.message = map==nil
            ? "Photos and geometry saved. No world map was available; use reference boards or a visual reference for alignment."
            : "Session saved: \(self.count) images, \(features.count) mesh patches. Approximate, uncalibrated geometry."
        } catch {
          self.message = "Photos and geometry saved. Map save failed: \(error.localizedDescription)"
        }
      }
    }
  }
  func sessionWasInterrupted(_ session: ARSession) {
    if let sid = segment?.id, let houseID {
      model?.edit(projectID: houseID) { h in
        if let i = h.segments.firstIndex(where: { $0.id == sid }) {
          h.segments[i].interrupted = true
        }
      }
    }
    message =
      "Capture interrupted. Saved images remain intact. Start a new segment when you return."
    stop()
  }
  func session(_ session: ARSession, didFailWithError error: Error) {
    message = error.localizedDescription
    stop()
  }
}
struct CaptureSurface: UIViewRepresentable {
  @ObservedObject var controller: CaptureController
  func makeUIView(context: Context) -> ARSCNView { controller.view }
  func updateUIView(_ v: ARSCNView, context: Context) {}
  static func dismantleUIView(_ v: ARSCNView, coordinator: ()) { v.session.pause() }
}
enum TextRecognition {
  static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .right) async throws
    -> String
  {
    try await Task.detached {
      let r = VNRecognizeTextRequest()
      r.recognitionLevel = .accurate
      r.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([r])
      return (r.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(
        separator: "\n")
    }.value
  }
}
