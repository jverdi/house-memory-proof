import Foundation

enum DurableFiles {
  static func write(_ data:Data,to url:URL)throws {
    try data.write(to:url,options:.atomic)
    let file=try FileHandle(forWritingTo:url);defer{try? file.close()};try file.synchronize()
  }
}
