import Foundation
import CryptoKit
import ImageIO
import simd
import CoreGraphics

protocol EvidenceAssetReader {func read(_ key:String)throws->Data}

struct VisualMapReference: Codable, Identifiable, Equatable {
  var id=UUID();var segmentID:UUID;var roomID:UUID;var stageID:UUID
  var asset:String;var fingerprint:String;var date=Date()
}
struct VisualMap: Codable {
  struct View: Codable {var observationID:UUID;var position:V3;var start:Int;var count:Int}
  var schema=1;var segmentID:UUID;var roomID:UUID;var stageID:UUID;var frameID:UUID?
  var fingerprint:String;var points:[V3];var descriptors:Data;var views:[View]
  var valid:Bool {
    schema==1 && points.count<=28800 && descriptors.count==points.count*32
      && points.allSatisfy{$0.finite} && views.count>=2 && views.count<=12
      && Set(views.map{$0.observationID}).count==views.count
      && views.allSatisfy{$0.start>=0 && $0.count>=0 && $0.start<=points.count && $0.count<=points.count-$0.start && $0.position.finite}
  }
}
enum VisualMapping {
  struct Features {var xy:[Float];var descriptors:Data;var count:Int}
  struct Pose {var transform:Rigid;var inliers:Int;var rms:Double;var sources:[UUID]}
  struct Signature:Codable {var observations:[Observation];var segment:Segment;var references:[ReferenceBoard]}
  static func fingerprint(house:House,segment:Segment)throws->String {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let data=try encoder.encode(Signature(observations:house.observations.filter{$0.segmentID==segment.id},segment:segment,references:house.references))
    return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  }
  static func detect(gray:Data,width:Int,height:Int,stride:Int)throws->Features {
    var xy=[Float](repeating:0,count:2400),bytes=[UInt8](repeating:0,count:38400)
    let count=gray.withUnsafeBytes{p in xy.withUnsafeMutableBufferPointer{x in bytes.withUnsafeMutableBufferPointer{d in
      hx_vision_detect(p.bindMemory(to:UInt8.self).baseAddress,UInt32(gray.count),UInt32(width),UInt32(height),UInt32(stride),x.baseAddress,d.baseAddress,1200)
    }}}
    guard count>=0 else{throw HouseError.message("Visual feature extraction rejected the image.")}
    return Features(xy:Array(xy.prefix(Int(count)*2)),descriptors:Data(bytes.prefix(Int(count)*32)),count:Int(count))
  }
  static func image(_ data:Data)throws->(Data,Int,Int) {
    guard let source=CGImageSourceCreateWithData(data as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1280,kCGImageSourceCreateThumbnailWithTransform:false] as CFDictionary) else{throw HouseError.message("Visual map image cannot be decoded.")}
    let w=cg.width,h=cg.height;var gray=Data(count:w*h)
    let ok=gray.withUnsafeMutableBytes{p->Bool in
      guard let context=CGContext(data:p.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else{return false}
      context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
    }
    guard ok else{throw HouseError.message("Visual map image allocation failed.")};return (gray,w,h)
  }
  static func build(house:House,segment:Segment,repo:any EvidenceAssetReader)throws->VisualMap {
    let all=house.observations.filter{$0.segmentID==segment.id && $0.depth != nil && !$0.documentary}
    let selected=PoseRefinement.selected(all,segment:segment,house:house).0.filter{$0.sharpness>=0.02}
    guard selected.count>=2 else{throw HouseError.message("Capture at least two overlapping, sharp depth views of this stage first.")}
    var map=VisualMap(segmentID:segment.id,roomID:segment.roomID,stageID:segment.stageID,frameID:segment.registration==nil ? segment.id:nil,fingerprint:try fingerprint(house:house,segment:segment),points:[],descriptors:Data(),views:[])
    let count=min(12,selected.count)
    for index in 0..<count {
      try Task.checkCancellation()
      let o=selected[index*selected.count/count],w=o.depthWidth,h=o.depthHeight
      guard w>=3,h>=3,w*h<=1000000 else{continue}
      let depth=try repo.read(o.depth!),confidence=try o.confidence.map{try repo.read($0)}
      guard depth.count==w*h*4,confidence==nil || confidence?.count==w*h else{continue}
      let (gray,iw,ih)=try image(repo.read(o.image));let features=try detect(gray:gray,width:iw,height:ih,stride:iw)
      let start=map.points.count
      for i in 0..<features.count {
        let u=Double(features.xy[i*2]),v=Double(features.xy[i*2+1]);let x=Int(u*Double(w)),y=Int(v*Double(h))
        guard x>0,y>0,x<w-1,y<h-1 else{continue}
        if let confidence,confidence[y*w+x]<2{continue}
        var samples:[Double]=[]
        for dy in -1...1{for dx in -1...1{samples.append(Double(depth.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:((y+dy)*w+x+dx)*4,as:Float.self)}))}}
        guard samples.allSatisfy({$0.isFinite && $0>=0.15 && $0<=5}),let low=samples.min(),let high=samples.max(),high-low<0.04 else{continue}
        // Interpolate the continuous depth patch at the RGB feature's subpixel
        // location. Nearest-cell depth biases oblique surfaces by up to one
        // coarse depth pixel; the continuity gate above still rejects edges.
        let tx=u*Double(w)-Double(x),ty=v*Double(h)-Double(y)
        let d=samples[4]*(1-tx)*(1-ty)+samples[5]*tx*(1-ty)+samples[7]*(1-tx)*ty+samples[8]*tx*ty,cx=(u*Double(o.width)-o.intrinsics[2])*d/o.intrinsics[0],cy = -(v*Double(o.height)-o.intrinsics[5])*d/o.intrinsics[4],cz = -d,m=o.camera
        let ar=V3(m[0]*cx+m[1]*cy+m[2]*cz+m[3],m[4]*cx+m[5]*cy+m[6]*cz+m[7],m[8]*cx+m[9]*cy+m[10]*cz+m[11])
        var point=V3(ar.x,-ar.z,ar.y);if let t=segment.registration{point=t.apply(point)}
        map.points.append(point);map.descriptors.append(features.descriptors.subdata(in:i*32..<(i+1)*32))
      }
      let m=o.camera;var position=V3(m[3],-m[11],m[7]);if let t=segment.registration{position=t.apply(position)}
      let retained=map.points.count-start
      if retained>=30{map.views.append(VisualMap.View(observationID:o.id,position:position,start:start,count:retained))}
      else{map.points.removeLast(retained);map.descriptors.removeSubrange(start*32..<map.descriptors.count)}
    }
    guard map.valid,map.views.count>=2 else{throw HouseError.message("Not enough stable, textured depth features. Capture wider views with overlapping corners and good lighting.")}
    return map
  }
  static func agree(_ a:Rigid,_ b:Rigid)->Bool {
    guard a.valid,b.valid else{return false}
    let x=a.values,y=b.values
    guard (V3(x[3],x[7],x[11])-V3(y[3],y[7],y[11])).length<=0.03 else{return false}
    var trace=0.0
    for row in 0..<3 {for col in 0..<3 {trace += x[row*4+col]*y[row*4+col]}}
    return acos(max(-1,min(1,(trace-1)/2)))<=3*Double.pi/180
  }
  static func overlay(liveCamera:Rigid,savedCanonicalCamera:Rigid)->Rigid? {
    guard let live=PoseRefinement.matrix(liveCamera.values),let saved=PoseRefinement.matrix(savedCanonicalCamera.values),let nativeFromCanonical=PoseRefinement.matrix([1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1]) else{return nil}
    let result=Rigid(values:PoseRefinement.array(live*simd_inverse(nativeFromCanonical*saved)))
    return result.valid ? result:nil
  }
  static func competingMatch(_ features:Features,width:Int,height:Int,intrinsics:[Double],maps:[VisualMap])->Bool {
    maps.contains {query(features,width:width,height:height,intrinsics:intrinsics,map:$0) != nil}
  }
  static func query(_ features:Features,width:Int,height:Int,intrinsics:[Double],map:VisualMap,diagnostic:((String)->Void)?=nil)->Pose? {
    guard map.valid,features.count>=30,intrinsics.count==9 else{return nil}
    var candidates:[(Pose,V3)]=[]
    for view in map.views {
      let descriptors=map.descriptors.subdata(in:view.start*32..<(view.start+view.count)*32)
      var pairs=[UInt32](repeating:0,count:2400)
      let count=descriptors.withUnsafeBytes{m in features.descriptors.withUnsafeBytes{q in pairs.withUnsafeMutableBufferPointer{p in
        hx_vision_match(m.bindMemory(to:UInt8.self).baseAddress,UInt32(view.count),q.bindMemory(to:UInt8.self).baseAddress,UInt32(features.count),p.baseAddress,1200)
      }}}
      guard count>=30 else{diagnostic?("view \(view.observationID): insufficient matches \(count)");continue}
      var xyz:[Double]=[],xy:[Double]=[]
      for i in 0..<Int(count){let p=map.points[view.start+Int(pairs[i*2])],q=Int(pairs[i*2+1]);xyz += [p.x,p.y,p.z];xy += [Double(features.xy[q*2])*Double(width),Double(features.xy[q*2+1])*Double(height)]}
      var matrix=[Double](repeating:0,count:16),quality=HXPoseQuality()
      let accepted=xyz.withUnsafeBufferPointer{x in xy.withUnsafeBufferPointer{y in matrix.withUnsafeMutableBufferPointer{out in
        hx_vision_pose(x.baseAddress,y.baseAddress,UInt32(count),intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),out.baseAddress,&quality)
      }}}
      diagnostic?("view \(view.observationID): matches \(count), pose \(accepted), rejection \(quality.rejection), inliers \(quality.inliers)")
      if accepted==1,Rigid(values:matrix).valid{candidates.append((Pose(transform:Rigid(values:matrix),inliers:Int(quality.inliers),rms:quality.rms_pixels,sources:[view.observationID]),view.position))}
    }
    guard candidates.count>=2 else{diagnostic?("Fewer than two accepted source views");return nil}
    let origin=candidates[0].0.transform
    guard candidates.contains(where:{($0.1-candidates[0].1).length>=0.15}) else{diagnostic?("Insufficient source-view baseline");return nil}
    guard candidates.dropFirst().allSatisfy({agree(origin,$0.0.transform)}) else{diagnostic?("Accepted source views disagree");return nil}
    var result=candidates.max(by:{$0.0.inliers<$1.0.inliers})!.0
    result.sources=candidates.flatMap{$0.0.sources};return result
  }
}
