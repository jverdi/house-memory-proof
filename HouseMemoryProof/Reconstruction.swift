import Foundation

enum Reconstruction {
  static func fuse(
    house: House, segment: Segment, repo: Repository, progress: @escaping @MainActor (Double) -> Void
  ) async throws -> Feature {
    let raw = house.observations.filter { $0.segmentID == segment.id && $0.depth != nil && !$0.documentary }
    let (observations, referenceSupported) = PoseRefinement.selected(
      raw, segment: segment, house: house)
    guard !observations.isEmpty else {
      throw HouseError.message("This segment has no saved depth observations.")
    }
    guard let core = hx_create(0.02, 100000) else {
      throw HouseError.message("Could not allocate bounded depth fusion.")
    }
    defer { hx_destroy(core) }
    for (frame, obs) in observations.enumerated() {
      try Task.checkCancellation()
      guard ProcessInfo.processInfo.thermalState != .critical else {
        throw HouseError.message(
          "Phone is too warm. Originals are preserved; retry reconstruction after cooling.")
      }
      guard let key = obs.depth else { continue }
      let data = try repo.read(key)
      let confidence = try obs.confidence.map { try repo.read($0) }
      let w = obs.depthWidth
      let h = obs.depthHeight
      guard w > 0, h > 0, w * h <= 1_000_000, data.count == w * h * 4,
        confidence == nil || confidence?.count == w * h
      else { throw HouseError.message("Depth array metadata does not match its bytes.") }
      let fx = obs.intrinsics[0] * Double(w) / Double(obs.width)
      let fy = obs.intrinsics[4] * Double(h) / Double(obs.height)
      let cx = obs.intrinsics[2] * Double(w) / Double(obs.width)
      let cy = obs.intrinsics[5] * Double(h) / Double(obs.height)
      let m = obs.camera
      guard fx > 0, fy > 0 else { throw HouseError.message("Invalid camera intrinsics.") }
      var samples: [HXSample] = []
      for y in stride(from: 0, to: h, by: 2) {
        for x in stride(from: 0, to: w, by: 2) {
          let i = y * w + x
          let z = Double(Float(bitPattern: data.uint32(i * 4)))
          guard z.isFinite, z > 0.15, z < 5, (confidence?[i] ?? 1) > 0 else { continue }
          let a = (Double(x) - cx) * z / fx
          let b = -(Double(y) - cy) * z / fy
          let c = -z
          let p = V3(
            m[0] * a + m[1] * b + m[2] * c + m[3], -(m[8] * a + m[9] * b + m[10] * c + m[11]),
            m[4] * a + m[5] * b + m[6] * c + m[7])
          samples.append(
            HXSample(
              x: p.x, y: p.y, z: p.z, weight: (confidence?[i] ?? 1) == 2 ? 1 : 0.5,
              frame: UInt32(frame)))
        }
      }
      _ = samples.withUnsafeBufferPointer { hx_add(core, $0.baseAddress, UInt32($0.count)) }
      await progress(Double(frame + 1) / Double(observations.count))
      await Task.yield()
    }
    guard hx_dropped(core) == 0 else {
      throw HouseError.message(
        "Reconstruction reached its 100,000-cell budget. Split capture into smaller segments; originals are intact."
      )
    }
    let count = Int(hx_count(core, 3))
    guard count > 0 else {
      throw HouseError.message(
        "No depth cells have support from three views. Capture more translated overlapping views.")
    }
    var output = [HXPoint](repeating: HXPoint(x: 0, y: 0, z: 0, spread: 0, views: 0), count: count)
    _ = output.withUnsafeMutableBufferPointer { hx_copy(core, $0.baseAddress, UInt32($0.count), 3) }
    let points = output.map { V3($0.x, $0.y, $0.z) }
    return Feature(
      name: "Fused depth · 2 cm cells", trade: .unknown, roomID: segment.roomID,
      stageID: segment.stageID, kind: house.isDemo ? .synthetic : .observed,
      mesh: Mesh(vertices: points, triangles: []), sourceIDs: observations.map { $0.id },
      notes:
        "\(count) cells supported by ≥3 captured views. \(referenceSupported ? "Locally constrained camera estimates were used.":"ARKit pose priors are not optimized.") Sample spread is not measurement accuracy. Thin services need photographs and manual tracing.",
      segmentID: segment.id, sourceFingerprint: try VisualMapping.fingerprint(house:house,segment:segment),geometrySource:.depthPoints)
  }
}

