import Foundation
import simd

// Local reference constraints correct common AR-map drift without rewriting raw
// observations. This is not bundle adjustment or a calibrated uncertainty model.
enum PoseRefinement {
  struct Result {
    var observation: Observation
    var boards: [UUID]
    var maxDisagreement: Double
  }
  static func matrix(_ values: [Double]) -> simd_double4x4? {
    guard Rigid(values: values).valid else { return nil }
    var m = matrix_identity_double4x4
    for row in 0..<4 { for col in 0..<4 { m[col][row] = values[row * 4 + col] } }
    return m
  }
  static func array(_ m: simd_double4x4) -> [Double] {
    (0..<4).flatMap { r in (0..<4).map { c in m[c][r] } }
  }
  static func refine(
    _ o: Observation, segment: Segment, house: House, maximumCorrection: Double = 0.25
  ) -> Result? {
    guard let camera = matrix(o.camera), let seen = o.referenceObservations else { return nil }
    let valid = Set(house.references.filter { $0.valid }.map { $0.id })
    var candidates: [(UUID, simd_double4x4)] = []
    for observation in seen where valid.contains(observation.boardID) {
      guard let fixed = segment.referencePoses.first(where: { $0.boardID == observation.boardID }),
        let original = matrix(fixed.matrix), let measured = matrix(observation.matrix)
      else { continue }
      let candidate = original * simd_inverse(measured) * camera
      if Rigid(values: array(candidate)).valid,
        simd_distance(candidate.columns.3, camera.columns.3) <= maximumCorrection
      {
        candidates.append((observation.boardID, candidate))
      }
    }
    // A single board cannot independently check whether it moved.
    guard candidates.count >= 2, Set(candidates.map { $0.0 }).count == candidates.count else {
      return nil
    }
    func position(_ m: simd_double4x4) -> SIMD3<Double> {
      SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
    func rotation(_ m: simd_double4x4) -> simd_quatd {
      simd_quatd(
        simd_double3x3(
          SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
          SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
          SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
    }
    var worst = 0.0
    for i in candidates.indices {
      for j in candidates.indices where j > i {
        let delta = simd_distance(position(candidates[i].1), position(candidates[j].1))
        worst = max(worst, delta)
        let angle =
          2
          * acos(
            min(
              1, abs(simd_dot(rotation(candidates[i].1).vector, rotation(candidates[j].1).vector))))
        guard delta <= 0.03, angle <= 3 * Double.pi / 180 else { return nil }
      }
    }
    let base = rotation(candidates[0].1).vector
    var q = SIMD4<Double>(repeating: 0)
    var p = SIMD3<Double>(repeating: 0)
    for candidate in candidates {
      var r = rotation(candidate.1).vector
      if simd_dot(r, base) < 0 { r = -r }
      q += r
      p += position(candidate.1)
    }
    guard simd_length(q) > 1e-9 else { return nil }
    var corrected = simd_double4x4(simd_quatd(vector: simd_normalize(q)))
    p /= Double(candidates.count)
    corrected.columns.3 = SIMD4(p, 1)
    var observation = o
    observation.camera = array(corrected)
    return Result(observation: observation, boards: candidates.map { $0.0 }, maxDisagreement: worst)
  }
  static func selectedForHouse(_ house:House)->[Observation] {
    let grouped=Dictionary(grouping:house.observations.filter{!$0.documentary},by:{$0.segmentID})
    return house.segments.flatMap{selected(grouped[$0.id] ?? [],segment:$0,house:house).0}
  }
  static func selected(_ observations: [Observation], segment: Segment, house: House) -> (
    [Observation], Bool
  ) {
    if let optimized = PoseGraph.selected(observations, segment: segment, house: house) {
      return (optimized, true)
    }
    let refined = observations.compactMap {
      refine($0, segment: segment, house: house)?.observation
    }
    // Never mix frames with corrected and uncorrected priors in one candidate.
    return refined.count >= 3 ? (refined, true) : (observations, false)
  }
}
