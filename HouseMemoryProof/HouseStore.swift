import CryptoKit
import Foundation
import SQLite3
import SwiftUI

final class Repository: EvidenceAssetReader {
  static var defaultRoot:URL {
    let legacy=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HouseXray",isDirectory:true)
    // Preserve any prior beta store in place; fresh installs expose originals in Files.
    if FileManager.default.fileExists(atPath:legacy.appendingPathComponent("house.sqlite").path){return legacy}
    return FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("HouseXray",isDirectory:true)
  }
  let root: URL
  private(set) var recoveryWarnings: [String] = []
  private var db: OpaquePointer?
  private let lock = NSRecursiveLock()
  static let storeVersion=2
  init(root: URL? = nil,migrationCheckpoint:(()throws->Void)?=nil) throws {
    self.root = root ?? Self.defaultRoot
    try FileManager.default.createDirectory(
      at: self.root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        self.root.appendingPathComponent("house.sqlite").path, &db,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    else {sqlite3_close(db);db=nil;throw HouseError.message("Could not open local project database.") }
    sqlite3_busy_timeout(db, 3000)
    do {
      let version=try scalar("PRAGMA user_version")
      guard version<=Self.storeVersion else{throw HouseError.message("This project store was created by a newer House Xray build. Update the app to open it; the store has not been changed.")}
      try execute("PRAGMA synchronous=FULL;")
      if version<Self.storeVersion {
        if try scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='projects'")>0{try snapshotBeforeMigration(version:version)}
        try execute("BEGIN IMMEDIATE")
        do {
          try execute("CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, name TEXT NOT NULL, revision INTEGER NOT NULL, json BLOB NOT NULL); CREATE TABLE IF NOT EXISTS history(id TEXT, revision INTEGER, json BLOB, PRIMARY KEY(id,revision)); CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, state TEXT, json BLOB); CREATE TABLE IF NOT EXISTS capture_records(project_id TEXT NOT NULL, id TEXT NOT NULL, json BLOB NOT NULL, PRIMARY KEY(project_id,id)); PRAGMA user_version=2;")
          try migrationCheckpoint?()
          try execute("COMMIT")
        }catch{try? execute("ROLLBACK");throw error}
      }
      try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
    }catch{sqlite3_close(db);db=nil;throw error}
  }
  deinit { sqlite3_close(db) }
  private func scalar(_ sql:String)throws->Int {
    let query=try statement(sql);defer{sqlite3_finalize(query)}
    guard sqlite3_step(query)==SQLITE_ROW else{throw HouseError.message("Could not inspect the local store version.")}
    return Int(sqlite3_column_int64(query,0))
  }
  private func snapshotBeforeMigration(version:Int)throws {
    let directory=root.appendingPathComponent("metadata-snapshots",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let name="before-v\(version)-\(UUID().uuidString)",partial=directory.appendingPathComponent(name+".partial"),final=directory.appendingPathComponent(name+".sqlite")
    let required=Int64(try scalar("PRAGMA page_count"))*Int64(try scalar("PRAGMA page_size"))
    guard freeBytes()>required+100_000_000 else{throw HouseError.message("Free space is required for a verified metadata snapshot before this app update can open the store. Existing evidence remains intact.")}
    var target:OpaquePointer?
    guard sqlite3_open_v2(partial.path,&target,SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE,nil)==SQLITE_OK else{sqlite3_close(target);throw HouseError.message("Could not create the pre-update metadata snapshot.")}
    defer{sqlite3_close(target);try? FileManager.default.removeItem(at:partial)}
    guard let backup=sqlite3_backup_init(target,"main",db,"main") else{throw HouseError.message("Could not start the pre-update metadata snapshot.")}
    var status=SQLITE_OK;let deadline=Date().addingTimeInterval(30)
    repeat {
      status=sqlite3_backup_step(backup,256)
      if status==SQLITE_BUSY || status==SQLITE_LOCKED{Thread.sleep(forTimeInterval:0.02)}
    }while [SQLITE_OK,SQLITE_BUSY,SQLITE_LOCKED].contains(status) && Date()<deadline
    let finished=sqlite3_backup_finish(backup)
    guard status==SQLITE_DONE,finished==SQLITE_OK else{throw HouseError.message("The pre-update snapshot could not finish. Retry after closing other House Xray windows.")}
    var check:OpaquePointer?
    guard sqlite3_prepare_v2(target,"PRAGMA quick_check",-1,&check,nil)==SQLITE_OK else{throw HouseError.message("Could not verify the pre-update snapshot.")}
    defer{sqlite3_finalize(check)}
    guard sqlite3_step(check)==SQLITE_ROW,let value=sqlite3_column_text(check,0),String(cString:value)=="ok" else{throw HouseError.message("The pre-update snapshot failed its integrity check. The original store was not migrated.")}
    let handle=try FileHandle(forWritingTo:partial);try handle.synchronize();try handle.close()
    let digest=try StreamingArchive.digest(partial)
    try FileManager.default.moveItem(at:partial,to:final)
    try DurableFiles.write(try JSONSerialization.data(withJSONObject:["fromVersion":version,"targetVersion":Self.storeVersion,"database":final.lastPathComponent,"sha256":digest.sha,"originalAssetsCopied":false],options:[.sortedKeys]),to:final.appendingPathExtension("json"))
  }
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
      guard n>0,n<=100_000_000,let p = sqlite3_column_blob(s, 1) else {
        recoveryWarnings.append("A project row is empty or exceeds its read budget; its database contents remain intact.")
        continue
      }
      let data = Data(bytes: p, count: n)
      do {
        var h = try JSONDecoder().decode(House.self, from: data)
        guard let row=sqlite3_column_text(s,0),UUID(uuidString:String(cString:row))==h.id else{throw HouseError.message("Stored project identity disagrees with its database row.")}
        let pending=try captureRecords(projectID:h.id)
        guard Set(h.observations.map{$0.id}).count==h.observations.count else{throw HouseError.message("Duplicate capture identities in the stored project.")}
        var known=Dictionary(uniqueKeysWithValues:h.observations.map{($0.id,$0)})
        for observation in pending {
          if let existing=known[observation.id] {guard existing==observation else{throw HouseError.message("Conflicting durable capture identities; originals preserved.")}}
          else {h.observations.append(observation);h.revision+=1;known[observation.id]=observation}
        }
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
    guard bytes.count <= 100_000_000 else {throw HouseError.message("Project metadata exceeds the 100 MB storage budget. Existing revisions and originals remain intact; use smaller capture projects.")}
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
      let included=Set(h.observations.map{$0.id})
      for observation in try captureRecords(projectID:h.id) where included.contains(observation.id) {
        let remove=try statement("DELETE FROM capture_records WHERE project_id=? AND id=?")
        defer{sqlite3_finalize(remove)}
        for (index,value) in [h.id.uuidString,observation.id.uuidString].enumerated(){_=value.withCString{sqlite3_bind_text(remove,Int32(index+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}}
        guard sqlite3_step(remove)==SQLITE_DONE else{throw HouseError.message("Could not finish the capture checkpoint.")}
      }
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  private func captureRecords(projectID:UUID)throws->[Observation] {
    let query=try statement("SELECT json FROM capture_records WHERE project_id=? ORDER BY rowid")
    defer{sqlite3_finalize(query)}
    _=projectID.uuidString.withCString{sqlite3_bind_text(query,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
    var result:[Observation]=[],status=sqlite3_step(query)
    while status==SQLITE_ROW {
      guard result.count<50000,let bytes=sqlite3_column_blob(query,0),sqlite3_column_bytes(query,0)<=1000000 else{throw HouseError.message("Durable capture record exceeds its admission budget.")}
      result.append(try JSONDecoder().decode(Observation.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(query,0)))))
      status=sqlite3_step(query)
    }
    guard status==SQLITE_DONE else{throw HouseError.message("Could not read durable capture records.")};return result
  }
  func stageCapture(_ observation:Observation,projectID:UUID,room:Room,stage:Stage,segment:Segment)throws {
    lock.lock();defer{lock.unlock()}
    var validation=House(name:"Capture admission");validation.rooms=[room];validation.stages=[stage]
    var frame=segment;frame.poseSolution=nil;frame.registrationLink=nil
    validation.segments=[frame];validation.observations=[observation];try validation.validate()
    let bytes=try JSONEncoder().encode(observation)
    guard bytes.count<=1000000 else{throw HouseError.message("Capture metadata exceeds its admission budget.")}
    let query=try statement("INSERT OR IGNORE INTO capture_records(project_id,id,json) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM projects WHERE id=?)")
    defer{sqlite3_finalize(query)}
    for (index,value) in [(1,projectID.uuidString),(2,observation.id.uuidString),(4,projectID.uuidString)] {_=value.withCString{sqlite3_bind_text(query,Int32(index),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}}
    _=bytes.withUnsafeBytes{sqlite3_bind_blob(query,3,$0.baseAddress,Int32(bytes.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
    guard sqlite3_step(query)==SQLITE_DONE else{throw HouseError.message("Could not durably save this photograph's metadata.")}
    let check=try statement("SELECT json FROM capture_records WHERE project_id=? AND id=?");defer{sqlite3_finalize(check)}
    for (index,value) in [projectID.uuidString,observation.id.uuidString].enumerated(){_=value.withCString{sqlite3_bind_text(check,Int32(index+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}}
    guard sqlite3_step(check)==SQLITE_ROW,let stored=sqlite3_column_blob(check,0),try JSONDecoder().decode(Observation.self,from:Data(bytes:stored,count:Int(sqlite3_column_bytes(check,0))))==observation else{throw HouseError.message("Original project is missing or the capture identity conflicts; its recovery journal remains intact.")}
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
      try DurableFiles.write(bytes,to:url)
    } else {
      guard try StreamingArchive.digest(url).sha==hash else{throw HouseError.message("An existing original failed its checksum. It was preserved for recovery; new evidence was not linked to it.")}
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
  func jobData(_ id:String)throws->Data? {
    lock.lock();defer{lock.unlock()}
    let s=try statement("SELECT json FROM jobs WHERE id=?");defer{sqlite3_finalize(s)}
    _=id.withCString{sqlite3_bind_text(s,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
    let status=sqlite3_step(s)
    if status==SQLITE_DONE{return nil}
    guard status==SQLITE_ROW,let bytes=sqlite3_column_blob(s,0) else{throw HouseError.message("Could not read the local job checkpoint.")}
    let count=Int(sqlite3_column_bytes(s,0));guard count<=1_000_000 else{throw HouseError.message("Job metadata exceeds its budget.")}
    return Data(bytes:bytes,count:count)
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

#if DEBUG
// Used only by isolated diagnostics; never downgrades an owner project store.
enum StoreMigrationDiagnostics {
  static func legacyFixture(at root:URL)throws->UUID {
    var repository:Repository?=try Repository(root:root)
    let house=try SimulatedCapture.make(repo:repository!)
    try repository!.save(house);repository=nil
    try setVersion(at:root,version:1,dropCaptureTable:true)
    return house.id
  }
  static func setVersion(at root:URL,version:Int,dropCaptureTable:Bool=false)throws {
    var database:OpaquePointer?
    guard sqlite3_open_v2(root.appendingPathComponent("house.sqlite").path,&database,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK else{sqlite3_close(database);throw HouseError.message("Migration fixture could not open.")}
    defer{sqlite3_close(database)}
    let sql=(dropCaptureTable ? "DROP TABLE capture_records;":"")+"PRAGMA user_version=\(version)"
    guard sqlite3_exec(database,sql,nil,nil,nil)==SQLITE_OK else{throw HouseError.message("Migration fixture setup failed.")}
  }
  static func state(at root:URL)throws->(Int,Int) {
    var database:OpaquePointer?
    guard sqlite3_open_v2(root.appendingPathComponent("house.sqlite").path,&database,SQLITE_OPEN_READONLY,nil)==SQLITE_OK else{sqlite3_close(database);throw HouseError.message("Migration fixture inspection failed.")}
    defer{sqlite3_close(database)}
    func value(_ sql:String)throws->Int {
      var query:OpaquePointer?;defer{sqlite3_finalize(query)}
      guard sqlite3_prepare_v2(database,sql,-1,&query,nil)==SQLITE_OK,sqlite3_step(query)==SQLITE_ROW else{throw HouseError.message("Migration fixture query failed.")}
      return Int(sqlite3_column_int(query,0))
    }
    return (try value("PRAGMA user_version"),try value("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='capture_records'"))
  }
}
#endif

@MainActor final class AppModel: ObservableObject {
  @Published var houses: [House] = []
  @Published var selected: UUID?
  @Published var error: String?
  @Published var busy = false
  @Published var progress: Double = 0
  @Published var status = ""
  @Published var shareURL: URL?
  private var operationTask: Task<Void, Never>?
  private var captureOwner:UUID?
  let repository: Repository?
  init(root: URL? = nil) {
    do {
      let r = try Repository(root: root)
      repository = r
      do {
        var pendingWarnings: [String] = []
        do { pendingWarnings = try r.recoverPendingCaptures() }
        catch { pendingWarnings = ["Capture recovery needs attention: " + error.localizedDescription] }
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
      ReferenceRegistration.invalidateChangedInputs(&h)
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
  @discardableResult func acceptStagedCapture(_ observation:Observation,projectID:UUID)->Bool {
    guard let index=houses.firstIndex(where:{$0.id==projectID}) else{error="Capture project is unavailable; its durable record will recover on reopening.";return false}
    if let existing=houses[index].observations.first(where:{$0.id==observation.id}) {return existing==observation}
    houses[index].observations.append(observation);houses[index].revision+=1;return true
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
  func beginCapture(_ token:UUID)->Bool {
    guard !busy,captureOwner==nil else{return false}
    captureOwner=token;return true
  }
  func endCapture(_ token:UUID) {if captureOwner==token {captureOwner=nil}}
  var captureInProgress:Bool {captureOwner != nil}
  func cancelOperation() { operationTask?.cancel(); status = "Stopping at the next safe boundary…" }
  func perform(_ label: String, operation: @escaping () async throws -> URL?) {
    guard !busy else { return }
    guard captureOwner==nil else {error="Finish saving the capture before starting this operation.";return}
    busy = true
    progress = 0
    status = label
    operationTask = Task {
      defer { busy = false; operationTask = nil }
      do {
        let result = try await operation()
        try Task.checkCancellation()
        shareURL = result
        progress = 1
        status = "Complete"
      } catch is CancellationError {
        status = "Cancelled; originals preserved"
      } catch {
        self.error = error.localizedDescription
        status = "Stopped; original project preserved"
      }
    }
  }
}