// Build a complete candidate beside immutable captures. Publish once, only when
// the source revision still matches. Individual unavailable products are named
// in the report; cancellation never publishes a partially rebuilt project.
enum CaptureProcessing {
  static func build(house:House,segmentID:UUID,repo:Repository,checkpoint:((String)throws->Void)?=nil,progress:@escaping @MainActor (String,Double)->Void)async throws->House {
    guard let index=house.segments.firstIndex(where:{$0.id==segmentID}),house.observations.filter({$0.segmentID==segmentID && $0.depth != nil && !$0.documentary}).count>=3 else{throw HouseError.message("Save at least three overlapping depth photographs before processing this capture.")}
    let started=ProcessInfo.processInfo.systemUptime
    var candidate=house,steps:[CaptureProcessingStep]=[]
    func note(_ name:String,_ passed:Bool,_ detail:String){steps.append(CaptureProcessingStep(name:name,passed:passed,detail:detail))}
    func check()throws {try Task.checkCancellation();guard ProcessInfo.processInfo.thermalState != .critical else{throw HouseError.message("Processing paused while the phone cools. Saved photographs and reconstruction checkpoints remain intact.")}}
    try check();await progress("Refining camera positions",0.05)
    do {
      let input=candidate,segment=candidate.segments[index]
      candidate.segments[index].poseSolution=try await LocalWorker.run{try PoseGraph.build(house:input,segment:segment,repo:repo)}
      note("Camera graph",true,"Connected camera estimates saved; raw capture transforms are unchanged.")
    }catch is CancellationError {throw CancellationError()}catch {note("Camera graph",false,error.localizedDescription)}
    try check();await progress("Refining photograph landmarks",0.2)
    do {
      let input=candidate,segment=candidate.segments[index]
      let result=try await LocalWorker.run{try BundleRefinement.build(house:input,segment:segment,repo:repo)}
      candidate.segments[index].poseSolution=result.solution
      // Original photographs and ARKit meshes are never invalidated by a new
      // camera solution. Source-linked derived products retain their history.
      for i in candidate.features.indices where candidate.features[i].segmentID==segmentID && candidate.features[i].sourceFingerprint != nil {candidate.features[i].artifactValid=false;candidate.features[i].hidden=true}
      candidate.features.append(result.feature)
      note("Joint landmarks",true,"\(result.solution.bundlePointCount ?? 0) independently checked photograph landmarks.")
    }catch is CancellationError {throw CancellationError()}catch {note("Joint landmarks",false,error.localizedDescription)}
    try check();await progress("Reconstructing captured surfaces",0.35)
    var rebuiltSurface=false
    do {
      let input=candidate,segment=candidate.segments[index]
      let surface=try await SurfaceReconstruction.build(house:input,segment:segment,repo:repo){value in progress("Reconstructing captured surfaces",0.35+value*0.3)}
      let parts=try await LocalWorker.run{try MeshSemantics.transfer(surface,from:input.features)}
      for i in candidate.features.indices where candidate.features[i].segmentID==segmentID && [GeometrySource.depthPoints,.depthFusion,.photoTexture].contains(candidate.features[i].resolvedGeometrySource ?? .capturedMesh) {candidate.features[i].artifactValid=false;candidate.features[i].hidden=true}
      candidate.features.append(contentsOf:parts);rebuiltSurface=true
      note("Triangle surfaces",true,"\(surface.mesh.triangles.count/3) triangles with repeated depth support. Unseen regions remain absent.")
    }catch is CancellationError {throw CancellationError()}catch {note("Triangle surfaces",false,error.localizedDescription)}
    try check();try checkpoint?("surfaces-prepared");await progress("Applying captured photographs",0.7)
    do {
      let input=candidate,segment=candidate.segments[index]
      let textures=try await LocalWorker.run{try TextureBuilder.build(house:input,segment:segment,repo:repo)}
      guard !textures.isEmpty else{throw HouseError.message("No texture geometry was produced.")}
      for i in candidate.features.indices where candidate.features[i].segmentID==segmentID && candidate.features[i].resolvedGeometrySource != nil {candidate.features[i].hidden=true}
      candidate.features.append(contentsOf:textures)
      note("Photo textures",true,"\(textures.filter{$0.texture != nil}.count) source-photo patches; unmatched regions retain untextured geometry.")
    }catch is CancellationError {throw CancellationError()}catch {
      if rebuiltSurface {for i in candidate.features.indices where candidate.features[i].segmentID==segmentID && candidate.features[i].resolvedGeometrySource == .capturedMesh {candidate.features[i].hidden=true}}
      note("Photo textures",false,error.localizedDescription)
    }
    try check();await progress("Building a visual reference",0.85)
    do {
      let input=candidate,segment=candidate.segments[index]
      let map=try await LocalWorker.run{try VisualMapping.build(house:input,segment:segment,repo:repo)}
      let key=try await LocalWorker.run{try repo.put(JSONEncoder().encode(map),ext:"vmap")}
      candidate.visualMaps.removeAll{$0.segmentID==segmentID}
      candidate.visualMaps.append(VisualMapReference(segmentID:segmentID,roomID:segment.roomID,stageID:segment.stageID,asset:key,fingerprint:map.fingerprint))
      note("Visual reference",true,"\(map.views.count) saved viewpoints. Later alignment still requires independent eligibility checks.")
    }catch is CancellationError {throw CancellationError()}catch {note("Visual reference",false,error.localizedDescription)}
    try check();await progress("Checking photo coverage",0.95)
    do {
      let input=candidate,segment=candidate.segments[index]
      let coverage=try await LocalWorker.run{try CoverageAnalyzer.analyze(house:input,segment:segment,repo:repo)}
      guard coverage.sampledPatches>0 else{throw HouseError.message("No original triangle mesh is available for a surface-coverage report.")}
      note("Observed surface coverage",true,"\(coverage.supportedPatches) of \(coverage.sampledPatches) sampled observed patches have enough photo support. This does not assess unseen cavities.")
    }catch is CancellationError {throw CancellationError()}catch {note("Observed surface coverage",false,error.localizedDescription)}
    try check()
    let report=CaptureProcessingReport(segmentID:segmentID,sourceRevision:house.revision,sourceFingerprint:try VisualMapping.fingerprint(house:candidate,segment:candidate.segments[index]),seconds:ProcessInfo.processInfo.systemUptime-started,steps:steps)
    candidate.processingReports.removeAll{$0.segmentID==segmentID};candidate.processingReports.append(report)
    try candidate.validate();try checkpoint?("candidate-ready");await progress("Saving processed capture",1)
    return candidate
  }
}

extension AppModel {
  func processCapture(projectID:UUID,segmentID:UUID,automatic:Bool=false) {
    guard let repo=repository,let source=houses.first(where:{$0.id==projectID}),!busy,!captureInProgress else{return}
    if automatic && source.observations.filter({$0.segmentID==segmentID && $0.depth != nil && !$0.documentary}).count<3 {return}
    perform("Processing saved capture") {
      let result=try await CaptureProcessing.build(house:source,segmentID:segmentID,repo:repo){label,value in self.status=label;self.progress=value}
      try Task.checkCancellation()
      guard self.houses.first(where:{$0.id==projectID})?.revision==source.revision else{throw HouseError.message("The project changed during processing. Saved captures are intact; process this session again.")}
      guard self.commit(result,select:false) else{throw HouseError.message("Processed capture could not be saved. Existing originals and the previous project remain intact.")}
      if let report=result.processingReports.last,!report.complete {self.error="Capture saved and processed with limits. Open its processing report for the stages that need more capture support."}
      return nil
    }
  }
}
