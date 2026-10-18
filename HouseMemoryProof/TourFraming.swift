import Foundation

struct TourSubject:Codable,Equatable {
  var featureID:UUID
  var featureRevision:Int
  var point:V3
}

// Exact triangle sightlines are separate from conservative camera-body bounds.
// A triangle's axis-aligned box must not hide a target outside that triangle.
struct TourSightlines {
  struct Triangle {
    var a:V3;var b:V3;var c:V3
    var bounds:SpatialClearance.Bounds {
      .init(low:V3(min(a.x,min(b.x,c.x)),min(a.y,min(b.y,c.y)),min(a.z,min(b.z,c.z))),
        high:V3(max(a.x,max(b.x,c.x)),max(a.y,max(b.y,c.y)),max(a.z,max(b.z,c.z))))
    }
    func blocks(from origin:V3,to target:V3)->Bool {
      let ray=target-origin,u=b-a,v=c-a,p=ray.cross(v),det=u.dot(p)
      guard abs(det)>1e-12 else{return false}
      let inverse=1/det,delta=origin-a,s=delta.dot(p)*inverse
      guard s>=(-1e-9),s<=1+1e-9 else{return false}
      let q=delta.cross(u),t=ray.dot(q)*inverse
      guard t>=(-1e-9),s+t<=1+1e-9 else{return false}
      let distance=v.dot(q)*inverse
      // The selected surface itself is the ray endpoint, not an obstruction.
      return distance>1e-7 && distance<1-1e-7
    }
  }
  private var triangles:[Triangle]=[]
  private var nodes:[SpatialClearance.Node]=[]
  private(set) var complete=true
  private(set) var includesPlanned=false
  private(set) var candidates:[TourSubject]=[]
  init(features:[Feature],house:House,limit:Int=500000) {
    includesPlanned=features.contains{$0.kind == .planned}
    var used=0
    let count=min(64,features.count)
    let sampled=Set((0..<count).map{count==1 ? 0:$0*(features.count-1)/(count-1)})
    for (featureIndex,feature) in features.enumerated() {
      let mesh=feature.mesh,primitives=mesh.triangles.isEmpty ? mesh.vertices.count:mesh.triangles.count/3
      guard primitives<=limit-used,!Task.isCancelled else{complete=false;triangles=[];candidates=[];return};used+=primitives
      let transform=feature.segmentID.flatMap{id in house.segments.first{$0.id==id}?.registration}
      func world(_ p:V3)->V3 {transform?.apply(p) ?? p}
      let samples=min(8,primitives)
      let selected=sampled.contains(featureIndex) ? Set((0..<samples).map{samples==1 ? 0:$0*(primitives-1)/(samples-1)}):Set<Int>()
      if mesh.triangles.isEmpty {
        for index in selected.sorted() {
          let point=world(mesh.vertices[index])
          guard point.finite else{complete=false;triangles=[];candidates=[];return}
          candidates.append(.init(featureID:feature.id,featureRevision:feature.revision,point:point))
        }
      }else{
        guard mesh.triangles.count%3==0 else{complete=false;triangles=[];candidates=[];return}
        for index in 0..<primitives {
          if index%1024==0 && Task.isCancelled {complete=false;triangles=[];candidates=[];return}
          let ids=(0..<3).map{Int(mesh.triangles[index*3+$0])}
          guard ids.allSatisfy({$0>=0 && $0<mesh.vertices.count}) else{complete=false;triangles=[];candidates=[];return}
          let a=world(mesh.vertices[ids[0]]),b=world(mesh.vertices[ids[1]]),c=world(mesh.vertices[ids[2]])
          guard a.finite,b.finite,c.finite else{complete=false;triangles=[];candidates=[];return}
          guard (b-a).cross(c-a).length>1e-12 else{continue}
          triangles.append(.init(a:a,b:b,c:c))
          if selected.contains(index) {candidates.append(.init(featureID:feature.id,featureRevision:feature.revision,point:(a+b+c)*(1.0/3)))}
        }
      }
    }
    if !triangles.isEmpty {_=build(0,triangles.count)}
  }
  private mutating func build(_ start:Int,_ end:Int)->Int {
    var bounds=triangles[start].bounds
    for i in (start+1)..<end {bounds=bounds.union(triangles[i].bounds)}
    let index=nodes.count;nodes.append(.init(bounds:bounds,start:start,count:end-start))
    if end-start>16 {
      let size=bounds.high-bounds.low,axis=size.x>=size.y && size.x>=size.z ? 0:size.y>=size.z ? 1:2
      func coordinate(_ triangle:Triangle)->Double {let p=triangle.bounds.centre;return axis==0 ? p.x:axis==1 ? p.y:p.z}
      triangles.replaceSubrange(start..<end,with:triangles[start..<end].sorted{coordinate($0)<coordinate($1)})
      let middle=(start+end)/2,left=build(start,middle),right=build(middle,end)
      nodes[index].left=left;nodes[index].right=right;nodes[index].count=0
    }
    return index
  }
  func visible(from camera:V3,to target:V3)->Bool {
    guard complete,camera.finite,target.finite,!Task.isCancelled else{return false}
    guard !nodes.isEmpty else{return true}
    var stack=[0]
    while let index=stack.popLast() {
      let node=nodes[index]
      guard node.bounds.intersects(camera,target,radius:0) else{continue}
      if node.count>0 {
        for i in node.start..<(node.start+node.count) where triangles[i].blocks(from:camera,to:target) {return false}
      }else{stack.append(node.left);stack.append(node.right)}
    }
    return true
  }
}

