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
    schema==1 && points.count<=240000 && descriptors.count==points.count*32
      && points.allSatisfy{$0.finite} && views.count>=2 && views.count<=120
      && Set(views.map{$0.observationID}).count==views.count
      && views.allSatisfy{$0.start>=0 && $0.count>=0 && $0.start<=points.count && $0.count<=points.count-$0.start && $0.position.finite}
  }
}
enum VisualMapping {
  static let featureLimit=2000
  struct PixelIdentity:Hashable {var u:UInt32;var v:UInt32;init(_ u:Double,_ v:Double){self.u=Float(u).bitPattern;self.v=Float(v).bitPattern}}
  struct Features {var xy:[Float];var descriptors:Data;var count:Int}
  struct Pose {var transform:Rigid;var inliers:Int;var rms:Double;var sources:[UUID]}
  struct Signature:Codable {var algorithm="visual-v12-camera-pixel-centres";var observations:[Observation];var segment:Segment;var references:[ReferenceBoard]}
  static func fingerprint(house:House,segment:Segment)throws->String {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let data=try encoder.encode(Signature(observations:house.observations.filter{$0.segmentID==segment.id},segment:segment,references:house.references))
    return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  }
  static func detect(gray:Data,width:Int,height:Int,stride:Int)throws->Features {
    var xy=[Float](repeating:0,count:featureLimit*2),bytes=[UInt8](repeating:0,count:featureLimit*32)
    let count=gray.withUnsafeBytes{p in xy.withUnsafeMutableBufferPointer{x in bytes.withUnsafeMutableBufferPointer{d in
      hx_vision_detect(p.bindMemory(to:UInt8.self).baseAddress,UInt32(gray.count),UInt32(width),UInt32(height),UInt32(stride),x.baseAddress,d.baseAddress,UInt32(featureLimit))
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
  static func cameraFeatures(_ features:Features,imageWidth:Int,imageHeight:Int,cameraWidth:Int,cameraHeight:Int)throws->Features {
    guard imageWidth>0,imageHeight>0,cameraWidth>0,cameraHeight>0,features.count>=0,features.xy.count==features.count*2,features.descriptors.count==features.count*32 else{throw HouseError.message("Invalid visual image dimensions or feature storage.")}
    guard imageWidth != cameraWidth || imageHeight != cameraHeight else{return features}
    // Integer pixel centres do not scale about zero. A thumbnail pixel x
    // maps to (x + 0.5) * cameraWidth / imageWidth - 0.5 in the camera.
    let du=0.5/Double(imageWidth)-0.5/Double(cameraWidth),dv=0.5/Double(imageHeight)-0.5/Double(cameraHeight)
    var result=features
    for i in 0..<features.count {result.xy[i*2]=Float(Double(features.xy[i*2])+du);result.xy[i*2+1]=Float(Double(features.xy[i*2+1])+dv)}
    return result
  }
  static func detectImage(_ data:Data,cameraWidth:Int,cameraHeight:Int)throws->Features {
    let (gray,w,h)=try image(data),features=try detect(gray:gray,width:w,height:h,stride:w)
    return try cameraFeatures(features,imageWidth:w,imageHeight:h,cameraWidth:cameraWidth,cameraHeight:cameraHeight)
  }
  static func keyframes(_ input:[Observation],limit:Int)->[Observation] {
    let ordered=input.sorted{a,b in a.timestamp==b.timestamp ? a.id.uuidString<b.id.uuidString:a.timestamp<b.timestamp}
    let count=min(max(1,limit),ordered.count)
    guard count>1 else{return Array(ordered.prefix(count))}
    return (0..<count).map{ordered[$0*(ordered.count-1)/(count-1)]}
  }
  static func build(house:House,segment:Segment,repo:any EvidenceAssetReader,maximumViews:Int=12)throws->VisualMap {
    let all=house.observations.filter{$0.segmentID==segment.id && $0.depth != nil && !$0.documentary}
    let selected=PoseRefinement.selected(all,segment:segment,house:house).0.filter{$0.sharpness>=0.02}
    guard selected.count>=2 else{throw HouseError.message("Capture at least two overlapping, sharp depth views of this stage first.")}
    var map=VisualMap(segmentID:segment.id,roomID:segment.roomID,stageID:segment.stageID,frameID:segment.registration==nil ? segment.id:nil,fingerprint:try fingerprint(house:house,segment:segment),points:[],descriptors:Data(),views:[])
    var optimized:[UUID:[PixelIdentity:V3]]=[:],conflicts:[UUID:Set<PixelIdentity>]=[:]
    if let solution=segment.poseSolution,solution.fingerprint == (try? PoseGraph.fingerprint(house:house,segment:segment)),let landmarks=solution.landmarks {
      for landmark in landmarks {for control in landmark.controls {
        let key=PixelIdentity(control.u,control.v)
        if let prior=optimized[control.observationID]?[key],prior != landmark.point {conflicts[control.observationID,default:[]].insert(key)}
        optimized[control.observationID,default:[:]][key]=landmark.point
      }}
    }
    let retainedViews=keyframes(selected,limit:min(120,maximumViews))
    for o in retainedViews {
      try Task.checkCancellation()
      let w=o.depthWidth,h=o.depthHeight
      guard w>=3,h>=3,w*h<=1000000 else{continue}
      let depth=try repo.read(o.depth!),confidence=try o.confidence.map{try repo.read($0)}
      guard depth.count==w*h*4,confidence==nil || confidence?.count==w*h else{continue}
      let features=try detectImage(repo.read(o.image),cameraWidth:o.width,cameraHeight:o.height)
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
        var point=V3(ar.x,-ar.z,ar.y)
        // Reuse the jointly fitted landmark only at its exact feature identity,
        // with independent image provenance and agreement with continuous depth.
        // Descriptor matching and all query eligibility gates remain unchanged.
        let key=PixelIdentity(u,v)
        if conflicts[o.id]?.contains(key) != true,let landmark=optimized[o.id]?[key],(landmark-point).length<=0.025 {point=landmark}
        if let t=segment.registration{point=t.apply(point)}
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
  static func consensus(_ poses:[Rigid],positions:[V3])->[Int] {
    guard poses.count>=2,poses.count<=120,poses.count==positions.count,poses.allSatisfy({$0.valid}),positions.allSatisfy({$0.finite}) else{return []}
    let count=poses.count,indices=Array(poses.indices)
    let centres=poses.map{V3($0.values[3],$0.values[7],$0.values[11])}
    var agreement=[Bool](repeating:false,count:count*count)
    for a in indices {for b in a..<count {let value=agree(poses[a],poses[b]);agreement[a*count+b]=value;agreement[b*count+a]=value}}
    func separated(_ group:[Int])->Bool {
      for a in group {for b in group where b>a {if (positions[a]-positions[b]).length>=0.15{return true}}};return false
    }
    var best:[Int]=[]
    // Bounded deterministic clique search: every retained pair must agree.
    // Greedy search can abstain unnecessarily; it cannot weaken pairwise gates.
    for seed in indices {
      let ranked=indices.filter{$0 != seed}.sorted {a,b in
        let x=(centres[a]-centres[seed]).length,y=(centres[b]-centres[seed]).length
        return x==y ? a<b:x<y
      }
      var group=[seed]
      for candidate in ranked where group.allSatisfy({agreement[$0*count+candidate]}){group.append(candidate)}
      if group.count>best.count,separated(group){best=group}
    }
    guard best.count>=2 else{return []}
    if best.count<count {
      // An isolated bad source pose may be excluded only with at least three
      // mutually agreeing views and a two-thirds majority. A second supported
      // hypothesis always hides alignment, even against a larger majority.
      guard best.count>=3,best.count*3>=count*2 else{return []}
      let excluded=indices.filter{!best.contains($0)}
      for a in excluded {for b in excluded where b>a {
        if agreement[a*count+b],(positions[a]-positions[b]).length>=0.15{return []}
      }}
    }
    return best.sorted()
  }
  static func isCompeting(_ map:VisualMap,prior:Segment)->Bool {
    map.roomID != prior.roomID || (map.frameID != nil && map.frameID != prior.id)
  }
  static func competingMatch(_ features:Features,width:Int,height:Int,intrinsics:[Double],maps:[VisualMap])->Bool {
    // An ill-conditioned competing map is not evidence that a room is unique.
    // Strong appearance in two separated competing views is enough to abstain,
    // even when their PnP poses cannot pass the geometric eligibility checks.
    for map in maps where map.valid {
      var supported:[V3]=[],repeated:[Int:[V3]]=[:]
      for view in map.views {
        let bytes=map.descriptors.subdata(in:view.start*32..<(view.start+view.count)*32)
        var pairs=[UInt32](repeating:0,count:featureLimit*2)
        let count=bytes.withUnsafeBytes{m in features.descriptors.withUnsafeBytes{q in pairs.withUnsafeMutableBufferPointer{p in hx_vision_match(m.bindMemory(to:UInt8.self).baseAddress,UInt32(view.count),q.bindMemory(to:UInt8.self).baseAddress,UInt32(features.count),p.baseAddress,UInt32(featureLimit))}}}
        guard count>=8 else{continue}
        for i in 0..<Int(count){repeated[Int(pairs[i*2+1]),default:[]].append(view.position)}
        guard count>=30 else{continue}
        var cells=Set<Int>(),loU=1.0,loV=1.0,hiU=0.0,hiV=0.0
        for i in 0..<Int(count) {let index=Int(pairs[i*2+1]),u=Double(features.xy[index*2]),v=Double(features.xy[index*2+1]);cells.insert(min(3,Int(u*4))+4*min(2,Int(v*3)));loU=min(loU,u);loV=min(loV,v);hiU=max(hiU,u);hiV=max(hiV,v)}
        guard cells.count>=6,hiU-loU>=0.3,hiV-loV>=0.3 else{continue}
        if supported.contains(where:{($0-view.position).length>=0.15}) {return true}
        supported.append(view.position)
      }
      if map.views.count>=4 {
        let indices=repeated.keys.filter {index in let views=repeated[index]!;return views.contains{a in views.contains{($0-a).length>=0.15}}}
        if indices.count>=30 {
          var cells=Set<Int>(),loU=1.0,loV=1.0,hiU=0.0,hiV=0.0
          for index in indices {let u=Double(features.xy[index*2]),v=Double(features.xy[index*2+1]);cells.insert(min(3,Int(u*4))+4*min(2,Int(v*3)));loU=min(loU,u);loV=min(loV,v);hiU=max(hiU,u);hiV=max(hiV,v)}
          if cells.count>=6,hiU-loU>=0.3,hiV-loV>=0.3 {return true}
        }
      }
    }
    return false
  }
  struct SourceMatches {var id:UUID;var position:V3;var matches:[Int:V3]}
  static func fusedPoints(_ sources:[SourceMatches])->[(Int,V3)] {
    var repeated:[Int:[(V3,V3)]]=[:]
    for source in sources {for (query,point) in source.matches {repeated[query,default:[]].append((point,source.position))}}
    var result:[(Int,V3)]=[]
    for query in repeated.keys.sorted() {
      let samples=repeated[query]!;guard samples.count>=2 else{continue}
      func median(_ values:[Double])->Double {let sorted=values.sorted();return sorted[sorted.count/2]}
      let centre=V3(median(samples.map{$0.0.x}),median(samples.map{$0.0.y}),median(samples.map{$0.0.z}))
      let supported=samples.filter{($0.0-centre).length<=0.025}
      guard supported.count>=2,supported.contains(where:{($0.1-supported[0].1).length>=0.15}) else{continue}
      result.append((query,supported.reduce(V3()){$0+$1.0}*(1/Double(supported.count))))
    }
    return result
  }
  static func pooledPose(_ sources:[SourceMatches],features:Features,width:Int,height:Int,intrinsics:[Double],diagnostic:((String)->Void)?)->Pose? {
    let points=fusedPoints(sources)
    guard points.count>=30 else{diagnostic?("Pooled source group has only \(points.count) independently repeated features");return nil}
    var xyz:[Double]=[],xy:[Double]=[]
    for (query,point) in points {
      xyz.append(contentsOf:[point.x,point.y,point.z])
      let u=Double(features.xy[query*2])*Double(width)
      let v=Double(features.xy[query*2+1])*Double(height)
      xy.append(contentsOf:[u,v])
    }
    var matrix=[Double](repeating:0,count:16),quality=HXPoseQuality()
    let accepted=xyz.withUnsafeBufferPointer{x in xy.withUnsafeBufferPointer{y in matrix.withUnsafeMutableBufferPointer{out in
      hx_vision_pose(x.baseAddress,y.baseAddress,UInt32(points.count),intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),out.baseAddress,&quality)
    }}}
    diagnostic?("Pooled source group: \(sources.count) sources, \(points.count) repeated features, rejection \(quality.rejection), cells \(quality.image_cells), span \(quality.span_x)/\(quality.span_y), spectrum \(quality.spread_largest)/\(quality.spread_middle)/\(quality.spread_smallest)")
    guard accepted==1,Rigid(values:matrix).valid else{return nil}
    return Pose(transform:Rigid(values:matrix),inliers:Int(quality.inliers),rms:quality.rms_pixels,sources:sources.map{$0.id})
  }
  static func checkedPooledPose(_ sources:[SourceMatches],individual:[Rigid],features:Features,width:Int,height:Int,intrinsics:[Double],diagnostic:((String)->Void)?)->Pose? {
    guard sources.count>=4 else{return nil}
    // Disjoint interleaved source-camera groups must independently pass the
    // unchanged PnP geometry gates. Each landmark needs repeated, separated
    // source support inside its own group; no single weak frame gains a vote.
    let a=sources.enumerated().filter{$0.offset%2==0}.map{$0.element},b=sources.enumerated().filter{$0.offset%2==1}.map{$0.element}
    guard let first=pooledPose(a,features:features,width:width,height:height,intrinsics:intrinsics,diagnostic:diagnostic),
      let second=pooledPose(b,features:features,width:width,height:height,intrinsics:intrinsics,diagnostic:diagnostic),agree(first.transform,second.transform),
      let all=pooledPose(sources,features:features,width:width,height:height,intrinsics:intrinsics,diagnostic:diagnostic),
      ([first.transform,second.transform]+individual).allSatisfy({agree(all.transform,$0)}) else{return nil}
    return all
  }
  static func query(_ features:Features,width:Int,height:Int,intrinsics:[Double],map:VisualMap,diagnostic:((String)->Void)?=nil)->Pose? {
    guard map.valid,features.count>=30,intrinsics.count==9 else{return nil}
    struct Candidate {var pose:Pose;var position:V3;var matches:[Int:V3]}
    var candidates:[Candidate]=[],sources:[SourceMatches]=[]
    for view in map.views {
      let descriptors=map.descriptors.subdata(in:view.start*32..<(view.start+view.count)*32)
      var pairs=[UInt32](repeating:0,count:featureLimit*2)
      let count=descriptors.withUnsafeBytes{m in features.descriptors.withUnsafeBytes{q in pairs.withUnsafeMutableBufferPointer{p in
        hx_vision_match(m.bindMemory(to:UInt8.self).baseAddress,UInt32(view.count),q.bindMemory(to:UInt8.self).baseAddress,UInt32(features.count),p.baseAddress,UInt32(featureLimit))
      }}}
      guard count>=8 else{diagnostic?("view \(view.observationID): insufficient matches \(count)");continue}
      var xyz:[Double]=[],xy:[Double]=[],matches:[Int:V3]=[:]
      for i in 0..<Int(count){let p=map.points[view.start+Int(pairs[i*2])],q=Int(pairs[i*2+1]);xyz += [p.x,p.y,p.z];xy += [Double(features.xy[q*2])*Double(width),Double(features.xy[q*2+1])*Double(height)];matches[q]=p}
      sources.append(SourceMatches(id:view.observationID,position:view.position,matches:matches))
      guard count>=30 else{diagnostic?("view \(view.observationID): insufficient individual matches \(count)");continue}
      var matrix=[Double](repeating:0,count:16),quality=HXPoseQuality()
      let accepted=xyz.withUnsafeBufferPointer{x in xy.withUnsafeBufferPointer{y in matrix.withUnsafeMutableBufferPointer{out in
        hx_vision_pose(x.baseAddress,y.baseAddress,UInt32(count),intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),out.baseAddress,&quality)
      }}}
      diagnostic?("view \(view.observationID): matches \(count), pose \(accepted), rejection \(quality.rejection), inliers \(quality.inliers), cells \(quality.image_cells), span \(quality.span_x)/\(quality.span_y), spectrum \(quality.spread_largest)/\(quality.spread_middle)/\(quality.spread_smallest)")
      if accepted==1,Rigid(values:matrix).valid{candidates.append(Candidate(pose:Pose(transform:Rigid(values:matrix),inliers:Int(quality.inliers),rms:quality.rms_pixels,sources:[view.observationID]),position:view.position,matches:matches))}
    }
    guard candidates.count>=2 else{
      diagnostic?("Fewer than two accepted source views; checking disjoint pooled source groups")
      return checkedPooledPose(sources,individual:candidates.map{$0.pose.transform},features:features,width:width,height:height,intrinsics:intrinsics,diagnostic:diagnostic)
    }
    let admitted=consensus(candidates.map{$0.pose.transform},positions:candidates.map{$0.position})
    diagnostic?("Source pose consensus: \(admitted.count)/\(candidates.count) views; positions \(candidates.map{[ $0.pose.transform.values[3],$0.pose.transform.values[7],$0.pose.transform.values[11] ]})")
    guard admitted.count>=2 else{diagnostic?("No unique, separated source-pose consensus");return nil}
    candidates=admitted.map{candidates[$0]}
    // Do not throw away the checked multi-view evidence by selecting one source
    // camera. Fuse spatially consistent repeats of each query feature, then
    // rerun the same robust PnP gates on one correspondence per image feature.
    var repeated:[Int:[(V3,V3)]]=[:]
    for candidate in candidates {for (query,point) in candidate.matches {repeated[query,default:[]].append((point,candidate.position))}}
    var xyz:[Double]=[],xy:[Double]=[]
    for query in repeated.keys.sorted() {
      let samples=repeated[query]!
      guard samples.count>=2 else{continue}
      func median(_ values:[Double])->Double {let ordered=values.sorted();return ordered[ordered.count/2]}
      let centre=V3(median(samples.map{$0.0.x}),median(samples.map{$0.0.y}),median(samples.map{$0.0.z}))
      let supported=samples.filter{($0.0-centre).length<=0.025}
      guard supported.count>=2,supported.contains(where:{($0.1-supported[0].1).length>=0.15}) else{continue}
      let point=supported.reduce(V3()){$0+$1.0}*(1/Double(supported.count))
      xyz += [point.x,point.y,point.z];xy += [Double(features.xy[query*2])*Double(width),Double(features.xy[query*2+1])*Double(height)]
    }
    guard xy.count>=60 else{diagnostic?("Insufficient repeated features for multi-view query refinement");return nil}
    var matrix=[Double](repeating:0,count:16),quality=HXPoseQuality()
    let accepted=xyz.withUnsafeBufferPointer{x in xy.withUnsafeBufferPointer{y in matrix.withUnsafeMutableBufferPointer{out in
      hx_vision_pose(x.baseAddress,y.baseAddress,UInt32(xy.count/2),intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),out.baseAddress,&quality)
    }}}
    let transform=Rigid(values:matrix)
    guard accepted==1,candidates.allSatisfy({agree(transform,$0.pose.transform)}) else{diagnostic?("Multi-view query refinement rejected at gate \(quality.rejection)");return nil}
    return Pose(transform:transform,inliers:Int(quality.inliers),rms:quality.rms_pixels,sources:candidates.flatMap{$0.pose.sources})
  }
}
