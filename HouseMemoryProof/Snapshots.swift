import SwiftUI
import UniformTypeIdentifiers

// User-selected Files storage avoids a hosted service or a required iCloud container.
// File-provider sync is managed by iOS; successful local copy is not proof of cloud upload.
enum SnapshotStorage {
  static func write(house: House, repo: Repository, folder: URL) throws -> String {
    let archive = try Exporter.archive(house, repo: repo)
    defer { try? FileManager.default.removeItem(at: archive) }
    let name =
      "HouseXray-\(house.id.uuidString.prefix(8))-r\(house.revision)-\(UUID().uuidString.prefix(8)).hxray"
    let destination = folder.appendingPathComponent(name)
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var operationError: Error?
    coordinator.coordinate(writingItemAt: destination, options: [], error: &coordinationError) {
      url in
      let temporary = url.appendingPathExtension("partial")
      do {
        try FileManager.default.copyItem(at: archive, to: temporary)
        _ = try StreamingArchive.index(temporary)
        try FileManager.default.moveItem(at: temporary, to: url)
      } catch {
        try? FileManager.default.removeItem(at: temporary)
        operationError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let operationError { throw operationError }
    let state = try? destination.resourceValues(forKeys: [
      .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
    ])
    if state?.isUbiquitousItem == true {
      return state?.ubiquitousItemIsUploaded == true
        ? "Snapshot saved and reported uploaded by iCloud."
        : "Snapshot saved locally in iCloud Drive; upload was pending at save time."
    }
    return "Snapshot saved to the chosen folder. Provider upload status is unavailable."
  }
}
@MainActor enum SnapshotService {
  static let bookmarkKey = "snapshot-folder-bookmark", automaticKey = "snapshot-on-open",
    statusKey = "snapshot-status"
  static var status: String {
    UserDefaults.standard.string(forKey: statusKey)
      ?? "No independent folder snapshot has been saved."
  }
  static func select(_ folder: URL) throws {
    let access = folder.startAccessingSecurityScopedResource()
    defer { if access { folder.stopAccessingSecurityScopedResource() } }
    let bookmark = try folder.bookmarkData(
      options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    UserDefaults.standard.set(
      "Folder selected. Save a snapshot and verify a restore.", forKey: statusKey)
  }
  static func save(_ house: House, repo: Repository) async throws {
    guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
      throw HouseError.message("Choose a backup folder in Files first.")
    }
    let result = try await Task.detached(priority: .utility) {
      var stale = false
      let folder = try URL(
        resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil,
        bookmarkDataIsStale: &stale)
      guard !stale else {
        throw HouseError.message(
          "The backup-folder permission changed. Choose the folder again; local evidence is intact."
        )
      }
      let access = folder.startAccessingSecurityScopedResource()
      defer { if access { folder.stopAccessingSecurityScopedResource() } }
      return try SnapshotStorage.write(house: house, repo: repo, folder: folder)
    }.value
    UserDefaults.standard.set(result + " Revision \(house.revision).", forKey: statusKey)
    UserDefaults.standard.set(Date(), forKey: "snapshot-date-" + house.id.uuidString)
  }
  static func automatic(model: AppModel) {
    guard UserDefaults.standard.bool(forKey: automaticKey), !model.busy, let house = model.house,
      let repo = model.repository, UserDefaults.standard.data(forKey: bookmarkKey) != nil
    else { return }
    if let previous = UserDefaults.standard.object(forKey: "snapshot-date-" + house.id.uuidString)
      as? Date, Date().timeIntervalSince(previous) < 86400
    {
      return
    }
    model.perform("Saving selected house snapshot") {
      do { try await save(house, repo: repo) } catch {
        UserDefaults.standard.set(
          "Snapshot needs attention: " + error.localizedDescription, forKey: statusKey)
        throw error
      }
      return nil
    }
  }
}
struct SnapshotSettings: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var choosing = false
  @State private var automatic = UserDefaults.standard.bool(forKey: SnapshotService.automaticKey)
  @State private var status = SnapshotService.status
  var body: some View {
    Form {
      Section {
        Text(
          "Choose a folder in Files, optionally in iCloud Drive. No app backend is needed. iOS requires your initial folder selection; an agent cannot silently grant that permission."
        ).font(.footnote)
        Button("Choose snapshot folder") { choosing = true }
        Toggle("Daily snapshot when opening this house", isOn: $automatic).onChange(of: automatic) {
          _, value in UserDefaults.standard.set(value, forKey: SnapshotService.automaticKey)
        }
      }
      Section {
        Button("Save snapshot now") {
          guard let repo = model.repository else { return }
          model.perform("Writing verified folder snapshot") {
            do {
              try await SnapshotService.save(house, repo: repo)
              status = SnapshotService.status
            } catch {
              status = error.localizedDescription
              throw error
            }
            return nil
          }
        }.disabled(model.busy)
        Text(status).font(.footnote)
      }
      Section {
        Text(
          "Runs while the app is active; it cannot promise an overnight upload while iOS suspends the app. Incomplete files fail archive restore checks. Originals are never evicted. Each snapshot is complete and uses additional storage; automatic incremental chunk sync is not implemented."
        ).font(.footnote)
      }
    }.navigationTitle("Folder snapshots").fileImporter(
      isPresented: $choosing, allowedContentTypes: [.folder], allowsMultipleSelection: false
    ) { result in
      do {
        if let url = try result.get().first {
          try SnapshotService.select(url)
          status = SnapshotService.status
        }
      } catch { model.error = error.localizedDescription }
    }
  }
}
