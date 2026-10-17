import Foundation

enum TextureBuilder {
  struct Camera {
    var observation: Observation
    var depth: Data?
  }
  static func project(_ p: V3, through o: Observation) -> (UV, Double)? {
    CameraProjection.project(p,through:o)
  }

  static func visible(_ uv: UV, z: Double, camera: Camera) -> Bool {
    let o = camera.observation
    guard let depth = camera.depth, o.depthWidth > 0, o.depthHeight > 0 else { return false }
    let x = min(o.depthWidth - 1, Int(uv.u * Double(o.depthWidth)))
    let y = min(o.depthHeight - 1, Int(uv.v * Double(o.depthHeight)))
    let i = (y * o.depthWidth + x) * 4
    guard i + 4 <= depth.count else { return false }
    let measured = Double(Float(bitPattern: depth.uint32(i)))
    return measured.isFinite && measured > 0 && abs(measured - z) < 0.08
  }
  static func build(house: House, segment: Segment, repo: Repository) throws -> [Feature] {
    let raw = house.observations.filter {
      $0.segmentID == segment.id && $0.depth != nil && !$0.documentary
    }.sorted { $0.sharpness > $1.sharpness }
    let current=DerivedEvidence.currentIDs(house)
    let eligible=house.features.filter{$0.segmentID==segment.id && current.contains($0.id) && !$0.mesh.triangles.isEmpty}
    let reconstructed=eligible.filter{$0.resolvedGeometrySource == .depthFusion}
    let usesSurface = !reconstructed.isEmpty
    let observations = usesSurface ? PoseRefinement.selected(raw,segment:segment,house:house).0:raw
    let candidates=Array(observations.filter{$0.light>100}.prefix(16))
    let cameras=try candidates.map{Camera(observation:$0,depth:try $0.depth.map{try repo.read($0)})}
    guard !cameras.isEmpty else{throw HouseError.message("No posed depth photographs are available for visibility-tested textures.")}
    let input=reconstructed.isEmpty ? eligible.filter{$0.resolvedGeometrySource == .capturedMesh}:reconstructed
    guard !input.isEmpty else {
      throw HouseError.message("This session has no original LiDAR triangle surfaces to texture.")
    }
    var output: [Feature] = []
    for f in input {
      try Task.checkCancellation()
      final class Patch {var mesh=Mesh();var uv:[UV]=[]}
      var patches: [Int: Patch] = [:]
      var remainder = Mesh()
      for i in stride(from: 0, to: f.mesh.triangles.count, by: 3) {
        if i % 3000 == 0 { try Task.checkCancellation() }
        let vertices = (0..<3).map { f.mesh.vertices[Int(f.mesh.triangles[i + $0])] }
        var winner: Int?
        var coordinates: [UV] = []
        for (j, c) in cameras.enumerated() {
          let projections = vertices.compactMap { project($0, through: c.observation) }
          if projections.count == 3 && projections.allSatisfy({ visible($0.0, z: $0.1, camera: c) })
          {
            winner = j
            coordinates = projections.map { $0.0 }
            break
          }
        }
        if let winner {
          let patch:Patch
          if let existing=patches[winner] {patch=existing}else{patch=Patch();patches[winner]=patch}
          let base = Int32(patch.mesh.vertices.count)
          patch.mesh.vertices += vertices
          patch.mesh.triangles += [base, base + 1, base + 2]
          patch.uv += coordinates
        } else {
          let base = Int32(remainder.vertices.count)
          remainder.vertices += vertices
          remainder.triangles += [base, base + 1, base + 2]
        }
      }
      for (j, patch) in patches.sorted(by: { $0.key < $1.key }) {
        var copy = f
        copy.id = UUID()
        copy.geometrySource = .photoTexture
        copy.hidden = false
        copy.name = "Photo-textured surface"
        copy.mesh = patch.mesh
        copy.uv = patch.uv
        copy.texture = cameras[j].observation.image
        copy.sourceIDs = [cameras[j].observation.id]
        copy.notes =
          "Source photo selected from this session using camera projection and first-surface depth agreement within 8 cm. Display texture, not a precision refinement."
        output.append(copy)
      }
      if !remainder.triangles.isEmpty {
        var copy = f
        copy.id = UUID()
        copy.geometrySource = .photoTexture
        copy.hidden = false
        copy.name = "Untextured surface · missing photo support"
        copy.mesh = remainder
        output.append(copy)
      }
    }
    let fingerprint=try VisualMapping.fingerprint(house:house,segment:segment)
    for i in output.indices {output[i].sourceFingerprint=fingerprint}
    return output
  }
}