enum TourFraming {
  static let profile="subject-frustum-v1"
  static func inFrame(_ point:V3,camera:(V3,Double,Double),aspect:Double=16.0/9)->Bool {
    let (position,yaw,pitch)=camera,delta=point-position,distance=delta.length
    guard point.finite,position.finite,yaw.isFinite,pitch.isFinite,aspect.isFinite,aspect>0,distance>=0.35,distance<=30 else{return false}
    let forward=V3(-sin(yaw)*cos(pitch),cos(yaw)*cos(pitch),sin(pitch))
    let right=V3(cos(yaw),sin(yaw),0),up=right.cross(forward)
    let depth=delta.dot(forward),halfHeight=tan(65*Double.pi/360)*0.75
    return depth>0.03 && abs(delta.dot(right))<=depth*halfHeight*aspect && abs(delta.dot(up))<=depth*halfHeight
  }
  static func framed(_ shot:TourShot,subject:TourSubject)->TourShot {
    var result=shot
    let position=TourDirector.camera(shot,phase:(shot.startPhase+shot.endPhase)/2).0
    let direction=(subject.point-position).normalized
    result.yaw=atan2(-direction.x,direction.y);result.pitch=asin(max(-1,min(1,direction.z)))
    if result.endPosition != nil {result.endYaw=result.yaw;result.endPitch=result.pitch}
    result.subject=subject
    return result
  }
  static func held(_ shot:TourShot)->TourShot {
    var result=shot;let camera=TourDirector.camera(shot,phase:shot.startPhase)
    result.position=camera.0;result.yaw=camera.1;result.pitch=camera.2
    result.endPosition=nil;result.endYaw=nil;result.endPitch=nil;result.startPhase=0;result.endPhase=1
    return result
  }
  static func check(_ shot:TourShot,sightlines:TourSightlines,steps:Int,aspect:Double=16.0/9)->Bool {
    guard let subject=shot.subject,steps>0 else{return false}
    let samples=shot.endPosition==nil ? 1:steps
    for frame in 0...samples {
      let phase=shot.startPhase+Double(frame)/Double(samples)*(shot.endPhase-shot.startPhase)
      let camera=TourDirector.camera(shot,phase:phase)
      guard inFrame(subject.point,camera:camera,aspect:aspect),sightlines.visible(from:camera.0,to:subject.point) else{return false}
    }
    return true
  }
  static func apply(_ input:[TourShot],house:House,options:SceneOptions,aspect:Double=16.0/9)->(shots:[TourShot],excluded:[String]) {
    guard !input.isEmpty else{return ([],[])}
    let frames=input.reduce(0){$0+max(1,Int(($1.duration*30).rounded()))}
    var result:[TourShot]=[],excluded:[String]=[],cachedScope:SceneOptions?,cachedSightlines:TourSightlines?
    func context(_ shot:TourShot)->TourSightlines {
      var scope=options;scope.room=shot.roomID
      if let mode=shot.layerMode.flatMap(ViewMode.init(rawValue:)){scope.mode=mode;scope.stage=nil}
      if let names=shot.tradeNames{scope.trades=Set(names.compactMap(Trade.init(rawValue:)))}
      if cachedScope != scope {
        cachedSightlines=TourSightlines(features:SceneBuilder.features(house,options:scope),house:house);cachedScope=scope
      }
      return cachedSightlines!
    }
    for shot in input {
      let sightlines=context(shot)
      guard sightlines.complete else{excluded.append(shot.caption+": visible-surface budget exceeded");continue}
      if let subject=shot.subject,sightlines.candidates.contains(subject),check(shot,sightlines:sightlines,steps:32,aspect:aspect) {result.append(shot);continue}
      let mid=TourDirector.camera(shot,phase:(shot.startPhase+shot.endPhase)/2).0
      func orderedCandidates(near position:V3)->[TourSubject] {
        sightlines.candidates.enumerated().filter{entry in
          let distance=(entry.element.point-position).length;return distance>=0.35 && distance<=30
        }.sorted{a,b in
          let x=(a.element.point-position).length,y=(b.element.point-position).length
          return x==y ? a.offset<b.offset:x<y
        }.prefix(128).map{$0.element}
      }
      let candidates=orderedCandidates(near:mid)
      if let candidate=candidates.lazy.map({framed(shot,subject:$0)}).first(where:{check($0,sightlines:sightlines,steps:32,aspect:aspect)}) {
        result.append(candidate)
      }else if let candidate=orderedCandidates(near:TourDirector.camera(shot,phase:shot.startPhase).0).lazy.map({framed(held(shot),subject:$0)}).first(where:{check($0,sightlines:sightlines,steps:1,aspect:aspect)}) {
        var still=candidate;still.caption += " · viewpoint cut for subject visibility";result.append(still)
        excluded.append(shot.caption+": movement replaced by a clear stationary subject view")
      }else{excluded.append(shot.caption+": no visible subject inside the framing and distance limits")}
    }
    guard !result.isEmpty else{return ([],excluded)}
    let base=frames/result.count,remainder=frames%result.count
    for i in result.indices {result[i].duration=Double(base+(i<remainder ? 1:0))/30}
    result=TourDirector.boundedMotion(result).shots
    // Check every exported/rendered frame, including the endpoint. If a narrow
    // occluder falls between coarse samples, hold the already checked start.
    for i in result.indices {
      let sightlines=context(result[i]),count=max(1,Int((result[i].duration*30).rounded()))
      result[i].includesPlannedGeometry=sightlines.includesPlanned
      if !check(result[i],sightlines:sightlines,steps:count,aspect:aspect) {
        result[i]=held(result[i]);result[i].caption += " · viewpoint cut for frame visibility"
        excluded.append(result[i].caption+": the moving shot lost its visible subject")
        guard check(result[i],sightlines:sightlines,steps:1,aspect:aspect) else{return ([],excluded+["Tour framing changed during validation; no movie path was admitted."])}
      }
    }
    return (result,excluded)
  }
}
