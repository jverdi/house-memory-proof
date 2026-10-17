import CryptoKit
import Foundation

// Stored ZIP64, with bounded 1 MiB buffers. Compatible with ordinary ZIP utilities.
// Originals are never decoded into images and never accumulated in memory.
enum StreamingArchive {
  struct Item {
    var name: String
    var url: URL
  }
  struct Record {
    var name: String
    var offset: UInt64
    var size: UInt64
    var crc: UInt32
  }
  struct Digest {
    var size: UInt64
    var crc: UInt32
    var sha: String
  }
  static let block = 1_048_576
  static func digest(
    _ url: URL, offset: UInt64 = 0, count: UInt64? = nil, copyTo: FileHandle? = nil
  ) throws -> Digest {
    let f = try FileHandle(forReadingFrom: url)
    defer { try? f.close() }
    try f.seek(toOffset: offset)
    var remaining = count ?? UInt64.max
    var size: UInt64 = 0
    var crc: UInt32 = 0xffff_ffff
    var sha = SHA256()
    while remaining > 0 {
      try Task.checkCancellation()
      let bytes = try f.read(upToCount: Int(min(UInt64(block), remaining))) ?? Data()
      if bytes.isEmpty { break }
      for b in bytes { crc = StoredZip.crcTable[Int((crc ^ UInt32(b)) & 255)] ^ (crc >> 8) }
      sha.update(data: bytes)
      try copyTo?.write(contentsOf: bytes)
      size += UInt64(bytes.count)
      remaining -= UInt64(bytes.count)
    }
    if let count, size != count { throw HouseError.message("Truncated archive entry.") }
    return Digest(
      size: size, crc: crc ^ 0xffff_ffff,
      sha: sha.finalize().map { String(format: "%02x", $0) }.joined())
  }
  static func write(_ items: [Item], to url: URL) throws -> [String: String] {
    guard items.count <= 160_000 else {
      throw HouseError.message("Archive exceeds 160,000 entries.")
    }
    let partial = url.appendingPathExtension("partial")
    FileManager.default.createFile(atPath: partial.path, contents: nil)
    let f = try FileHandle(forWritingTo: partial)
    var success = false
    defer {
      try? f.close()
      if !success { try? FileManager.default.removeItem(at: partial) }
    }
    var central = Data()
    var hashes: [String: String] = [:]
    var offset: UInt64 = 0
    for item in items {
      try Task.checkCancellation()
      let d = try digest(item.url)
      let name = Data(item.name.utf8)
      guard name.count < 65535, d.size < UInt64(512) * 1024 * 1024 * 1024 else {
        throw HouseError.message("Archive entry exceeds its size budget.")
      }
      var extra = Data()
      extra.le(UInt16(1))
      extra.le(UInt16(16))
      extra.le(d.size)
      extra.le(d.size)
      var h = Data()
      h.le(UInt32(0x0403_4b50))
      h.le(UInt16(45))
      h.le(UInt16(0x800))
      h.le(UInt16(0))
      h.le(UInt16(0))
      h.le(UInt16(0))
      h.le(d.crc)
      h.le(UInt32.max)
      h.le(UInt32.max)
      h.le(UInt16(name.count))
      h.le(UInt16(extra.count))
      h.append(name)
      h.append(extra)
      try f.write(contentsOf: h)
      let copied = try digest(item.url, copyTo: f)
      guard copied.sha == d.sha, copied.size == d.size else {
        throw HouseError.message("Source changed during backup; no archive was published.")
      }
      central.le(UInt32(0x0201_4b50))
      central.le(UInt16(45))
      central.le(UInt16(45))
      central.le(UInt16(0x800))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(d.crc)
      central.le(UInt32.max)
      central.le(UInt32.max)
      central.le(UInt16(name.count))
      central.le(UInt16(28))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt32(0))
      central.le(UInt32.max)
      central.append(name)
      central.le(UInt16(1))
      central.le(UInt16(24))
      central.le(d.size)
      central.le(d.size)
      central.le(offset)
      hashes[item.name] = d.sha
      offset += UInt64(h.count) + d.size
    }
    try f.write(contentsOf: central)
    let zipEnd = offset + UInt64(central.count)
    var end = Data()
    end.le(UInt32(0x0606_4b50))
    end.le(UInt64(44))
    end.le(UInt16(45))
    end.le(UInt16(45))
    end.le(UInt32(0))
    end.le(UInt32(0))
    end.le(UInt64(items.count))
    end.le(UInt64(items.count))
    end.le(UInt64(central.count))
    end.le(offset)
    end.le(UInt32(0x0706_4b50))
    end.le(UInt32(0))
    end.le(zipEnd)
    end.le(UInt32(1))
    end.le(UInt32(0x0605_4b50))
    end.le(UInt16(0))
    end.le(UInt16(0))
    end.le(UInt16.max)
    end.le(UInt16.max)
    end.le(UInt32.max)
    end.le(UInt32.max)
    end.le(UInt16(0))
    try f.write(contentsOf: end)
    try f.synchronize()
    try f.close()
    try FileManager.default.moveItem(at: partial, to: url)
    success = true
    return hashes
  }
  static func index(_ url: URL) throws -> [String: Record] {
    let f = try FileHandle(forReadingFrom: url)
    defer { try? f.close() }
    let length = try f.seekToEnd()
    guard length >= 22, length < UInt64(512) * 1024 * 1024 * 1024 else {
      throw HouseError.message("Archive length is invalid or exceeds 512 GB.")
    }
    try f.seek(toOffset: length - 22)
    let end = try exact(f, 22)
    guard end.uint32(0) == 0x0605_4b50, end.uint16(20) == 0 else {
      throw HouseError.message("Incomplete or unsupported archive footer.")
    }
    var offset: UInt64 = 0
    var result: [String: Record] = [:]
    while offset + 30 <= length {
      try f.seek(toOffset: offset)
      let h = try exact(f, 30)
      if h.uint32(0) == 0x0201_4b50 { break }
      guard h.uint32(0) == 0x0403_4b50, h.uint16(6) & 9 == 0, h.uint16(8) == 0 else {
        throw HouseError.message("Only complete, uncompressed House Xray archives are supported.")
      }
      let nl = Int(h.uint16(26))
      let el = Int(h.uint16(28))
      let n = try exact(f, nl)
      let e = try exact(f, el)
      guard let name = String(data: n, encoding: .utf8), !name.isEmpty, !name.hasPrefix("/"),
        !name.contains("\\"), !name.split(separator: "/").contains(".."), result[name] == nil
      else { throw HouseError.message("Unsafe or duplicate archive entry.") }
      var size = UInt64(h.uint32(22))
      var compressed = UInt64(h.uint32(18))
      if size == UInt32.max || compressed == UInt32.max {
        var i = 0
        var found = false
        while i + 4 <= e.count {
          let kind = e.uint16(i)
          let len = Int(e.uint16(i + 2))
          guard i + 4 + len <= e.count else { throw HouseError.message("Invalid ZIP64 header.") }
          if kind == 1, len >= 16 {
            size = e.uint64(i + 4)
            compressed = e.uint64(i + 12)
            found = true
            break
          }
          i += 4 + len
        }
        guard found else { throw HouseError.message("Missing ZIP64 sizes.") }
      }
      let start = offset + UInt64(30 + nl + el)
      guard size == compressed, start <= length, size <= length - start, result.count < 160000
      else { throw HouseError.message("Truncated or oversized archive index.") }
      result[name] = Record(name: name, offset: start, size: size, crc: h.uint32(14))
      offset = start + size
    }
    guard !result.isEmpty else { throw HouseError.message("Archive contains no entries.") }
    return result
  }
  static func exact(_ f: FileHandle, _ count: Int) throws -> Data {
    let d = try f.read(upToCount: count) ?? Data()
    guard d.count == count else { throw HouseError.message("Truncated archive header.") }
    return d
  }
  static func read(_ record: Record, from url: URL, limit: UInt64 = 100_000_000) throws -> Data {
    guard record.size <= limit else {
      throw HouseError.message("Project metadata exceeds the 100 MB admission budget.")
    }
    let f = try FileHandle(forReadingFrom: url)
    defer { try? f.close() }
    try f.seek(toOffset: record.offset)
    let data = try exact(f, Int(record.size))
    guard StoredZip.crc(data) == record.crc else {
      throw HouseError.message("Archive checksum failed.")
    }
    return data
  }
  static func restore(_ url: URL, repo: Repository) throws -> House {
    let entries = try index(url)
    guard let m = entries["manifest.json"], let h = entries["house.json"] else {
      throw HouseError.message("Missing archive manifest or project.")
    }
    let manifest = try read(m, from: url)
    let data = try read(h, from: url)
    guard let object = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
      object["format"] as? String == "HouseXray", object["version"] as? Int == 1,
      let hashes = object["sha256"] as? [String: String],
      hashes["house.json"] == SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
    else { throw HouseError.message("Archive manifest identity failed.") }
    var house = try JSONDecoder().decode(House.self, from: data)
    try house.validate()
    let needed = try house.assets.reduce(UInt64(0)) { sum, key in
      guard let r = entries["assets/" + key], hashes[r.name] != nil else {
        throw HouseError.message("Archive is missing original evidence.")
      }
      return sum + r.size
    }
    guard UInt64(max(0, repo.freeBytes())) > needed + 200_000_000 else {
      throw HouseError.message("Not enough free space to restore original evidence.")
    }
    for key in house.assets.sorted() {
      let r = entries["assets/" + key]!
      let target = try repo.assetURL(key)
      let temporary = repo.root.appendingPathComponent(UUID().uuidString + ".restore")
      FileManager.default.createFile(atPath: temporary.path, contents: nil)
      let output = try FileHandle(forWritingTo: temporary)
      do {
        let digest = try digest(url, offset: r.offset, count: r.size, copyTo: output)
        try output.synchronize()
        try output.close()
        guard digest.crc == r.crc, digest.sha == hashes[r.name], key.hasPrefix(digest.sha + ".")
        else { throw HouseError.message("Original evidence checksum failed.") }
        if FileManager.default.fileExists(atPath: target.path) {
          let existing = try self.digest(target)
          guard existing.sha == digest.sha else {
            throw HouseError.message(
              "Existing original is corrupt; restore stopped without replacing it.")
          }
          try FileManager.default.removeItem(at: temporary)
        } else {
          try FileManager.default.moveItem(at: temporary, to: target)
        }
      } catch {
        try? output.close()
        try? FileManager.default.removeItem(at: temporary)
        throw error
      }
    }
    house.id = UUID()
    house.name += " · restored"
    house.revision = 0
    return house
  }
}
extension Data {
  func uint64(_ i: Int) -> UInt64 { UInt64(uint32(i)) | UInt64(uint32(i + 4)) << 32 }
}
