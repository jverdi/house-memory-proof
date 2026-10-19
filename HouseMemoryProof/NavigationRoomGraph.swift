import Foundation

// A derived virtual-exploration graph, never evidence of a physical doorway or
// permission to walk. Every movement still passes the live clearance checks.
struct NavigationRoomGraph {
  struct Link {
    var fromRoom:UUID;var toRoom:UUID;var stage:UUID
    var fromObservation:UUID;var toObservation:UUID
    var from:V3;var to:V3
  }
  var links:[Link]=[]
  var examinedCandidates=0
  var limited=false
  func neighbours(of room:UUID)->Set<UUID> {
    Set(links.compactMap{$0.fromRoom==room ? $0.toRoom:$0.toRoom==room ? $0.fromRoom:nil})
  }
  private struct Cell:Hashable {var x:Int;var y:Int;var z:Int}
  private struct Pair:Hashable {var a:UUID;var b:UUID;var stage:UUID}
  private struct Anchor {var id:UUID;var room:UUID;var stage:UUID;var position:V3}
  static func build(house:House,options:SceneOptions,navigation:SpatialDisplayIndex,
    candidateLimit:Int=256,timeLimit:Double=1)throws->Self {
    var result=Self()
    guard candidateLimit>0,candidateLimit<=4096,timeLimit.isFinite,timeLimit>0,timeLimit<=5 else {
      result.limited=true;return result
    }
    // Visits without a common registration never acquire cross-room links.
    guard SceneBuilder.activeUnregisteredSegment(house,options:options)==nil else{return result}
    let started=ProcessInfo.processInfo.systemUptime
    let stages=SceneBuilder.eligibleStages(house,options:options)
    let registered=Set(house.segments.filter{$0.registration?.valid==true}.map{$0.id})
    let rooms=Set(house.rooms.filter{options.room==nil || $0.id==options.room}.map{$0.id})
    let selected=PoseRefinement.selectedForHouse(house).filter{
      $0.spatialPoseEligible && rooms.contains($0.roomID) && stages.contains($0.stageID) && registered.contains($0.segmentID)
    }.sorted{$0.timestamp==$1.timestamp ? $0.id.uuidString<$1.id.uuidString:$0.timestamp<$1.timestamp}
    // Uniform sampling bounds metadata work and keeps later rooms eligible.
    // An omitted candidate leaves a missing edge, never a fabricated passage.
    let strideCount=max(1,(selected.count+1999)/2000)
    result.limited=strideCount>1
    var anchors:[Anchor]=[]
    for (i,o) in selected.enumerated() where i%strideCount==0 {
      try Task.checkCancellation()
      let p=TourDirector.pose(o,house:house).0
      if RoomMapSnapshot.displayable(p) {anchors.append(Anchor(id:o.id,room:o.roomID,stage:o.stageID,position:p))}
    }
    var cells:[Cell:[Int]]=[:],candidates:[(Int,Int,Double)]=[]
    let maximumDistance=1.2
    for i in anchors.indices {
      try Task.checkCancellation()
      let a=anchors[i],p=a.position,key=Cell(x:Int(floor(p.x/maximumDistance)),y:Int(floor(p.y/maximumDistance)),z:Int(floor(p.z/maximumDistance)))
      let neighbours=(-1...1).flatMap { x in (-1...1).flatMap { y in (-1...1).map { z in Cell(x:key.x+x,y:key.y+y,z:key.z+z) } } }
      for neighbour in neighbours {
        for j in cells[neighbour] ?? [] {
          let b=anchors[j],distance=(a.position-b.position).length
          if a.room != b.room,a.stage==b.stage,distance>0.03,distance<=maximumDistance {
            candidates.append((j,i,distance))
            if candidates.count>=4096 {result.limited=true;break}
          }
        }
        if candidates.count>=4096 {break}
      }
      cells[key,default:[]].append(i)
      if candidates.count>=4096 || ProcessInfo.processInfo.systemUptime-started>timeLimit {result.limited=true;break}
    }
    candidates.sort{$0.2==$1.2 ? ($0.0==$1.0 ? $0.1<$1.1:$0.0<$1.0):$0.2<$1.2}
    var connected=Set<Pair>()
    for (i,j,_) in candidates {
      try Task.checkCancellation()
      let a=anchors[i],b=anchors[j]
      let key=Pair(a:min(a.room.uuidString,b.room.uuidString)==a.room.uuidString ? a.room:b.room,
        b:min(a.room.uuidString,b.room.uuidString)==a.room.uuidString ? b.room:a.room,stage:a.stage)
      // A retained link already resolves this room/stage pair. Duplicate
      // camera evidence needs no further clearance solve and cannot make a
      // completed graph appear incomplete when the work allowance is spent.
      if connected.contains(key) {continue}
      if result.examinedCandidates>=candidateLimit || ProcessInfo.processInfo.systemUptime-started>timeLimit {result.limited=true;break}
      result.examinedCandidates+=1
      let clearance=try SpatialClearance(index:navigation,camera:(a.position+b.position)*0.5,stageID:a.stage)
      guard clearance.complete,
        let from=clearance.standingPosition(from:a.position,eyeHeight:1.7),
        let to=clearance.standingPosition(from:b.position,eyeHeight:1.7),
        let forward=clearance.walkingDestination(from:from,toward:to,eyeHeight:1.7),
        let reverse=clearance.walkingDestination(from:to,toward:from,eyeHeight:1.7),
        (forward.position-to).length<0.001,(reverse.position-from).length<0.001 else{continue}
      // Every point of this short transition remains in the recorded camera
      // corridor, checked at the same 5 cm sampling used by the floor walker.
      let steps=max(1,Int(ceil((to-from).length/0.05)))
      var observed=true
      for step in 0...steps {
        let p=from+(to-from)*(Double(step)/Double(steps))
        if !NavigationGeometry.observed(p,positions:[a.position,b.position]) {observed=false;break}
      }
      guard observed else{continue}
      result.links.append(Link(fromRoom:a.room,toRoom:b.room,stage:a.stage,
        fromObservation:a.id,toObservation:b.id,from:from,to:to))
      connected.insert(key)
    }
    return result
  }
}

struct RoomStreamingContext {
  var rooms:[Room]
  var graph:NavigationRoomGraph
  var selectedRoom:UUID?
  var separateRoom:UUID?
  func priority(at camera:V3)->SpatialDisplayIndex.RoomPriority {
    let current=separateRoom ?? selectedRoom ?? RoomMapSnapshot.containingRoom(camera,in:rooms)?.id
    let level=rooms.first{$0.id==current}?.level
    return SpatialDisplayIndex.RoomPriority(current:current,connected:current.map{graph.neighbours(of:$0)} ?? [],
      sameFloor:Set(rooms.filter{level != nil && $0.level==level}.map{$0.id}))
  }
}
