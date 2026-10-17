import Foundation

enum DurableFiles {
  static func read(_ url:URL,limit:Int)throws->Data {
    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize
    guard let size,size>=0,size<=limit else{throw HouseError.message("This file exceeds the import memory budget. Use a smaller source file; originals have not been changed.")}
    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
    let bytes=try file.read(upToCount:limit+1) ?? Data()
    guard bytes.count<=limit,bytes.count==size else{throw HouseError.message("Source grew beyond its import budget while reading.")};return bytes
  }
  static func write(_ data:Data,to url:URL)throws {
    try data.write(to:url,options:.atomic)
    let file=try FileHandle(forWritingTo:url);defer{try? file.close()};try file.synchronize()
  }
}
