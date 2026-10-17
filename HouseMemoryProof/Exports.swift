import AVFoundation
import CryptoKit
import Foundation
import SceneKit
import UIKit

extension Data {
  mutating func le<T: FixedWidthInteger>(_ x: T) {
    var v = x.littleEndian
    Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
  }
  mutating func float(_ x: Float) { le(x.bitPattern) }
  func uint16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
  func uint32(_ i: Int) -> UInt32 { UInt32(uint16(i)) | UInt32(uint16(i + 2)) << 16 }
}
enum StoredZip {
  static let crcTable: [UInt32] = (0..<256).map { v in
    var c = UInt32(v)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
  }
  static func crc(_ data: Data) -> UInt32 {
    var c: UInt32 = 0xffff_ffff
    for b in data { c = crcTable[Int((c ^ UInt32(b)) & 255)] ^ (c >> 8) }
    return c ^ 0xffff_ffff
  }
  struct Entry {
    var name: String
    var data: Data
  }
  static func write(_ entries: [Entry], to url: URL, aligned: Bool = false) throws {
    guard entries.count < 65535 else { throw HouseError.message("Too many archive entries.") }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let f = try FileHandle(forWritingTo: url)
    defer { try? f.close() }
    var central = Data()
    var offset: UInt32 = 0
    for e in entries {
      let name = Data(e.name.utf8)
      guard name.count < 65535, e.data.count < 1_000_000_000 else {
        throw HouseError.message("Archive entry is too large.")
      }
      let remainder = (Int(offset) + 30 + name.count) % 64
      var padding = aligned ? (64 - remainder) % 64 : 0
      if padding > 0 && padding < 4 { padding += 64 }
      var extra = Data()
      if padding >= 4 {
        extra.le(UInt16(0x1986))
        extra.le(UInt16(padding - 4))
        extra.append(Data(repeating: 0, count: padding - 4))
      }
      let checksum = crc(e.data)
      let size = UInt32(e.data.count)
      var h = Data()
      h.le(UInt32(0x0403_4b50))
      h.le(UInt16(20))
      h.le(UInt16(0x800))
      h.le(UInt16(0))
      h.le(UInt16(0))
      h.le(UInt16(0))
      h.le(checksum)
      h.le(size)
      h.le(size)
      h.le(UInt16(name.count))
      h.le(UInt16(extra.count))
      h.append(name)
      h.append(extra)
      try f.write(contentsOf: h)
      try f.write(contentsOf: e.data)
      central.le(UInt32(0x0201_4b50))
      central.le(UInt16(20))
      central.le(UInt16(20))
      central.le(UInt16(0x800))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(checksum)
      central.le(size)
      central.le(size)
      central.le(UInt16(name.count))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt16(0))
      central.le(UInt32(0))
      central.le(offset)
      central.append(name)
      guard UInt64(offset) + UInt64(h.count) + UInt64(size) < UInt64(UInt32.max) else {
        throw HouseError.message(
          "This build supports archives below 4 GB. Export smaller room projects.")
      }
      offset += UInt32(h.count) + size
    }
    try f.write(contentsOf: central)
    var end = Data()
    end.le(UInt32(0x0605_4b50))
    end.le(UInt16(0))
    end.le(UInt16(0))
    end.le(UInt16(entries.count))
    end.le(UInt16(entries.count))
    end.le(UInt32(central.count))
    end.le(offset)
    end.le(UInt16(0))
    try f.write(contentsOf: end)
    try f.synchronize()
  }
  static func read(_ url: URL) throws -> [Entry] {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size < 700_000_000 else {
      throw HouseError.message("Archive restore is limited to 700 MB in this build.")
    }
    let d = try Data(contentsOf: url, options: .mappedIfSafe)
    var i = 0
    var entries: [Entry] = []
    var names = Set<String>()
    while i + 30 <= d.count && d.uint32(i) == 0x0403_4b50 {
      let flags = d.uint16(i + 6)
      let method = d.uint16(i + 8)
      let crc = d.uint32(i + 14)
      let size = Int(d.uint32(i + 18))
      let raw = Int(d.uint32(i + 22))
      let nl = Int(d.uint16(i + 26))
      let el = Int(d.uint16(i + 28))
      let start = i + 30 + nl + el
      guard method == 0, flags & 9 == 0, size == raw, size <= 512 * 1024 * 1024, start <= d.count,
        size <= d.count - start, nl > 0, i + 30 + nl <= d.count
      else {
        throw HouseError.message(
          "Unsupported, truncated or compressed archive. Import a House Xray archive created by this app."
        )
      }
      guard let name = String(data: d[(i + 30)..<(i + 30 + nl)], encoding: .utf8),
        !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains(".."),
        names.insert(name).inserted
      else { throw HouseError.message("Unsafe or duplicate archive path.") }
      let bytes = d.subdata(in: start..<start + size)
      guard Self.crc(bytes) == crc else { throw HouseError.message("Archive checksum failed.") }
      entries.append(Entry(name: name, data: bytes))
      i = start + size
      if entries.count > 50000 { throw HouseError.message("Archive has too many entries.") }
    }
    guard !entries.isEmpty, i + 4 <= d.count, d.uint32(i) == 0x0201_4b50 else {
      throw HouseError.message("Incomplete archive.")
    }
    return entries
  }
}
enum Exporter {
  static func destination(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "exports", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + name)
  }
  static func canonicalFeatures(_ h: House, options: SceneOptions) -> [Feature] {
    SceneBuilder.features(h, options: options).map { f in
      var f = f
      if let sid = f.segmentID, let t = h.segments.first(where: { $0.id == sid })?.registration {
        f.mesh.vertices = f.mesh.vertices.map { t.apply($0) }
      }
      return f
    }
  }
  // Conservative staging estimate includes working copies and unique texture
  // bytes. It is an admission limit, not a measured device-memory guarantee.
  static func exportAssets(_ features:[Feature],textGeometry:Bool,
    root:URL=Repository.defaultRoot.appendingPathComponent("assets"),budget:Int64=256_000_000
  ) throws -> [String:URL] {
    var estimate:Int64=0,assets:[String:URL]=[:]
    for feature in features {
      try Task.checkCancellation()
      estimate += Int64(feature.mesh.vertices.count)*(textGeometry ? 320:72)
        + Int64(max(feature.mesh.triangles.count,feature.mesh.vertices.count))*(textGeometry ? 32:12)+4096
      if let key=feature.texture {
        guard feature.uv?.count==feature.mesh.vertices.count else{throw HouseError.message("A textured surface has no complete texture coordinates. Rebuild it before exporting.")}
        guard key.count<100,!key.contains("/"),!key.contains("\\"),!key.contains(".."),
          ["jpg","jpeg","png"].contains((key as NSString).pathExtension.lowercased())
        else{throw HouseError.message("An export texture has an invalid asset key.")}
        if assets[key]==nil {
          let url=root.appendingPathComponent(key)
          guard FileManager.default.fileExists(atPath:url.path) else{throw HouseError.message("An export texture is missing. Restore its original or rebuild the surface before exporting.")}
          let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
          guard values.isRegularFile==true,values.isSymbolicLink != true,let bytes=values.fileSize,bytes>0,bytes<=25_000_000 else{throw HouseError.message("An export texture exceeds the 25 MB asset budget or is not a regular file.")}
          estimate += Int64(bytes)*3;assets[key]=url
        }
      }
      guard estimate<=budget else{throw HouseError.message("This selection exceeds the model export memory budget. Select one room or stage and export again.")}
    }
    return assets
  }
  static func verifiedTexture(_ key:String,assets:[String:URL])throws->Data {
    try Task.checkCancellation()
    guard let url=assets[key] else{throw HouseError.message("An export texture was not admitted.")}
    let bytes=try DurableFiles.read(url,limit:25_000_000)
    let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
    guard key.hasPrefix(hash+".") else{throw HouseError.message("An export texture failed its checksum. Restore its original before exporting.")}
    return bytes
  }
  static func glb(_ h: House, options: SceneOptions) throws -> URL {
    let features = canonicalFeatures(h, options: options)
    guard !features.isEmpty else{throw HouseError.message("No geometry selected.")}
    let assets=try exportAssets(features,textGeometry:false)
    var bin = Data()
    var views: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var meshes: [[String: Any]] = []
    var nodes: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var images: [[String: Any]] = []
    var textures: [[String: Any]] = []
    var textureIDs: [String: Int] = [:]
    var featureNodes:[UUID:[UUID:[Int]]]=[:]
    for f in features where !f.mesh.vertices.isEmpty {
      try Task.checkCancellation()
      let posOffset = bin.count
      var lo = [Double](repeating: Double.infinity, count: 3)
      var hi = [Double](repeating: -Double.infinity, count: 3)
      for p in f.mesh.vertices {
        let v = [p.x, p.z, -p.y]
        for j in 0..<3 {
          bin.float(Float(v[j]))
          lo[j] = min(lo[j], v[j])
          hi[j] = max(hi[j], v[j])
        }
      }
      views.append([
        "buffer": 0, "byteOffset": posOffset, "byteLength": bin.count - posOffset, "target": 34962,
      ])
      let pi = accessors.count
      accessors.append([
        "bufferView": views.count - 1, "componentType": 5126, "count": f.mesh.vertices.count,
        "type": "VEC3", "min": lo, "max": hi,
      ])
      let indices =
        f.mesh.triangles.isEmpty ? Array(0..<Int32(f.mesh.vertices.count)) : f.mesh.triangles
      var attributes: [String: Int] = ["POSITION": pi]
      if let uv = f.uv, uv.count == f.mesh.vertices.count {
        let offset = bin.count
        for p in uv {
          bin.float(Float(p.u))
          bin.float(Float(p.v))
        }
        views.append([
          "buffer": 0, "byteOffset": offset, "byteLength": bin.count - offset, "target": 34962,
        ])
        attributes["TEXCOORD_0"] = accessors.count
        accessors.append([
          "bufferView": views.count - 1, "componentType": 5126, "count": uv.count, "type": "VEC2",
        ])
      }
      let idxOffset = bin.count
      for i in indices { bin.le(UInt32(i)) }
      views.append([
        "buffer": 0, "byteOffset": idxOffset, "byteLength": bin.count - idxOffset, "target": 34963,
      ])
      let ii = accessors.count
      accessors.append([
        "bufferView": views.count - 1, "componentType": 5125, "count": indices.count,
        "type": "SCALAR",
      ])
      let c = f.trade.hex
      materials.append([
        "name": f.trade.rawValue, "doubleSided": true,
        "pbrMetallicRoughness": [
          "baseColorFactor": [
            Double((c >> 16) & 255) / 255, Double((c >> 8) & 255) / 255, Double(c & 255) / 255, 1,
          ], "metallicFactor": 0, "roughnessFactor": 0.8,
        ],
      ])
      if let key = f.texture, attributes["TEXCOORD_0"] != nil {
        if textureIDs[key] == nil {
          let bytes=try verifiedTexture(key,assets:assets)
            let offset = bin.count
            bin.append(bytes)
            views.append(["buffer": 0, "byteOffset": offset, "byteLength": bytes.count])
            while bin.count % 4 != 0 { bin.append(0) }
            images.append([
              "bufferView": views.count - 1,
              "mimeType": (key as NSString).pathExtension.lowercased()=="png" ? "image/png" : "image/jpeg",
            ])
            textureIDs[key] = textures.count
            textures.append(["source": images.count - 1])
        }
        if let index = textureIDs[key] {
          materials[materials.count - 1]["pbrMetallicRoughness"] = [
            "baseColorFactor": [1, 1, 1, 1], "baseColorTexture": ["index": index],
            "metallicFactor": 0, "roughnessFactor": 0.8,
          ]
        }
      }
      meshes.append([
        "primitives": [
          [
            "attributes": attributes, "indices": ii, "material": materials.count - 1,
            "mode": f.mesh.triangles.isEmpty ? 0 : 4,
          ]
        ]
      ])
      featureNodes[f.roomID,default:[:]][f.stageID,default:[]].append(nodes.count)
      nodes.append([
        "name": f.name, "mesh": meshes.count - 1,
        "extras": [
          "id": f.id.uuidString, "room": f.roomID.uuidString, "stage": f.stageID.uuidString,
          "evidence": f.kind.rawValue, "trade": f.trade.rawValue, "notes": f.notes,
          "endpoint": f.endpoint, "reviewed": f.reviewed,
          "sourceObservations": f.sourceIDs.map { $0.uuidString },
          "sourceGeometry": try JSONSerialization.jsonObject(with:JSONEncoder().encode(f.annotationSources ?? [])),
          "sourceRevision": f.revision,
          "captureClassification": f.captureClassification ?? "unclassified",
          "captureAnchor": f.captureAnchorID?.uuidString ?? "",
        ],
      ])
    }
    guard !meshes.isEmpty else { throw HouseError.message("No geometry in the selected layers.") }
    // Identity hierarchy only: vertices already use the exported world frame.
    // Explicit parents make levels, rooms and dated stages reusable in editors.
    var levels:[Int:[Int]]=[:]
    for room in h.rooms {
      guard let byStage=featureNodes[room.id] else{continue}
      var stageNodes:[Int]=[]
      for stage in h.stages {
        guard let children=byStage[stage.id],!children.isEmpty else{continue}
        stageNodes.append(nodes.count)
        nodes.append(["name":stage.name,"children":children,"extras":["type":"stage","id":stage.id.uuidString,"phase":stage.category.rawValue,"evidence":stage.kind.rawValue,"capturedAt":ISO8601DateFormatter().string(from:stage.date)]])
      }
      levels[room.level,default:[]].append(nodes.count)
      nodes.append(["name":room.name,"children":stageNodes,"extras":["type":"room","id":room.id.uuidString,"level":room.level]])
    }
    var sceneRoots:[Int]=[]
    for level in levels.keys.sorted() {
      sceneRoots.append(nodes.count)
      nodes.append(["name":"Level \(level)","children":levels[level]!,"extras":["type":"level","level":level]])
    }
    var tour=TourDirector.plan(h,options:options)
    let exportedRooms=Set(features.map{$0.roomID})
    tour.shots.removeAll{!exportedRooms.contains($0.roomID)}
    var cameras:[[String:Any]]=[],animations:[[String:Any]]=[],cameraNodes:[Int]=[]
    func appendFloats(_ values:[Float],type:String,count:Int,min:[Float]?=nil,max:[Float]?=nil)->Int {
      let offset=bin.count;for value in values{bin.float(value)}
      views.append(["buffer":0,"byteOffset":offset,"byteLength":bin.count-offset])
      var accessor:[String:Any]=["bufferView":views.count-1,"componentType":5126,"count":count,"type":type]
      if let min{accessor["min"]=min};if let max{accessor["max"]=max}
      let index=accessors.count;accessors.append(accessor);return index
    }
    // Each cut is a separate clip. Editors must not interpolate a camera
    // through unknown space between independently admitted room viewpoints.
    for (index,shot) in tour.shots.enumerated() {
      let frames=max(1,Int((shot.duration*30).rounded()))
      var times:[Float]=[],positions:[Float]=[],rotations:[Float]=[]
      var previous:SIMD4<Float>?
      for frame in 0...frames {
        let t=Double(frame)/Double(frames)
        let (position,yaw,pitch)=TourDirector.camera(shot,phase:shot.startPhase+t*(shot.endPhase-shot.startPhase))
        let camera=SceneBuilder.camera(at:position,yaw:yaw,pitch:pitch)
        var q=camera.simdOrientation.vector
        if let previous,simd_dot(previous,q)<0{q = -q};previous=q
        times.append(Float(t*shot.duration));positions += [Float(position.x),Float(position.z),Float(-position.y)];rotations += [q.x,q.y,q.z,q.w]
      }
      let time=appendFloats(times,type:"SCALAR",count:frames+1,min:[0],max:[Float(shot.duration)])
      let translation=appendFloats(positions,type:"VEC3",count:frames+1),rotation=appendFloats(rotations,type:"VEC4",count:frames+1)
      let node=nodes.count;cameraNodes.append(node)
      nodes.append(["name":"Tour shot \(index+1)","camera":cameras.count,"translation":Array(positions.prefix(3)),"rotation":Array(rotations.prefix(4)),"extras":["type":"tourCamera","room":shot.roomID.uuidString,"caption":shot.caption,"cut":index]])
      cameras.append(["type":"perspective","perspective":["aspectRatio":16.0/9.0,"yfov":65.0*Double.pi/180.0,"znear":0.03,"zfar":150.0]])
      animations.append(["name":"Shot \(index+1) · \(shot.caption)","samplers":[["input":time,"output":translation,"interpolation":"LINEAR"],["input":time,"output":rotation,"interpolation":"LINEAR"]],"channels":[["sampler":0,"target":["node":node,"path":"translation"]],["sampler":1,"target":["node":node,"path":"rotation"]]],"extras":["cut":index,"durationSeconds":shot.duration]])
    }
    if !cameraNodes.isEmpty {sceneRoots.append(nodes.count);nodes.append(["name":"Automatic tour","children":cameraNodes])}
    var json: [String: Any] = [
      "asset": [
        "version": "2.0", "generator": "House Xray",
        "extras": ["units": "metres", "sourceRevision": h.revision, "accuracy": "Uncalibrated"],
      ], "scene": 0, "scenes": [["nodes": sceneRoots]], "nodes": nodes, "meshes": meshes,
      "materials": materials, "images": images, "textures": textures,
      "buffers": [["byteLength": bin.count]], "bufferViews": views, "accessors": accessors,
    ]
    if !cameras.isEmpty {json["cameras"]=cameras;json["animations"]=animations}
    json["extras"] = [
      "tour":try JSONSerialization.jsonObject(with:JSONEncoder().encode(tour)),
      "sourceCoordinateSystem":"metres Z-up; geometry and cameras converted to glTF Y-up",
      "connections": try JSONSerialization.jsonObject(with: JSONEncoder().encode(h.connections)),
      "measurements": try JSONSerialization.jsonObject(with: JSONEncoder().encode(h.dimensions)),
    ]
    if images.isEmpty {
      json.removeValue(forKey: "images")
      json.removeValue(forKey: "textures")
    }
    var j = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    while j.count % 4 != 0 { j.append(0x20) }
    while bin.count % 4 != 0 { bin.append(0) }
    var output = Data()
    output.le(UInt32(0x4654_6c67))
    output.le(UInt32(2))
    output.le(UInt32(12 + 8 + j.count + 8 + bin.count))
    output.le(UInt32(j.count))
    output.le(UInt32(0x4e4f_534a))
    output.append(j)
    output.le(UInt32(bin.count))
    output.le(UInt32(0x004e_4942))
    output.append(bin)
    let url = destination("House-Xray.glb")
    try output.write(to: url, options: .atomic)
    return url
  }
  static func meshText(_ h: House, options: SceneOptions, ply: Bool) throws -> URL {
    let features = canonicalFeatures(h, options: options)
    // OBJ/PLY intentionally carry geometry only; do not require photo assets.
    let geometry=features.map{f->Feature in var result=f;result.texture=nil;return result}
    _=try exportAssets(geometry,textGeometry:true)
    let count = features.reduce(0) { $0 + $1.mesh.vertices.count }
    let faces = features.reduce(0) { $0 + $1.mesh.triangles.count / 3 }
    guard count > 0 else { throw HouseError.message("No geometry selected.") }
    var s =
      ply
      ? "ply\nformat ascii 1.0\ncomment House Xray metres Z-up uncalibrated\nelement vertex \(count)\nproperty double x\nproperty double y\nproperty double z\nelement face \(faces)\nproperty list uchar int vertex_indices\nend_header\n"
      : "# House Xray metres Z-up; uncalibrated evidence\n"
    for f in features {
      try Task.checkCancellation()
      for p in f.mesh.vertices { s += "\(ply ? "" : "v ")\(p.x) \(p.y) \(p.z)\n" }
    }
    var offset = ply ? 0 : 1
    for f in features {
      try Task.checkCancellation()
      if !ply { s += "g feature_\(f.id.uuidString.replacingOccurrences(of:"-",with:"_"))\n" }
      for i in stride(from: 0, to: f.mesh.triangles.count, by: 3) {
        s +=
          "\(ply ? "3":"f") \(Int(f.mesh.triangles[i])+offset) \(Int(f.mesh.triangles[i+1])+offset) \(Int(f.mesh.triangles[i+2])+offset)\n"
      }
      offset += f.mesh.vertices.count
    }
    let url = destination(ply ? "House-Xray.ply" : "House-Xray.obj")
    try Data(s.utf8).write(to: url, options: .atomic)
    return url
  }
  static func usdz(_ h: House, options: SceneOptions) throws -> URL {
    let features = canonicalFeatures(h, options: options)
    guard !features.isEmpty else { throw HouseError.message("No geometry selected.") }
    let admitted=try exportAssets(features,textGeometry:true)
    var text =
      "#usda 1.0\n(\n defaultPrim = \"House\"\n metersPerUnit = 1\n upAxis = \"Z\"\n)\ndef Xform \"House\" {\n"
    var assets: [String: Data] = [:]
    for f in features {
      try Task.checkCancellation()
      let id = f.id.uuidString.replacingOccurrences(of: "-", with: "_")
      let pts = f.mesh.vertices.map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: ",")
      let c = f.trade.hex
      text +=
        "def \(f.mesh.triangles.isEmpty ? "Points":"Mesh") \"feature_\(id)\" {\n point3f[] points = [\(pts)]\n"
      if f.mesh.triangles.isEmpty {
        text += "float[] widths = [0.02] (interpolation = \"constant\")\n"
      } else {
        text +=
          "int[] faceVertexCounts = [\(Array(repeating:"3",count:f.mesh.triangles.count/3).joined(separator:","))]\n int[] faceVertexIndices = [\(f.mesh.triangles.map(String.init).joined(separator:","))]\n uniform token subdivisionScheme = \"none\"\n bool doubleSided = true\n"
      }
      text +=
        "color3f[] primvars:displayColor = [(\(Double((c>>16)&255)/255), \(Double((c>>8)&255)/255), \(Double(c&255)/255))]\ncustom string houseXray:id = \"\(f.id)\"\n"
      var texture: String?
      if let key = f.texture, let uv = f.uv, uv.count == f.mesh.vertices.count {
          if assets[key]==nil{assets[key]=try verifiedTexture(key,assets:admitted)}
          texture = key
          text +=
            "texCoord2f[] primvars:st = [\(uv.map{"(\($0.u),\(1-$0.v))"}.joined(separator:","))] (interpolation = \"vertex\")\nrel material:binding = </House/material_\(id)>\n"
      }
      text += "}\n"
      if let texture {
        text += """
          def Material "material_\(id)" {
            token outputs:surface.connect = </House/material_\(id)/Surface.outputs:surface>
            def Shader "Surface" {
              uniform token info:id = "UsdPreviewSurface"
              color3f inputs:diffuseColor.connect = </House/material_\(id)/Image.outputs:rgb>
              float inputs:roughness = 0.8
              float inputs:metallic = 0
              token outputs:surface
            }
            def Shader "Image" {
              uniform token info:id = "UsdUVTexture"
              asset inputs:file = @textures/\(texture)@
              token inputs:sourceColorSpace = "sRGB"
              float2 inputs:st.connect = </House/material_\(id)/ST.outputs:result>
              float3 outputs:rgb
            }
            def Shader "ST" {
              uniform token info:id = "UsdPrimvarReader_float2"
              token inputs:varname = "st"
              float2 outputs:result
            }
          }

          """
      }
    }
    text += "}\n"
    let entries =
      [StoredZip.Entry(name: "house.usda", data: Data(text.utf8))]
      + assets.sorted(by: { $0.key < $1.key }).map {
        StoredZip.Entry(name: "textures/" + $0.key, data: $0.value)
      }
    let url = destination("House-Xray.usdz")
    do{try StoredZip.write(entries, to: url, aligned: true)}
    catch{try? FileManager.default.removeItem(at:url);throw error}
    return url
  }
  static func archive(_ h: House, repo: Repository) throws -> URL {
    try h.validate()
    let metadata = try JSONEncoder().encode(h)
    guard metadata.count <= 100_000_000 else {
      throw HouseError.message(
        "Project metadata exceeds the 100 MB restore budget. Split large captures into separate projects before continuing."
      )
    }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
      "archive-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let json = staging.appendingPathComponent("house.json")
    try metadata.write(to: json)
    var items = [StreamingArchive.Item(name: "house.json", url: json)]
    var hashes = [
      "house.json": SHA256.hash(data: metadata).map { String(format: "%02x", $0) }.joined()
    ]
    var required: UInt64 = UInt64(metadata.count)
    for key in h.assets.sorted() {
      let url = try repo.assetURL(key)
      let digest = try StreamingArchive.digest(url)
      guard key.hasPrefix(digest.sha + ".") else {
        throw HouseError.message("Original evidence checksum mismatch.")
      }
      required += digest.size
      hashes["assets/" + key] = digest.sha
      items.append(.init(name: "assets/" + key, url: url))
    }
    guard UInt64(max(0, repo.freeBytes())) > required + 200_000_000 else {
      throw HouseError.message("Not enough free space for the complete archive.")
    }
    let viewer=try ArchiveViewer.html(h)
    let viewerURL=staging.appendingPathComponent("viewer.html");try viewer.write(to:viewerURL)
    hashes["viewer.html"]=SHA256.hash(data:viewer).map{String(format:"%02x",$0)}.joined()
    items.append(.init(name:"viewer.html",url:viewerURL))
    let manifest = staging.appendingPathComponent("manifest.json")
    try JSONSerialization.data(
      withJSONObject: ["format": "HouseXray", "version": 1, "sha256": hashes],
      options: [.sortedKeys]
    ).write(to: manifest)
    items.append(.init(name: "manifest.json", url: manifest))
    let html =
      "<!doctype html><meta charset=utf-8><title>House Xray evidence</title><style>body{font:16px system-ui;max-width:960px;margin:40px auto;background:#101923;color:#eee}img{max-width:100%;max-height:700px}article{margin:32px 0}</style><h1>House Xray evidence archive</h1><p>Unzip all files together. Coordinates in house.json are metres, Z-up. Photographs are historical evidence; placement is uncalibrated.</p><a href=viewer.html>Explore offline 3D</a> · <a href=house.json>Complete project metadata</a>"
      + h.observations.map {
        "<article><h2>\($0.date.formatted())</h2><img src=\"assets/\($0.image)\"><p>Observation \($0.id)</p></article>"
      }.joined()
    let unposed = h.documentaryPhotos.map {
      "<article><h2>Unposed documentary photograph</h2><img src=\"assets/\($0.image)\"><p>Photo \($0.id) · no spatial calibration</p></article>"
    }.joined()
    let index = staging.appendingPathComponent("index.html")
    try Data((html + unposed).utf8).write(to: index)
    items.append(.init(name: "index.html", url: index))
    let url = destination("House-Xray.hxray")
    _ = try StreamingArchive.write(items, to: url)
    return url
  }
  static func restore(_ url: URL, repo: Repository) throws -> House {
    try StreamingArchive.restore(url, repo: repo)
  }
  static func metadata(_ h: House) throws -> URL {
    let url = destination("House-Xray.json")
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(h).write(to: url, options: .atomic)
    return url
  }
}
