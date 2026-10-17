import Foundation

enum Reconstruction {
  static func fuse(
    house: House, segment: Segment, repo: Repository, progress: @escaping @MainActor (Double) -> Void
  ) async throws -> Feature {
    let raw = Array(
      house.observations.filter { $0.segmentID == segment.id && $0.depth != nil && !$0.documentary }
        .prefix(300))
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
        "\(count) cells supported by ≥3 captured views. \(referenceSupported ? "Two-reference consensus constraints were used.":"ARKit pose priors are not optimized.") Sample spread is not measurement accuracy. Thin services need photographs and manual tracing.",
      segmentID: segment.id)
  }
}
