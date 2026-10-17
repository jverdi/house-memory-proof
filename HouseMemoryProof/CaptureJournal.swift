import Foundation

// This journal spans the asset-write / SQLite-commit boundary. It is removed only
// after a capture record has been committed, and replay is idempotent by UUID.
struct PendingCapture: Codable {
  var projectID: UUID
  var observation: Observation
}
extension Repository {
  var captureJournal: URL { root.appendingPathComponent("pending-captures", isDirectory: true) }
  func journalCapture(projectID: UUID, observation: Observation) throws {
    try FileManager.default.createDirectory(at: captureJournal, withIntermediateDirectories: true)
    let url = captureJournal.appendingPathComponent(observation.id.uuidString + ".json")
    let data = try JSONEncoder().encode(PendingCapture(projectID: projectID, observation: observation))
    try data.write(to: url, options: .atomic)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    try file.synchronize()
  }
  func finishCaptureJournal(_ id: UUID) throws {
    let url = captureJournal.appendingPathComponent(id.uuidString + ".json")
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }
  func recoverPendingCaptures() throws -> [String] {
    guard FileManager.default.fileExists(atPath: captureJournal.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(at: captureJournal, includingPropertiesForKeys: [.fileSizeKey])
      .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard files.count <= 50000 else { throw HouseError.message("Capture recovery exceeds its admission budget; journal preserved.") }
    var projects = Dictionary(uniqueKeysWithValues: try all().map { ($0.id, $0) })
    var warnings: [String] = []
    for url in files {
      do {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1000000 else {
          throw HouseError.message("Oversized capture journal record.")
        }
        let pending = try JSONDecoder().decode(PendingCapture.self, from: Data(contentsOf: url))
        let o = pending.observation
        guard url.lastPathComponent == o.id.uuidString + ".json", var h = projects[pending.projectID] else {
          throw HouseError.message("Capture's original project is unavailable; its journal is preserved.")
        }
        if let existing = h.observations.first(where: { $0.id == o.id }) {
          guard existing == o else { throw HouseError.message("Conflicting capture identities; journal preserved.") }
        } else {
          for key in [o.image, o.depth, o.confidence].compactMap({ $0 }) {
            let digest = try StreamingArchive.digest(assetURL(key))
            guard key.hasPrefix(digest.sha + ".") else { throw HouseError.message("Capture asset failed its recovery checksum.") }
          }
          h.observations.append(o)
          h.revision += 1
          try save(h)
          projects[h.id] = h
        }
        try finishCaptureJournal(o.id)
      } catch {
        warnings.append("Capture recovery: \(error.localizedDescription)")
      }
    }
    return Array(Set(warnings)).sorted()
  }
}
