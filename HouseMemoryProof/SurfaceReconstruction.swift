import Foundation

@MainActor enum SurfaceReconstruction {
  static func build(
    house: House, segment: Segment, repo: Repository, progress: @escaping (Double) -> Void
  ) async throws -> Feature {
    let raw = Array(
      house.observations.filter { $0.segmentID == segment.id && $0.depth != nil && !$0.documentary }
        .prefix(300))
    let (observations, referenceSupported) = PoseRefinement.selected(
      raw, segment: segment, house: house)
    guard !observations.isEmpty, let core = hx_surface_create(0.02, 400000) else {
      throw HouseError.message("No depth observations or insufficient surface-fusion resources.")
    }
    defer { hx_surface_destroy(core) }
    for (frame, o) in observations.enumerated() {
      try Task.checkCancellation()
      guard ProcessInfo.processInfo.thermalState != .critical else {
        throw HouseError.message(
          "Surface fusion paused because the phone is too warm. Originals remain intact; retry after cooling."
        )
      }
      let depth = try repo.read(o.depth!)
      let confidence = try o.confidence.map { try repo.read($0) }
      let w = o.depthWidth
      let h = o.depthHeight
      guard w >= 3, h >= 3, w * h <= 1_000_000, depth.count == w * h * 4,
        confidence == nil || confidence?.count == w * h
      else { throw HouseError.message("Depth buffer does not match its calibration.") }
      let fx = o.intrinsics[0] * Double(w) / Double(o.width)
      let fy = o.intrinsics[4] * Double(h) / Double(o.height)
      let cx = o.intrinsics[2] * Double(w) / Double(o.width)
      let cy = o.intrinsics[5] * Double(h) / Double(o.height)
      let conf = confidence ?? Data(repeating: 1, count: w * h)
      let status = depth.withUnsafeBytes { d in
        conf.withUnsafeBytes { c in
          o.camera.withUnsafeBufferPointer { m in
            hx_surface_integrate(
              core, d.bindMemory(to: Float.self).baseAddress,
              c.bindMemory(to: UInt8.self).baseAddress, UInt32(w), UInt32(h), fx, fy, cx, cy,
              m.baseAddress, UInt32(frame))
          }
        }
      }
      guard status >= 0, hx_surface_dropped(core) == 0 else {
        throw HouseError.message(
          "Surface fusion reached its bounded volume or rejected a frame. Split the capture into smaller sessions; originals are preserved."
        )
      }
      progress(Double(frame + 1) / Double(observations.count) * 0.85)
      await Task.yield()
    }
    let count = Int(hx_surface_mesh(core, nil, 0, 3))
    guard count > 0, count <= 500000 else {
      throw HouseError.message(
        count == 0
          ? "No triangle surfaces have three-view depth support. Add overlapping captures."
          : "Surface exceeds 500,000 vertices. Use smaller capture sessions.")
    }
    var vertices = [HXVertex](repeating: HXVertex(x: 0, y: 0, z: 0), count: count)
    let copied = vertices.withUnsafeMutableBufferPointer {
      hx_surface_mesh(core, $0.baseAddress, UInt32(count), 3)
    }
    guard copied == count else { throw HouseError.message("Surface candidate was incomplete.") }
    progress(1)
    return Feature(
      name: "Reconstructed depth surface", trade: .unknown, roomID: segment.roomID,
      stageID: segment.stageID, kind: house.isDemo ? .synthetic : .observed,
      mesh: Mesh(
        vertices: vertices.map { V3($0.x, $0.y, $0.z) }, triangles: Array(0..<Int32(count))),
      sourceIDs: observations.map { $0.id },
      notes:
        "Sparse 2 cm signed-distance fusion, 6 cm truncation and ≥3 distinct views. Depth discontinuities are excluded. \(referenceSupported ? "Two-reference consensus camera constraints were used; unreferenced frames were excluded.":"Uses unoptimized camera priors.") Thin services, occlusions and precision remain unqualified.",
      segmentID: segment.id)
  }
}
