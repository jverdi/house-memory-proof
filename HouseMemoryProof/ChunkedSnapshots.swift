import Foundation
import CryptoKit

// Immutable 16 MiB objects pack small originals and split large ones. The
// manifest is published before its discoverable revision; partial arrival is
// still possible, so restoration verifies every referenced byte again.
enum ChunkedSnapshots {
  static let chunkLimit=16*1024*1024
  struct Slice:Codable,Equatable {var chunk:String;var offset:Int;var length:Int}
  struct Asset:Codable,Equatable {var key:String;var bytes:UInt64;var slices:[Slice]}
  struct Manifest:Codable {
    var version=2;var projectID:UUID;var metadata:String;var deviceID:UUID
    var parentMetadata:String?;var assets:[Asset]
  }
  static func encode<T:Encodable>(_ value:T)throws->Data {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value)
  }
  static func object(_ bytes:Data,kind:String,extension ext:String,base:URL)throws->String {
    let key=IncrementalSnapshots.hash(bytes)+"."+ext,destination=base.appendingPathComponent(kind).appendingPathComponent(key)
    if FileManager.default.fileExists(atPath:destination.path) {
      guard try IncrementalSnapshots.read(destination,limit:max(chunkLimit,bytes.count))==bytes else{throw HouseError.message("An existing snapshot object is incomplete or corrupt. Local originals remain intact.")}
    } else {
      let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer{try? FileManager.default.removeItem(at:temporary)}
      try bytes.write(to:temporary,options:.atomic)
      try IncrementalSnapshots.publish(source:temporary,destination:destination,expected:String(key.prefix(64)))
    }
    return key
  }
  static func manifest(_ revision:SnapshotRevision,base:URL)throws->Manifest {
    guard revision.format=="HouseXraySnapshot",revision.version==2,IncrementalSnapshots.safe(revision.metadata),
      revision.assets.count<=160000,Set(revision.assets).count==revision.assets.count,revision.assets.allSatisfy({IncrementalSnapshots.safe($0)}),
      let key=revision.chunkManifest,IncrementalSnapshots.safe(key) else{throw HouseError.message("Unsupported chunked snapshot revision.")}
    let data=try IncrementalSnapshots.read(base.appendingPathComponent("manifests").appendingPathComponent(key),limit:32_000_000)
    guard IncrementalSnapshots.hash(data)==String(key.prefix(64)) else{throw HouseError.message("Snapshot chunk manifest checksum mismatch.")}
    let m=try JSONDecoder().decode(Manifest.self,from:data)
    guard m.version==2,m.projectID==revision.projectID,m.metadata==revision.metadata,m.assets.count==revision.assets.count,
      m.assets.map({$0.key}).sorted()==revision.assets.sorted() else{throw HouseError.message("Snapshot chunk manifest and revision disagree.")}
    var references=0
    for asset in m.assets {
      guard asset.bytes<=512*1024*1024*1024 else{throw HouseError.message("Snapshot original exceeds its size budget.")}
      var total:UInt64=0
      for slice in asset.slices {
        references+=1
        guard references<=1_000_000,IncrementalSnapshots.safe(slice.chunk),slice.offset>=0,slice.length>0,
          slice.length<=chunkLimit,slice.offset<=chunkLimit-slice.length else{throw HouseError.message("Invalid snapshot chunk range.")}
        total+=UInt64(slice.length)
      }
      guard total==asset.bytes else{throw HouseError.message("Snapshot original length disagrees with its chunks.")}
    }
    return m
  }
  static func chunk(_ key:String,base:URL)throws->Data {
    let data=try IncrementalSnapshots.read(base.appendingPathComponent("chunks").appendingPathComponent(key),limit:chunkLimit)
    guard IncrementalSnapshots.hash(data)==String(key.prefix(64)) else{throw HouseError.message("Snapshot chunk checksum mismatch. Restore was not committed.")}
    return data
  }
  static func verify(_ m:Manifest,base:URL)throws {
    var key:String?,bytes=Data()
    for asset in m.assets {
      var hash=SHA256(),count:UInt64=0
      for slice in asset.slices {
        try Task.checkCancellation()
        if key != slice.chunk {bytes=try chunk(slice.chunk,base:base);key=slice.chunk}
        guard slice.offset>=0,slice.length>0,slice.offset<=bytes.count-slice.length else{throw HouseError.message("Snapshot chunk is truncated.")}
        hash.update(data:bytes.subdata(in:slice.offset..<(slice.offset+slice.length)));count+=UInt64(slice.length)
      }
      guard count==asset.bytes,hash.finalize().map({String(format:"%02x",$0)}).joined()==String(asset.key.prefix(64)) else{throw HouseError.message("Snapshot chunks do not reproduce their original.")}
    }
  }
  static func write(house:House,repo:Repository,folder:URL,deviceID:UUID,checkpoint:((String)throws->Void)?=nil)throws->SnapshotRevision {
    try house.validate();let base=IncrementalSnapshots.root(folder)
    for name in ["chunks","manifests","metadata","revisions"] {try FileManager.default.createDirectory(at:base.appendingPathComponent(name),withIntermediateDirectories:true)}
    let data=try encode(house)
    guard data.count<=100_000_000 else{throw HouseError.message("Snapshot metadata exceeds its restore budget.")}
    let metadata=IncrementalSnapshots.hash(data)+".json"
    let id=IncrementalSnapshots.revisionID(metadata:"chunks-v2:"+metadata)
    let recordURL=base.appendingPathComponent("revisions").appendingPathComponent(id.uuidString+".json")
    func existing()throws->SnapshotRevision? {
      guard FileManager.default.fileExists(atPath:recordURL.path) else{return nil}
      let record=try JSONDecoder().decode(SnapshotRevision.self,from:IncrementalSnapshots.read(recordURL,limit:10_000_000))
      guard record.id==id,record.projectID==house.id,record.name==house.name,record.revision==house.revision,record.metadata==metadata,record.assets==house.assets.sorted() else{throw HouseError.message("Snapshot revision conflicts with its content identity.")}
      let m=try manifest(record,base:base);try verify(m,base:base)
      guard try IncrementalSnapshots.read(base.appendingPathComponent("metadata").appendingPathComponent(metadata),limit:100_000_000)==data else{throw HouseError.message("Snapshot metadata failed readback.")}
      return record
    }
    if let result=try existing(){return result}
    // Reuse whole immutable asset references from one parent. Adding a small
    // original never repacks all the old assets into different chunk hashes.
    let catalog=try IncrementalSnapshots.inspectCatalog(folder:folder)
    let parent=catalog.revisions.first{$0.projectID==house.id && $0.version==2}
    let prior=try parent.map{try manifest($0,base:base)}
    var known:[String:Asset]=[:]
    for item in prior?.assets ?? [] {known[item.key]=item}
    var assets:[Asset]=[],buffer=Data(),pending:[(Int,Int,Int)]=[]
    func flush()throws {
      guard !buffer.isEmpty else{return}
      let key=try object(buffer,kind:"chunks",extension:"chunk",base:base)
      for (asset,offset,length) in pending {assets[asset].slices.append(Slice(chunk:key,offset:offset,length:length))}
      buffer.removeAll(keepingCapacity:true);pending=[];try checkpoint?("chunk-verified")
    }
    for key in house.assets.sorted() {
      try Task.checkCancellation()
      guard IncrementalSnapshots.safe(key) else{throw HouseError.message("Invalid original identity.")}
      let source=try repo.assetURL(key),digest=try StreamingArchive.digest(source)
      guard digest.sha==String(key.prefix(64)),digest.size<=512*1024*1024*1024 else{throw HouseError.message("A local original failed snapshot verification.")}
      if let reused=known[key],reused.bytes==digest.size {assets.append(reused);continue}
      let index=assets.count;assets.append(Asset(key:key,bytes:digest.size,slices:[]))
      let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
      var count:UInt64=0,hash=SHA256()
      while let bytes=try input.read(upToCount:min(StreamingArchive.block,chunkLimit-buffer.count)),!bytes.isEmpty {
        try Task.checkCancellation();hash.update(data:bytes);count+=UInt64(bytes.count)
        pending.append((index,buffer.count,bytes.count));buffer.append(bytes)
        if buffer.count==chunkLimit {try flush()}
      }
      try input.close()
      guard count==digest.size,hash.finalize().map({String(format:"%02x",$0)}).joined()==digest.sha else{throw HouseError.message("Original changed during snapshot; no revision was published.")}
      try checkpoint?("asset-verified")
    }
    try flush()
    let m=Manifest(projectID:house.id,metadata:metadata,deviceID:deviceID,parentMetadata:parent?.metadata,assets:assets)
    try verify(m,base:base)
    _=try object(data,kind:"metadata",extension:"json",base:base);try checkpoint?("metadata-verified")
    let manifestData=try encode(m)
    guard manifestData.count<=32_000_000 else{throw HouseError.message("Snapshot chunk index exceeds its restore budget.")}
    let manifestKey=try object(manifestData,kind:"manifests",extension:"json",base:base)
    let revision=SnapshotRevision(version:2,id:id,projectID:house.id,name:house.name,revision:house.revision,metadata:metadata,assets:house.assets.sorted(),chunkManifest:manifestKey)
    let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:temporary)}
    try encode(revision).write(to:temporary,options:.atomic)
    try checkpoint?("manifest-verified")
    do {try IncrementalSnapshots.publish(source:temporary,destination:recordURL)}
    catch {let errorToReturn=error;if let result=try existing(){return result};throw errorToReturn}
    try checkpoint?("revision-committed");return revision
  }
  struct TransferSummary {
    var total=0,uploaded=0,waiting=0,uploading=0,unknown=0,unavailable=0,conflicts=0,failed=0
    var message:String {
      if unavailable+conflicts+failed>0 {return "Snapshot needs attention: \(unavailable) unavailable files, \(conflicts) conflicts, \(failed) transfer errors. Local originals remain intact."}
      if total>0 && uploaded==total {return "iCloud reports all \(total) snapshot files uploaded. A restore on another destination or device is still required to verify recovery."}
      return "\(uploaded)/\(total) files reported uploaded · \(uploading) uploading · \(waiting) waiting · \(unknown) with no provider status. Local readback does not verify remote recovery."
    }
  }
  static func transfers(_ revision:SnapshotRevision,folder:URL)throws->TransferSummary {
    guard revision.format=="HouseXraySnapshot",[1,2].contains(revision.version),IncrementalSnapshots.safe(revision.metadata),revision.assets.count<=160000,revision.assets.allSatisfy({IncrementalSnapshots.safe($0)}) else{throw HouseError.message("Unsupported snapshot transfer record.")}
    let base=IncrementalSnapshots.root(folder)
    var urls=[base.appendingPathComponent("revisions").appendingPathComponent(revision.id.uuidString+".json"),base.appendingPathComponent("metadata").appendingPathComponent(revision.metadata)]
    if revision.version==2 {
      let m=try manifest(revision,base:base)
      urls.append(base.appendingPathComponent("manifests").appendingPathComponent(revision.chunkManifest!))
      urls += Set(m.assets.flatMap{$0.slices.map{$0.chunk}}).sorted().map{base.appendingPathComponent("chunks").appendingPathComponent($0)}
    } else {urls += revision.assets.map{base.appendingPathComponent("assets").appendingPathComponent($0)}}
    var result=TransferSummary();result.total=urls.count
    for url in urls {
      try Task.checkCancellation()
      do {
        let values=try url.resourceValues(forKeys:[.isUbiquitousItemKey,.ubiquitousItemIsUploadedKey,.ubiquitousItemIsUploadingKey,.ubiquitousItemHasUnresolvedConflictsKey,.ubiquitousItemUploadingErrorKey,.ubiquitousItemDownloadingErrorKey])
        if values.ubiquitousItemHasUnresolvedConflicts==true {result.conflicts+=1}
        else if values.ubiquitousItemUploadingError != nil || values.ubiquitousItemDownloadingError != nil {result.failed+=1}
        else if values.isUbiquitousItem != true {result.unknown+=1}
        else if values.ubiquitousItemIsUploaded==true {result.uploaded+=1}
        else if values.ubiquitousItemIsUploading==true {result.uploading+=1}
        else {result.waiting+=1}
      } catch {result.unavailable+=1}
    }
    return result
  }
  static func restore(_ revision:SnapshotRevision,repo:Repository,folder:URL)throws->House {
    let base=IncrementalSnapshots.root(folder),m=try manifest(revision,base:base)
    let data=try IncrementalSnapshots.read(base.appendingPathComponent("metadata").appendingPathComponent(revision.metadata),limit:100_000_000)
    guard IncrementalSnapshots.hash(data)==String(revision.metadata.prefix(64)) else{throw HouseError.message("Snapshot metadata checksum mismatch.")}
    var house=try JSONDecoder().decode(House.self,from:data);try house.validate()
    guard house.id==revision.projectID,house.revision==revision.revision,house.assets==Set(revision.assets) else{throw HouseError.message("Snapshot metadata and revision disagree.")}
    var cachedKey:String?,cached=Data()
    for asset in m.assets {
      try Task.checkCancellation()
      guard repo.freeBytes()>Int64(asset.bytes)+64_000_000 else{throw HouseError.message("Snapshot restore needs more free storage. Local projects remain intact.")}
      let destination=try repo.assetURL(asset.key),temporary=repo.root.appendingPathComponent(UUID().uuidString+".restore")
      defer{try? FileManager.default.removeItem(at:temporary)}
      FileManager.default.createFile(atPath:temporary.path,contents:nil)
      let output=try FileHandle(forWritingTo:temporary);defer{try? output.close()}
      var hash=SHA256()
      for slice in asset.slices {
        try Task.checkCancellation()
        if cachedKey != slice.chunk {cached=try chunk(slice.chunk,base:base);cachedKey=slice.chunk}
        guard slice.offset+slice.length<=cached.count else{throw HouseError.message("Snapshot chunk is truncated.")}
        let bytes=cached.subdata(in:slice.offset..<(slice.offset+slice.length))
        hash.update(data:bytes);try output.write(contentsOf:bytes)
      }
      try output.synchronize();try output.close()
      guard hash.finalize().map({String(format:"%02x",$0)}).joined()==String(asset.key.prefix(64)) else{throw HouseError.message("Restored original checksum mismatch.")}
      if FileManager.default.fileExists(atPath:destination.path) {
        guard try StreamingArchive.digest(destination).sha==String(asset.key.prefix(64)) else{throw HouseError.message("Existing local original is corrupt; it was preserved for recovery.")}
      } else{try FileManager.default.moveItem(at:temporary,to:destination)}
    }
    house.id=UUID();house.name += " · restored";house.revision=0;return house
  }
}
