import Foundation
import CryptoKit

struct SnapshotRevision:Codable,Identifiable {
  var format="HouseXraySnapshot";var version=1;var id=UUID();var date=Date()
  var projectID:UUID;var name:String;var revision:Int;var metadata:String;var assets:[String]
}
enum IncrementalSnapshots {
  static func root(_ folder:URL)->URL {folder.appendingPathComponent("HouseXraySnapshots",isDirectory:true)}
  static func hash(_ bytes:Data)->String {SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
  static func safe(_ key:String)->Bool {key.count<100 && !key.contains("/") && !key.contains("\\") && !key.contains("..") && key.count>=65 && key.prefix(64).allSatisfy{$0.isHexDigit} && key.dropFirst(64).first=="."}
  static func publish(source:URL,destination:URL,expected:String?=nil)throws {
    let coordinator=NSFileCoordinator(filePresenter:nil);var coordinationError:NSError?,operationError:Error?
    coordinator.coordinate(writingItemAt:destination,options:[],error:&coordinationError){url in
      let temporary=url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".partial")
      do {try Task.checkCancellation();try FileManager.default.copyItem(at:source,to:temporary);let a=try StreamingArchive.digest(source),b=try StreamingArchive.digest(temporary);guard a.sha==b.sha,expected==nil || b.sha==expected else{throw HouseError.message("Snapshot copy did not verify.")};let handle=try FileHandle(forWritingTo:temporary);try handle.synchronize();try handle.close();try Task.checkCancellation();try FileManager.default.moveItem(at:temporary,to:url)}
      catch {try? FileManager.default.removeItem(at:temporary);operationError=error}
    }
    if let coordinationError {throw coordinationError};if let operationError {throw operationError}
  }
  static func write(house:House,repo:Repository,folder:URL)throws->SnapshotRevision {
    try house.validate();let base=root(folder)
    for name in ["assets","metadata","revisions"] {try FileManager.default.createDirectory(at:base.appendingPathComponent(name),withIntermediateDirectories:true)}
    for key in house.assets.sorted() {
      try Task.checkCancellation();guard safe(key) else{throw HouseError.message("Invalid original asset identity.")}
      let source=try repo.assetURL(key),destination=base.appendingPathComponent("assets").appendingPathComponent(key)
      let expected=String(key.prefix(64));guard try StreamingArchive.digest(source).sha==expected else{throw HouseError.message("An original failed its checksum; no snapshot revision was committed.")}
      if FileManager.default.fileExists(atPath:destination.path) {
        guard try StreamingArchive.digest(destination).sha==expected else{throw HouseError.message("An existing snapshot asset is incomplete or corrupt. Local originals are intact; choose another snapshot folder.")}
      } else {try publish(source:source,destination:destination,expected:expected)}
    }
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(house)
    guard data.count<=100_000_000 else{throw HouseError.message("Snapshot metadata exceeds its restore budget.")}
    let key=hash(data)+".json",destination=base.appendingPathComponent("metadata").appendingPathComponent(key)
    let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:temporary)}
    if !FileManager.default.fileExists(atPath:destination.path) {try data.write(to:temporary,options:.atomic);try publish(source:temporary,destination:destination,expected:String(key.prefix(64)))}
    else {guard try StreamingArchive.digest(destination).sha==String(key.prefix(64)) else{throw HouseError.message("Existing snapshot metadata is incomplete or corrupt.")}}
    let revision=SnapshotRevision(projectID:house.id,name:house.name,revision:house.revision,metadata:key,assets:house.assets.sorted())
    try encoder.encode(revision).write(to:temporary,options:.atomic)
    // The small revision record is the commit point; assets/metadata precede it.
    try publish(source:temporary,destination:base.appendingPathComponent("revisions").appendingPathComponent(revision.id.uuidString+".json"))
    return revision
  }
  static func catalog(folder:URL)throws->[SnapshotRevision] {
    let directory=root(folder).appendingPathComponent("revisions")
    guard FileManager.default.fileExists(atPath:directory.path) else{return []}
    let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey]).filter{$0.pathExtension=="json"}
    guard files.count<=10000 else{throw HouseError.message("Snapshot catalog exceeds its entry budget.")}
    return files.compactMap {url in
      guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=10_000_000,let data=try? Data(contentsOf:url),let record=try? JSONDecoder().decode(SnapshotRevision.self,from:data),record.format=="HouseXraySnapshot",record.version==1,record.id.uuidString==url.deletingPathExtension().lastPathComponent,safe(record.metadata) else{return nil}
      return record
    }.sorted{$0.date>$1.date}
  }
  static func read(_ url:URL,limit:Int)throws->Data {
    let coordinator=NSFileCoordinator(filePresenter:nil);var coordinationError:NSError?,operationError:Error?,result:Data?
    coordinator.coordinate(readingItemAt:url,options:[],error:&coordinationError){source in
      do {let values=try source.resourceValues(forKeys:[.fileSizeKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey]);if values.isUbiquitousItem==true && values.ubiquitousItemDownloadingStatus != .current {try FileManager.default.startDownloadingUbiquitousItem(at:source);throw HouseError.message("Snapshot files are still downloading. Retry after Files finishes syncing.")};guard let size=values.fileSize,size<=limit else{throw HouseError.message("Snapshot object exceeds its read budget.")};result=try Data(contentsOf:source)}catch{operationError=error}
    }
    if let coordinationError {throw coordinationError};if let operationError {throw operationError};guard let result else{throw HouseError.message("Snapshot object is unavailable.")};return result
  }
  static func restore(_ revision:SnapshotRevision,repo:Repository,folder:URL)throws->House {
    guard revision.format=="HouseXraySnapshot",revision.version==1,safe(revision.metadata),revision.assets.count<=160000,revision.assets.allSatisfy({safe($0)}) else{throw HouseError.message("Unsupported snapshot revision.")}
    let base=root(folder),data=try read(base.appendingPathComponent("metadata").appendingPathComponent(revision.metadata),limit:100_000_000)
    guard hash(data)==String(revision.metadata.prefix(64)) else{throw HouseError.message("Snapshot metadata checksum mismatch.")}
    var house=try JSONDecoder().decode(House.self,from:data);try house.validate()
    guard house.id==revision.projectID,house.revision==revision.revision,house.assets==Set(revision.assets) else{throw HouseError.message("Snapshot revision and metadata disagree.")}
    for key in house.assets.sorted() {
      try Task.checkCancellation();let source=base.appendingPathComponent("assets").appendingPathComponent(key)
      let destination=try repo.assetURL(key),temporary=repo.root.appendingPathComponent(UUID().uuidString+".restore")
      let coordinator=NSFileCoordinator(filePresenter:nil);var coordinationError:NSError?,operationError:Error?
      coordinator.coordinate(readingItemAt:source,options:[],error:&coordinationError){url in
        do {
          let values=try url.resourceValues(forKeys:[.fileSizeKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey])
          if values.isUbiquitousItem==true && values.ubiquitousItemDownloadingStatus != .current {try FileManager.default.startDownloadingUbiquitousItem(at:url);throw HouseError.message("Snapshot originals are downloading. Retry after Files finishes syncing.")}
          guard let size=values.fileSize,size<=512_000_000,repo.freeBytes()>Int64(size)+64_000_000 else{throw HouseError.message("Insufficient free space or unsupported individual snapshot asset size.")}
          FileManager.default.createFile(atPath:temporary.path,contents:nil)
          let output=try FileHandle(forWritingTo:temporary);defer{try? output.close()}
          let copied=try StreamingArchive.digest(url,copyTo:output);try output.synchronize();try output.close()
          guard copied.sha==String(key.prefix(64)) else{throw HouseError.message("Snapshot asset checksum mismatch. Restore was not committed.")}
          if FileManager.default.fileExists(atPath:destination.path) {guard try StreamingArchive.digest(destination).sha==copied.sha else{throw HouseError.message("Existing local original is corrupt; it was preserved for recovery.")};try FileManager.default.removeItem(at:temporary)}
          else {try FileManager.default.moveItem(at:temporary,to:destination)}
        } catch {try? FileManager.default.removeItem(at:temporary);operationError=error}
      }
      if let coordinationError {throw coordinationError};if let operationError {throw operationError}
    }
    house.id=UUID();house.name += " · restored";house.revision=0
    return house
  }
}
