import Foundation
import CryptoKit

enum FusionCheckpoint {
  struct Record:Codable {var schema=1;var fingerprint:String;var nextFrame:Int;var file:String;var sha256:String}
  static func load(repo:Repository,segment:Segment,fingerprint:String,frameCount:Int)throws->(UnsafeMutableRawPointer,Int)? {
    guard let bytes=try repo.jobData("surface-"+segment.id.uuidString),let record=try? JSONDecoder().decode(Record.self,from:bytes),record.schema==1,record.fingerprint==fingerprint,record.nextFrame>=0,record.nextFrame<=frameCount,UUID(uuidString:record.file) != nil else{return nil}
    let url=repo.root.appendingPathComponent("fusion-checkpoints").appendingPathComponent(record.file)
    guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=20_000_000 else{return nil}
    let data=try Data(contentsOf:url)
    guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==record.sha256 else{return nil}
    let core=data.withUnsafeBytes{hx_surface_restore($0.bindMemory(to:UInt8.self).baseAddress,UInt32(data.count))}
    guard let core else{return nil};return (core,record.nextFrame)
  }
  static func save(core:UnsafeMutableRawPointer,repo:Repository,segment:Segment,fingerprint:String,nextFrame:Int)throws {
    let size=hx_surface_checkpoint(core,nil,0)
    guard size>=32,size<=20_000_000 else{throw HouseError.message("Surface checkpoint exceeds its memory budget.")}
    guard repo.freeBytes()>Int64(size)+64_000_000 else{throw HouseError.message("Insufficient free space for a safe reconstruction checkpoint. Existing checkpoints and originals are preserved.")}
    var data=Data(count:Int(size))
    let copied=data.withUnsafeMutableBytes{hx_surface_checkpoint(core,$0.bindMemory(to:UInt8.self).baseAddress,size)}
    guard copied==size else{throw HouseError.message("Surface checkpoint could not be completed.")}
    let folder=repo.root.appendingPathComponent("fusion-checkpoints",isDirectory:true)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let record=Record(fingerprint:fingerprint,nextFrame:nextFrame,file:UUID().uuidString,sha256:SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined())
    let oldData=try? repo.jobData("surface-"+segment.id.uuidString)
    let old=oldData.flatMap{try? JSONDecoder().decode(Record.self,from:$0)}
    let url=folder.appendingPathComponent(record.file)
    try data.write(to:url,options:.atomic)
    let handle=try FileHandle(forWritingTo:url);defer{try? handle.close()};try handle.synchronize()
    do {try repo.job("surface-"+segment.id.uuidString,state:"checkpoint",data:JSONEncoder().encode(record))}
    catch {try? FileManager.default.removeItem(at:url);throw error}
    if let old,UUID(uuidString:old.file) != nil,old.file != record.file {try? FileManager.default.removeItem(at:folder.appendingPathComponent(old.file))}
  }
}
