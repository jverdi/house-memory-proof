import Foundation
import CryptoKit
import SceneKit
import AVFoundation
import UIKit

extension Data {
    mutating func le<T:FixedWidthInteger>(_ x:T){var v=x.littleEndian;Swift.withUnsafeBytes(of:&v){append(contentsOf:$0)}}
    mutating func float(_ x:Float){le(x.bitPattern)}
    func uint16(_ i:Int)->UInt16 {UInt16(self[i])|UInt16(self[i+1])<<8}
    func uint32(_ i:Int)->UInt32 {UInt32(uint16(i))|UInt32(uint16(i+2))<<16}
}
enum StoredZip {
    static let crcTable:[UInt32]=(0..<256).map{v in var c=UInt32(v);for _ in 0..<8{c=c&1 != 0 ? 0xEDB88320^(c>>1):c>>1};return c}
    static func crc(_ data:Data)->UInt32{var c:UInt32=0xffffffff;for b in data{c=crcTable[Int((c^UInt32(b))&255)]^(c>>8)};return c^0xffffffff}
    struct Entry{var name:String;var data:Data}
    static func write(_ entries:[Entry],to url:URL,aligned:Bool=false)throws {
        guard entries.count<65535 else{throw HouseError.message("Too many archive entries.")}
        FileManager.default.createFile(atPath:url.path,contents:nil);let f=try FileHandle(forWritingTo:url);defer{try? f.close()};var central=Data();var offset:UInt32=0
        for e in entries {
            let name=Data(e.name.utf8);guard name.count<65535,e.data.count<1_000_000_000 else{throw HouseError.message("Archive entry is too large.")}
            let remainder=(Int(offset)+30+name.count)%64
            var padding=aligned ? (64-remainder)%64:0;if padding>0 && padding<4{padding+=64}
            var extra=Data();if padding>=4{extra.le(UInt16(0x1986));extra.le(UInt16(padding-4));extra.append(Data(repeating:0,count:padding-4))}
            let checksum=crc(e.data),size=UInt32(e.data.count)
            var h=Data();h.le(UInt32(0x04034b50));h.le(UInt16(20));h.le(UInt16(0x800));h.le(UInt16(0));h.le(UInt16(0));h.le(UInt16(0));h.le(checksum);h.le(size);h.le(size);h.le(UInt16(name.count));h.le(UInt16(extra.count));h.append(name);h.append(extra)
            try f.write(contentsOf:h);try f.write(contentsOf:e.data)
            central.le(UInt32(0x02014b50));central.le(UInt16(20));central.le(UInt16(20));central.le(UInt16(0x800));central.le(UInt16(0));central.le(UInt16(0));central.le(UInt16(0));central.le(checksum);central.le(size);central.le(size);central.le(UInt16(name.count));central.le(UInt16(0));central.le(UInt16(0));central.le(UInt16(0));central.le(UInt16(0));central.le(UInt32(0));central.le(offset);central.append(name)
            guard UInt64(offset)+UInt64(h.count)+UInt64(size)<UInt64(UInt32.max) else{throw HouseError.message("This build supports archives below 4 GB. Export smaller room projects.")}
            offset+=UInt32(h.count)+size
        }
        try f.write(contentsOf:central);var end=Data();end.le(UInt32(0x06054b50));end.le(UInt16(0));end.le(UInt16(0));end.le(UInt16(entries.count));end.le(UInt16(entries.count));end.le(UInt32(central.count));end.le(offset);end.le(UInt16(0));try f.write(contentsOf:end);try f.synchronize()
    }
    static func read(_ url:URL)throws->[Entry] {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<700_000_000 else{throw HouseError.message("Archive restore is limited to 700 MB in this build.")}
        let d=try Data(contentsOf:url,options:.mappedIfSafe);var i=0,entries:[Entry]=[],names=Set<String>()
        while i+30<=d.count && d.uint32(i)==0x04034b50 {
            let flags=d.uint16(i+6),method=d.uint16(i+8),crc=d.uint32(i+14),size=Int(d.uint32(i+18)),raw=Int(d.uint32(i+22)),nl=Int(d.uint16(i+26)),el=Int(d.uint16(i+28)),start=i+30+nl+el
            guard method==0,flags&9==0,size==raw,size<=512*1024*1024,start<=d.count,size<=d.count-start,nl>0,i+30+nl<=d.count else{throw HouseError.message("Unsupported, truncated or compressed archive. Import a House Xray archive created by this app.")}
            guard let name=String(data:d[(i+30)..<(i+30+nl)],encoding:.utf8),!name.hasPrefix("/"),!name.contains("\\"),!name.split(separator:"/").contains(".."),names.insert(name).inserted else{throw HouseError.message("Unsafe or duplicate archive path.")}
            let bytes=d.subdata(in:start..<start+size);guard Self.crc(bytes)==crc else{throw HouseError.message("Archive checksum failed.")};entries.append(Entry(name:name,data:bytes));i=start+size
            if entries.count>50000{throw HouseError.message("Archive has too many entries.")}
        }
        guard !entries.isEmpty,i+4<=d.count,d.uint32(i)==0x02014b50 else{throw HouseError.message("Incomplete archive.")};return entries
    }
}
enum Exporter {
    static func destination(_ name:String)->URL {let dir=FileManager.default.temporaryDirectory.appendingPathComponent("exports",isDirectory:true);try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);return dir.appendingPathComponent(UUID().uuidString.prefix(8)+"-"+name)}
    static func canonicalFeatures(_ h:House,options:SceneOptions)->[Feature] {h.features.filter{SceneBuilder.visible($0,options)}.map{f in var f=f;if let sid=f.segmentID,let t=h.segments.first(where:{$0.id==sid})?.registration {f.mesh.vertices=f.mesh.vertices.map{t.apply($0)}};return f}}
    static func glb(_ h:House,options:SceneOptions)throws->URL {
        let features=canonicalFeatures(h,options:options);var bin=Data(),views:[[String:Any]]=[],accessors:[[String:Any]]=[],meshes:[[String:Any]]=[],nodes:[[String:Any]]=[],materials:[[String:Any]]=[]
        for f in features where !f.mesh.vertices.isEmpty {
            let posOffset=bin.count;var lo=[Double](repeating:Double.infinity,count:3),hi=[Double](repeating:-Double.infinity,count:3)
            for p in f.mesh.vertices {let v=[p.x,p.z,-p.y];for j in 0..<3{bin.float(Float(v[j]));lo[j]=min(lo[j],v[j]);hi[j]=max(hi[j],v[j])}}
            views.append(["buffer":0,"byteOffset":posOffset,"byteLength":bin.count-posOffset,"target":34962]);let pi=accessors.count;accessors.append(["bufferView":views.count-1,"componentType":5126,"count":f.mesh.vertices.count,"type":"VEC3","min":lo,"max":hi])
            let indices=f.mesh.triangles.isEmpty ? Array(0..<Int32(f.mesh.vertices.count)):f.mesh.triangles
            let idxOffset=bin.count;for i in indices{bin.le(UInt32(i))};views.append(["buffer":0,"byteOffset":idxOffset,"byteLength":bin.count-idxOffset,"target":34963]);let ii=accessors.count;accessors.append(["bufferView":views.count-1,"componentType":5125,"count":indices.count,"type":"SCALAR"])
            let c=f.trade.hex;materials.append(["name":f.trade.rawValue,"doubleSided":true,"pbrMetallicRoughness":["baseColorFactor":[Double((c>>16)&255)/255,Double((c>>8)&255)/255,Double(c&255)/255,1],"metallicFactor":0,"roughnessFactor":0.8]])
            meshes.append(["primitives":[["attributes":["POSITION":pi],"indices":ii,"material":materials.count-1,"mode":f.mesh.triangles.isEmpty ? 0:4]]])
            nodes.append(["name":f.name,"mesh":meshes.count-1,"extras":["id":f.id.uuidString,"room":f.roomID.uuidString,"stage":f.stageID.uuidString,"evidence":f.kind.rawValue,"trade":f.trade.rawValue,"notes":f.notes]])
        }
        guard !meshes.isEmpty else{throw HouseError.message("No geometry in the selected layers.")}
        let json:[String:Any]=["asset":["version":"2.0","generator":"House Xray","extras":["units":"metres","sourceRevision":h.revision,"accuracy":"Uncalibrated"]],"scene":0,"scenes":[["nodes":Array(nodes.indices)]],"nodes":nodes,"meshes":meshes,"materials":materials,"buffers":[["byteLength":bin.count]],"bufferViews":views,"accessors":accessors]
        var j=try JSONSerialization.data(withJSONObject:json,options:[.sortedKeys]);while j.count%4 != 0{j.append(0x20)};while bin.count%4 != 0{bin.append(0)}
        var output=Data();output.le(UInt32(0x46546c67));output.le(UInt32(2));output.le(UInt32(12+8+j.count+8+bin.count));output.le(UInt32(j.count));output.le(UInt32(0x4e4f534a));output.append(j);output.le(UInt32(bin.count));output.le(UInt32(0x004e4942));output.append(bin)
        let url=destination("House-Xray.glb");try output.write(to:url,options:.atomic);return url
    }
    static func meshText(_ h:House,options:SceneOptions,ply:Bool)throws->URL {
        let features=canonicalFeatures(h,options:options);let count=features.reduce(0){$0+$1.mesh.vertices.count},faces=features.reduce(0){$0+$1.mesh.triangles.count/3};guard count>0 else{throw HouseError.message("No geometry selected.")}
        var s=ply ? "ply\nformat ascii 1.0\ncomment House Xray metres Z-up uncalibrated\nelement vertex \(count)\nproperty double x\nproperty double y\nproperty double z\nelement face \(faces)\nproperty list uchar int vertex_indices\nend_header\n":"# House Xray metres Z-up; uncalibrated evidence\n"
        for f in features{for p in f.mesh.vertices{s+="\(ply ? "" : "v ")\(p.x) \(p.y) \(p.z)\n"}}
        var offset=ply ? 0:1
        for f in features{if !ply{s+="g feature_\(f.id.uuidString.replacingOccurrences(of:"-",with:"_"))\n"};for i in stride(from:0,to:f.mesh.triangles.count,by:3){s+="\(ply ? "3":"f") \(Int(f.mesh.triangles[i])+offset) \(Int(f.mesh.triangles[i+1])+offset) \(Int(f.mesh.triangles[i+2])+offset)\n"};offset+=f.mesh.vertices.count}
        let url=destination(ply ? "House-Xray.ply":"House-Xray.obj");try Data(s.utf8).write(to:url,options:.atomic);return url
    }
    static func usdz(_ h:House,options:SceneOptions)throws->URL {
        let features=canonicalFeatures(h,options:options);guard !features.isEmpty else{throw HouseError.message("No geometry selected.")}
        var text="#usda 1.0\n(\n defaultPrim = \"House\"\n metersPerUnit = 1\n upAxis = \"Z\"\n)\ndef Xform \"House\" {\n"
        for f in features {
            let pts=f.mesh.vertices.map{"(\($0.x), \($0.y), \($0.z))"}.joined(separator:",")
            let c=f.trade.hex
            text+="def Mesh \"feature_\(f.id.uuidString.replacingOccurrences(of:"-",with:"_"))\" {\n point3f[] points = [\(pts)]\n int[] faceVertexCounts = [\(Array(repeating:"3",count:f.mesh.triangles.count/3).joined(separator:","))]\n int[] faceVertexIndices = [\(f.mesh.triangles.map(String.init).joined(separator:","))]\n uniform token subdivisionScheme = \"none\"\n bool doubleSided = true\n color3f[] primvars:displayColor = [(\(Double((c>>16)&255)/255), \(Double((c>>8)&255)/255), \(Double(c&255)/255))]\n}\n"
        };text+="}\n"
        let url=destination("House-Xray.usdz");try StoredZip.write([.init(name:"house.usda",data:Data(text.utf8))],to:url,aligned:true);return url
    }
    static func archive(_ h:House,repo:Repository)throws->URL {
        try h.validate();_=try repo.integrity(h);let metadata=try JSONEncoder().encode(h)
        var entries=[StoredZip.Entry(name:"house.json",data:metadata)]
        var total=metadata.count
        for key in h.assets.sorted(){let d=try repo.read(key);total+=d.count;guard total<600_000_000 else{throw HouseError.message("This build's portable archive working set is limited to 600 MB. Originals remain local; large chunked archives are not yet qualified.")};entries.append(.init(name:"assets/"+key,data:d))}
        let hashes=Dictionary(uniqueKeysWithValues:entries.map{($0.name,SHA256.hash(data:$0.data).map{String(format:"%02x",$0)}.joined())})
        entries.append(.init(name:"manifest.json",data:try JSONSerialization.data(withJSONObject:["format":"HouseXray","version":1,"sha256":hashes],options:[.sortedKeys])))
        let html="<!doctype html><meta charset=utf-8><title>House Xray evidence</title><style>body{font:16px system-ui;max-width:960px;margin:40px auto;background:#101923;color:#eee}img{max-width:100%;max-height:700px}article{margin:32px 0}</style><h1>House Xray evidence archive</h1><p>Unzip all files together. Coordinates in house.json are metres, Z-up. Photographs are historical evidence; placement is uncalibrated.</p><a href=house.json>Complete project metadata</a>"+h.observations.map{"<article><h2>\($0.date.formatted())</h2><img src=\"assets/\($0.image)\"><p>Observation \($0.id)</p></article>"}.joined()
        entries.append(.init(name:"index.html",data:Data(html.utf8)));let url=destination("House-Xray.hxray");try StoredZip.write(entries,to:url);return url
    }
    static func restore(_ url:URL,repo:Repository)throws->House {
        let entries=try StoredZip.read(url),files=Dictionary(uniqueKeysWithValues:entries.map{($0.name,$0.data)})
        guard let manifest=files["manifest.json"],let object=try JSONSerialization.jsonObject(with:manifest) as? [String:Any],object["format"] as? String=="HouseXray",object["version"] as? Int==1,let hashes=object["sha256"] as? [String:String],let data=files["house.json"] else{throw HouseError.message("Missing or incompatible archive manifest.")}
        for (path,hash) in hashes {guard let d=files[path],SHA256.hash(data:d).map({String(format:"%02x",$0)}).joined()==hash else{throw HouseError.message("Archive integrity check failed.")}}
        var h=try JSONDecoder().decode(House.self,from:data);try h.validate()
        for key in h.assets {guard let d=files["assets/"+key],hashes["assets/"+key] != nil else{throw HouseError.message("Archive is missing an original asset.")};let ext=String(key.split(separator:".").last ?? "bin");guard try repo.put(d,ext:ext)==key else{throw HouseError.message("Asset identity mismatch.")}}
        // Always restore to a new project; never overwrite the good live copy.
        h.id=UUID();h.name += " · restored";h.revision=0;return h
    }
    static func metadata(_ h:House)throws->URL {let url=destination("House-Xray.json");let enc=JSONEncoder();enc.outputFormatting=[.prettyPrinted,.sortedKeys];try enc.encode(h).write(to:url,options:.atomic);return url}
}
