import CryptoKit
import Foundation
import SQLite3
import SwiftUI

final class Repository {
  let root: URL
  private(set) var recoveryWarnings: [String] = []
  private var db: OpaquePointer?
  private let lock = NSRecursiveLock()
  init(root: URL? = nil) throws {
    self.root =
      root
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("HouseXray", isDirectory: true)
    try FileManager.default.createDirectory(
      at: self.root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        self.root.appendingPathComponent("house.sqlite").path, &db,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    else { throw HouseError.message("Could not open local project database.") }
    sqlite3_busy_timeout(db, 3000)
    try execute(
      "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, name TEXT NOT NULL, revision INTEGER NOT NULL, json BLOB NOT NULL); CREATE TABLE IF NOT EXISTS history(id TEXT, revision INTEGER, json BLOB, PRIMARY KEY(id,revision)); CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, state TEXT, json BLOB);"
    )
  }
  deinit { sqlite3_close(db) }
  private func execute(_ sql: String) throws {
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
      throw HouseError.message("Local database write failed. Existing evidence is preserved.")
    }
  }
  private func statement(_ sql: String) throws -> OpaquePointer {
    var s: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else {
      throw HouseError.message("Could not prepare database transaction.")
    }
    return s
  }
  func all() throws -> [House] {
    lock.lock()
    defer { lock.unlock() }
    recoveryWarnings = []
    let s = try statement("SELECT id,json FROM projects ORDER BY name")
    defer { sqlite3_finalize(s) }
    var result: [House] = []
    var step = sqlite3_step(s)
    while step == SQLITE_ROW {
      defer { step = sqlite3_step(s) }
      let n = Int(sqlite3_column_bytes(s, 1))
      guard let p = sqlite3_column_blob(s, 1) else { continue }
      let data = Data(bytes: p, count: n)
      do {
        let h = try JSONDecoder().decode(House.self, from: data)
        try h.validate()
        result.append(h)
      } catch {
        let id = sqlite3_column_text(s, 0).map { String(cString: $0) } ?? "unknown"
        let recovery = root.appendingPathComponent("recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let name = UUID(uuidString: id)?.uuidString ?? UUID().uuidString
        try data.write(to: recovery.appendingPathComponent(name + ".json"), options: .atomic)
        recoveryWarnings.append(
          "Project \(name.prefix(8)) could not be opened; its database row and recovery copy remain intact. \(error.localizedDescription)"
        )
      }
    }
    guard step == SQLITE_DONE else {
      throw HouseError.message(
        "Local database could not finish reading. Existing records are preserved.")
    }
    return result
  }
  func save(_ h: House) throws {
    lock.lock()
    defer { lock.unlock() }
    try h.validate()
    let bytes = try JSONEncoder().encode(h)
    try execute("BEGIN IMMEDIATE")
    do {
      let history = try statement(
        "INSERT OR IGNORE INTO history SELECT id,revision,json FROM projects WHERE id=?")
      defer { sqlite3_finalize(history) }
      _ = h.id.uuidString.withCString {
        sqlite3_bind_text(history, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      guard sqlite3_step(history) == SQLITE_DONE else {
        throw HouseError.message("Unable to preserve prior revision.")
      }
      let s = try statement(
        "INSERT INTO projects(id,name,revision,json) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,revision=excluded.revision,json=excluded.json"
      )
      defer { sqlite3_finalize(s) }
      _ = h.id.uuidString.withCString {
        sqlite3_bind_text(s, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      _ = h.name.withCString {
        sqlite3_bind_text(s, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      sqlite3_bind_int(s, 3, Int32(h.revision))
      _ = bytes.withUnsafeBytes {
        sqlite3_bind_blob(
          s, 4, $0.baseAddress, Int32(bytes.count),
          unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
      guard sqlite3_step(s) == SQLITE_DONE else {
        throw HouseError.message("Project save failed; prior revision retained.")
      }
      // Bound full JSON revision history; original content-addressed assets are never pruned.
      let trim = try statement(
        "DELETE FROM history WHERE id=? AND revision NOT IN (SELECT revision FROM history WHERE id=? ORDER BY revision DESC LIMIT 20)"
      )
      defer { sqlite3_finalize(trim) }
      for column in 1...2 {
        _ = h.id.uuidString.withCString {
          sqlite3_bind_text(
            trim, Int32(column), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
      }
      guard sqlite3_step(trim) == SQLITE_DONE else {
        throw HouseError.message("Could not maintain revision history.")
      }
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  func previous(_ id: UUID) throws -> House? {
    lock.lock()
    defer { lock.unlock() }
    let s = try statement("SELECT json FROM history WHERE id=? ORDER BY revision DESC LIMIT 1")
    defer { sqlite3_finalize(s) }
    _ = id.uuidString.withCString {
      sqlite3_bind_text(s, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    guard sqlite3_step(s) == SQLITE_ROW, let p = sqlite3_column_blob(s, 0) else { return nil }
    return try JSONDecoder().decode(
      House.self, from: Data(bytes: p, count: Int(sqlite3_column_bytes(s, 0))))
  }
  func assetURL(_ key: String) throws -> URL {
    guard !key.contains("/"), !key.contains("\\"), !key.contains(".."), key.count < 100 else {
      throw HouseError.message("Invalid asset path.")
    }
    return root.appendingPathComponent("assets").appendingPathComponent(key)
  }
  func put(_ bytes: Data, ext: String) throws -> String {
    guard bytes.count <= 512 * 1024 * 1024 else {
      throw HouseError.message(
        "This individual asset is larger than the current 512 MB admission limit.")
    }
    let clean = ext.filter { $0.isLetter || $0.isNumber }
    let suffix = clean.isEmpty ? "bin" : String(clean.prefix(12))
    let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let key = hash + "." + suffix
    let url = try assetURL(key)
    if !FileManager.default.fileExists(atPath: url.path) {
      try bytes.write(to: url, options: .atomic)
    }
    return key
  }
  func read(_ key: String) throws -> Data {
    try Data(contentsOf: assetURL(key), options: .mappedIfSafe)
  }
  func integrity(_ h: House) throws -> Int {
    var count = 0
    for key in h.assets {
      let hash = try StreamingArchive.digest(assetURL(key)).sha
      guard key.hasPrefix(hash + ".") else {
        throw HouseError.message("Asset checksum mismatch: \(key.prefix(12)).")
      }
      count += 1
    }
    return count
  }
  func job(_ id: String, state: String, data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    let s = try statement("INSERT OR REPLACE INTO jobs VALUES(?,?,?)")
    defer { sqlite3_finalize(s) }
    _ = id.withCString {
      sqlite3_bind_text(s, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    _ = state.withCString {
      sqlite3_bind_text(s, 2, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    _ = data.withUnsafeBytes {
      sqlite3_bind_blob(
        s, 3, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      )
    }
    guard sqlite3_step(s) == SQLITE_DONE else {
      throw HouseError.message("Could not checkpoint job.")
    }
  }
  func freeBytes() -> Int64 {
    (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage) ?? 0
  }
}

@MainActor final class AppModel: ObservableObject {
  @Published var houses: [House] = []
  @Published var selected: UUID?
  @Published var error: String?
  @Published var busy = false
  @Published var progress: Double = 0
  @Published var status = ""
  @Published var shareURL: URL?
  let repository: Repository?
  init(root: URL? = nil) {
    do {
      let r = try Repository(root: root)
      repository = r
      do {
        let pendingWarnings = try r.recoverPendingCaptures()
        houses = try r.all()
        selected = houses.first?.id
        let warnings = pendingWarnings + r.recoveryWarnings
        if !warnings.isEmpty { error = warnings.joined(separator: "\n") }
      } catch { self.error = error.localizedDescription }
    } catch {
      repository = nil
      self.error = error.localizedDescription
    }
  }
  var house: House? { houses.first { $0.id == selected } }
  @discardableResult func commit(_ house: House, select: Bool = true) -> Bool {
    guard let repository else { return false }
    do {
      var h = house
      h.revision += 1
      try repository.save(h)
      if let i = houses.firstIndex(where: { $0.id == h.id }) {
        houses[i] = h
      } else {
        houses.append(h)
      }
      if select { selected = h.id }
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  func edit(_ body: (inout House) -> Void) {
    guard var h = house else { return }
    body(&h)
    commit(h)
  }
  @discardableResult func edit(projectID: UUID, _ body: (inout House) -> Void) -> Bool {
    guard var h = houses.first(where: { $0.id == projectID }) else { return false }
    body(&h)
    return commit(h, select: false)
  }
  func create(_ name: String, demo: Bool = false) {
    commit(demo ? DemoFactory.make() : House.empty(name.isEmpty ? "My house" : name))
  }
  func undo() {
    guard let id = selected, let repository else { return }
    do {
      if var h = try repository.previous(id) {
        h.revision = house?.revision ?? h.revision
        commit(h)
      } else {
        error = "No previous revision is available."
      }
    } catch { self.error = error.localizedDescription }
  }
  func perform(_ label: String, operation: @escaping () async throws -> URL?) {
    guard !busy else { return }
    busy = true
    progress = 0
    status = label
    Task {
      defer { busy = false }
      do {
        shareURL = try await operation()
        progress = 1
        status = "Complete"
      } catch {
        self.error = error.localizedDescription
        status = "Stopped; original project preserved"
      }
    }
  }
}
