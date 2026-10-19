import Foundation
import SceneKit
import UIKit
import simd

// Public analytic topology used only by owner diagnostics. This exercises the
// actual walk controller; it is neither reconstructed geometry nor field truth.
@MainActor enum NavigationBenchmark {
  private struct FloorPackage:Codable {var version=1;var flat:House;var gap:House}
  private struct Fixture {
    var house:House
    var stairIDs:[UUID]
    var routeRooms:[UUID]
  }

  private static func floorHeight(_ x:Double)->Double {
    if x<4 {return 0}
    if x>=10.4 {return 3.2}
    return Double(min(16,max(1,Int(floor((x-4)/0.4))+1))) * 0.2
  }

  private static func fixture()->Fixture {
    var h=House.empty("Analytic connected navigation");h.rooms=[]
    h.stages=[Stage(name:"Rough-in",kind:.synthetic,phase:.rough),
      Stage(name:"Finished",kind:.synthetic,phase:.finished)]
    let rough=h.stages[0].id
    for index in 0..<3 {
      h.rooms.append(Room(name:"Repeated room \(index+1)",level:0,
        origin:V3(-8+Double(index)*4,0,0),size:V3(4,4,3)))
    }
    h.rooms.append(Room(name:"Recorded stair",level:0,origin:V3(4,1,0),size:V3(6.4,2,6.2)))
    for index in 0..<3 {
      h.rooms.append(Room(name:"Repeated room \(index+1)",level:1,
        origin:V3(10.4+Double(index)*4,0,3.2),size:V3(4,4,3)))
    }
    // These stacked spaces have floors but no observed connection or camera
    // corridor. A geometrically plausible second level must not invent access.
    h.rooms.append(Room(name:"Unobserved upper room",level:1,origin:V3(0,0,3.2),size:V3(4,4,3)))
    h.rooms.append(Room(name:"Unobserved lower room",level:0,origin:V3(10.4,0,0),size:V3(4,4,3)))
    h.segments=h.rooms.map{Segment(roomID:$0.id,stageID:rough,registration:Rigid())}
    func box(_ name:String,_ trade:Trade,_ centre:V3,_ size:V3,_ room:Int)->Feature {
      Feature(name:name,trade:trade,roomID:h.rooms[room].id,stageID:rough,kind:.synthetic,
        mesh:.box(center:centre,size:size),segmentID:h.segments[room].id)
    }
    for index in h.rooms.indices where index != 3 {
      let room=h.rooms[index]
      h.features.append(box("Observed floor fixture",.floor,room.origin+V3(2,2,-0.05),V3(4,4,0.1),index))
      for y in [0.0,4.0] {
        h.features.append(box("Side wall fixture",.structure,room.origin+V3(2,y,1.5),V3(4,0.1,3),index))
      }
    }
    var stairIDs:[UUID]=[]
    for step in 0..<16 {
      let top=Double(step+1)*0.2
      let tread=box("Stair tread \(step+1)",.floor,V3(4.2+Double(step)*0.4,2,(top-0.1)/2),V3(0.4,2,top+0.1),3)
      stairIDs.append(tread.id);h.features.append(tread)
    }
    for (x,room,z) in [(-4.0,0,0.0),(0.0,1,0.0),(14.4,4,3.2),(18.4,5,3.2)] {
      for y in [0.75,3.25] {
        h.features.append(box("Door jamb fixture",.structure,V3(x,y,z+1.5),V3(0.1,1.5,3),room))
      }
      h.features.append(box("Door lintel fixture",.structure,V3(x,2,z+2.6),V3(0.1,1,0.8),room))
    }
    for sample in 0...148 {
      let x = -7.6+Double(sample)*0.2
      let room:Int=x<4 ? min(2,max(0,Int(floor((x+8)/4)))):
        x<10.4 ? 3:min(6,4+Int(floor((x-10.4)/4)))
      let height=floorHeight(x+0.2)+1.6
      var matrix=Rigid().values;matrix[3]=x;matrix[7]=height;matrix[11] = -2
      h.observations.append(Observation(roomID:h.rooms[room].id,stageID:rough,
        segmentID:h.segments[room].id,timestamp:Double(sample),image:"analytic-navigation.jpg",
        width:64,height:64,camera:matrix,intrinsics:[32,0,32,0,32,32,0,0,1],
        tracking:"synthetic",light:1000,sharpness:0.1))
    }
    return Fixture(house:h,stairIDs:stairIDs,routeRooms:Array(h.rooms.prefix(7).map{$0.id}))
  }

  private static func prepared(_ house:House,_ start:V3,options:SceneOptions=SceneOptions())->WalkController {
    let controller=WalkController();controller.load(house,options)
    controller.flying=false;controller.orbit=false;controller.yaw=0;controller.pitch=0
    controller.camera.simdPosition=start.render
    return controller
  }

  static func savedViewpointScope()throws->Bool {
    let h=fixture().house,original=h
    let walk=WalkController();defer{walk.stop()}
    var options=SceneOptions();options.stage=h.stages[0].id
    walk.load(h,options);walk.setFlying(true)
    let room=h.rooms[4],position=room.origin+V3(2,2,1.7)
    walk.canonicalPosition=position;walk.yaw=0.4;walk.pitch = -0.2
    walk.camera.eulerAngles=SCNVector3(walk.pitch,walk.yaw,0)
    let mark=try walk.makeBookmark(name:"Upper room")
    guard mark.roomID==room.id,mark.segmentID==nil,(mark.position-position).length<1e-5,
      abs(mark.yaw-0.4)<1e-5,abs(mark.pitch+0.2)<1e-5 else{return false}
    // A different orbit camera must be captured, including its orientation.
    let overview=SceneBuilder.camera(at:position+V3(0.5,0.2,0.1))
    overview.eulerAngles=SCNVector3(0.3,-0.7,0)
    walk.view.scene?.rootNode.addChildNode(overview)
    walk.setOrbit(true);walk.view.pointOfView=overview
    let orbitMark=try walk.makeBookmark(name:"Displayed orbit view")
    guard orbitMark.roomID==room.id,(orbitMark.position-(position+V3(0.5,0.2,0.1))).length<1e-5,
      abs(orbitMark.yaw+0.7)<1e-5,abs(orbitMark.pitch-0.3)<1e-5 else{return false}
    overview.eulerAngles=SCNVector3(1.5,0,0)
    do {_=try walk.makeBookmark(name:"Steep overview");return false}catch{}
    overview.eulerAngles=SCNVector3(0.3,-0.7,0.2)
    do {_=try walk.makeBookmark(name:"Tilted overview");return false}catch{}
    walk.bookmark(orbitMark)
    guard !walk.orbit,(walk.canonicalPosition-orbitMark.position).length<1e-5 else{return false}
    walk.canonicalPosition=V3(100,100,100)
    do {_=try walk.makeBookmark(name:"Outside");return false}catch{}
    options.room=h.rooms[0].id;walk.load(h,options);walk.setFlying(true);walk.canonicalPosition=position
    do {_=try walk.makeBookmark(name:"Outside selected room");return false}catch{}
    // A visit without alignment uses its visit's room, never design bounds.
    var local=h;local.segments[4].registration=nil;local.revision+=1
    options.room=room.id;walk.load(local,options);walk.setFlying(true)
    walk.canonicalPosition=V3(200,200,1.5)
    let visit=try walk.makeBookmark(name:"Unaligned visit")
    return visit.roomID==room.id && visit.segmentID==local.segments[4].id &&
      (visit.position-V3(200,200,1.5)).length<1e-5 && h==original
  }

  static func reconstructedFloor(repo:Repository) async throws->[String:Any] {
    let flatInput=try SimulatedCapture.navigationFloor(repo:repo,missingStrip:false)
    let gapInput=try SimulatedCapture.navigationFloor(repo:repo,missingStrip:true)
    guard flatInput.features.isEmpty,gapInput.features.isEmpty else{throw HouseError.message("Navigation fixture supplied generator geometry.")}
    let flatSurface=try await SurfaceReconstruction.build(house:flatInput,segment:flatInput.segments[0],repo:repo){_ in}
    let gapSurface=try await SurfaceReconstruction.build(house:gapInput,segment:gapInput.segments[0],repo:repo){_ in}
    guard flatSurface.resolvedGeometrySource == .depthFusion,gapSurface.resolvedGeometrySource == .depthFusion,
      flatSurface.trade == .unknown,gapSurface.trade == .unknown,
      flatSurface.mesh.vertices.count<DisplayGeometry.sceneVertexBudget,gapSurface.mesh.vertices.count<DisplayGeometry.sceneVertexBudget else{
      throw HouseError.message("Reconstructed floor output is missing or exceeds this bounded fixture.")
    }
    var unclassified=flatInput;unclassified.features=[flatSurface]
    let walk=WalkController();defer{walk.stop()};walk.load(unclassified,SceneOptions());walk.setFlying(false)
    let unclassifiedRefused=walk.flying
    var flat=flatInput;var floor=flatSurface;floor.trade = .floor;flat.features=[floor];flat.revision+=1
    let start=V3(-0.4,0,2)
    walk.load(flat,SceneOptions());walk.bookmark(Bookmark(name:"Supported floor",position:start,yaw:0,pitch:0,roomID:flat.rooms[0].id));walk.setFlying(false)
    let classifiedWalkEnabled = !walk.flying
    func point(_ p:V3)->[String:Double] {["x":p.x,"y":p.y,"z":p.z]}
    var trace:[[String:Double]]=[],completed=0
    for direction in [1.0,-1.0] {for _ in 0..<4 {
      let before=V3(ar:walk.camera.simdPosition);walk.stepMove(SIMD2(Float(direction),0));let after=V3(ar:walk.camera.simdPosition)
      if abs(after.x-before.x-direction*0.2)<0.0001 && abs(after.y)<0.0001 && abs(after.z-2)<0.003 {completed+=1}
      trace.append(point(after))
    }}
    var gap=gapInput;var gapFloor=gapSurface;gapFloor.trade = .floor;gap.features=[gapFloor]
    let blocked=WalkController();defer{blocked.stop()};blocked.load(gap,SceneOptions())
    blocked.bookmark(Bookmark(name:"Before missing floor",position:start,yaw:0,pitch:0,roomID:gap.rooms[0].id));blocked.setFlying(false)
    let gapStartWalkEnabled = !blocked.flying
    var gapTrace:[[String:Double]]=[]
    for _ in 0..<3 {blocked.stepMove(SIMD2(1,0));gapTrace.append(point(V3(ar:blocked.camera.simdPosition)))}
    blocked.setFlying(true)
    for _ in 0..<4 {blocked.stepMove(SIMD2(1,0))}
    let freeFlyPosition=V3(ar:blocked.camera.simdPosition);blocked.setFlying(false)
    let landedWalkEnabled = !blocked.flying
    let preserved=flat.observations==flatInput.observations && gap.observations==gapInput.observations &&
      floor.mesh==flatSurface.mesh && gapFloor.mesh==gapSurface.mesh && walk.house==flat && blocked.house==gap
    try flat.validate();try gap.validate()
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let package=try encoder.encode(FloorPackage(flat:flat,gap:gap))
    try DurableFiles.write(package,to:repo.root.appendingPathComponent("reconstructed-navigation-private.json"))
    let passed=unclassifiedRefused && classifiedWalkEnabled && completed==8 && gapStartWalkEnabled &&
      gapTrace.allSatisfy{abs(($0["x"] ?? .infinity)+0.4)<0.0001 && abs($0["y"] ?? .infinity)<0.0001 && abs(($0["z"] ?? .infinity)-2)<0.003} &&
      (freeFlyPosition-V3(0.4,0,2)).length<0.0001 && landedWalkEnabled && preserved
    return ["version":1,"profile":"analytic-reconstructed-floor-v1","passed":passed,
      "privatePackageSHA256":TourProvenance.digest(package),"generatorMeshesSupplied":0,
      "flatVertices":floor.mesh.vertices.count,"gapVertices":gapFloor.mesh.vertices.count,"capturedViewsPerFragment":9,
      "unclassifiedRefused":unclassifiedRefused,"classifiedWalkEnabled":classifiedWalkEnabled,
      "completedSteps":completed,"trace":trace,"gapStartWalkEnabled":gapStartWalkEnabled,"gapTrace":gapTrace,
      "afterExplicitFreeFly":point(freeFlyPosition),"landedWalkEnabled":landedWalkEnabled,"sourceGeometryUnchanged":preserved,
      "wholeHouseQualified":false,"physicalQualification":false,"protectedBenchmark":false,
      "limitations":"Two bounded synthetic depth fragments through production reconstruction and walking. Explicit floor classification is supplied by the diagnostic. This does not qualify automatic floor recognition, whole-house registration/navigation, sustained rendering or physical accuracy."]
  }

  // Three independent RGB-D fragments with explicitly supplied registration.
  // This isolates reconstruction -> registered navigation, not registration
  // estimation, whole-house diversity or protected/physical qualification.
  static func reconstructedRooms(repo:Repository) async throws->[String:Any] {
    var inputs:[House]=[],surfaces:[Feature]=[]
    let offsets=[V3(),V3(1.2,0,0),V3(0,0,3.2)]
    for index in offsets.indices {
      var input=try SimulatedCapture.navigationFloor(repo:repo,missingStrip:false)
      if let first=inputs.first {
        input.stages=first.stages
        input.segments[0].stageID=first.stages[0].id
        for i in input.observations.indices {input.observations[i].stageID=first.stages[0].id}
      }
      input.rooms[0].name="Reconstructed fragment \(index+1)"
      input.rooms[0].origin=offsets[index]+V3(-0.8,-0.6,0)
      input.rooms[0].size=V3(1.6,1.2,3)
      input.rooms[0].level=index==2 ? 1:0
      var registration=Rigid();registration.values[3]=offsets[index].x;registration.values[11]=offsets[index].z
      input.segments[0].registration=registration
      guard input.features.isEmpty else{throw HouseError.message("Fixture supplied generator meshes.")}
      var surface=try await SurfaceReconstruction.build(house:input,segment:input.segments[0],repo:repo){_ in}
      guard surface.resolvedGeometrySource == .depthFusion,surface.trade == .unknown else{throw HouseError.message("Expected unclassified reconstruction output.")}
      surface.trade = .floor
      inputs.append(input);surfaces.append(surface)
    }
    var h=inputs[0];h.name="Registered reconstructed navigation fragments"
    h.rooms=inputs.flatMap{$0.rooms};h.segments=inputs.flatMap{$0.segments}
    h.observations=inputs.flatMap{$0.observations};h.features=surfaces;h.revision+=1
    try h.validate()
    guard h.features.reduce(0,{$0+DisplayGeometry.cost($1.mesh)})<=DisplayGeometry.sceneVertexBudget else {
      throw HouseError.message("Registered-fragment fixture exceeds its synchronous display budget.")
    }
    func graph(_ house:House)throws->NavigationRoomGraph {
      let navigation=try SpatialDisplayIndex(features:NavigationGeometry.collisionFeatures(house,options:SceneOptions()))
      return try NavigationRoomGraph.build(house:house,options:SceneOptions(),navigation:navigation)
    }
    let links=try graph(h)
    // Retain only room ordinals in the public report; raw capture IDs stay local.
    let roomPairs=links.links.map{link in [h.rooms.firstIndex(where:{$0.id==link.fromRoom}) ?? -1,
      h.rooms.firstIndex(where:{$0.id==link.toRoom}) ?? -1].sorted()}.sorted{$0.lexicographicallyPrecedes($1)}
    var unsupported=h;unsupported.features[1].trade = .unknown;unsupported.revision+=1
    let walk=WalkController();defer{walk.stop()};walk.load(h,SceneOptions())
    walk.bookmark(Bookmark(name:"Reconstructed lower floor",position:V3(-0.2,0,2),yaw:0,pitch:0,roomID:h.rooms[0].id))
    walk.setFlying(false)
    let walkingEnabled = !walk.flying
    func point(_ p:V3)->[String:Double] {["x":p.x,"y":p.y,"z":p.z]}
    var trace:[[String:Double]]=[],completed=0
    for direction in [1.0,-1.0] {for _ in 0..<8 {
      let before=walk.canonicalPosition;walk.stepMove(SIMD2(Float(direction),0));let after=walk.canonicalPosition
      if abs(after.x-before.x-direction*0.2)<0.0001,abs(after.y)<0.0001,abs(after.z-2)<0.003 {completed+=1}
      trace.append(point(after))
    }}
    walk.jump(h.rooms[2]);walk.setFlying(false)
    let upper=walk.canonicalPosition,upperWalkingEnabled = !walk.flying
    let blocked=WalkController();defer{blocked.stop()};blocked.load(unsupported,SceneOptions())
    blocked.bookmark(Bookmark(name:"Before unsupported room",position:V3(0.4,0,2),yaw:0,pitch:0,roomID:h.rooms[0].id));blocked.setFlying(false)
    var missingFloorTrace:[[String:Double]]=[]
    let refusalWalkingEnabled = !blocked.flying
    for _ in 0..<3 {blocked.stepMove(SIMD2(1,0));missingFloorTrace.append(point(blocked.canonicalPosition))}
    let missingFloorRefused=refusalWalkingEnabled && missingFloorTrace.allSatisfy{abs(($0["x"] ?? .infinity)-0.4)<0.0001 && abs($0["y"] ?? .infinity)<0.0001 && abs(($0["z"] ?? .infinity)-2)<0.003}
    let preserved=walk.house==h && blocked.house==unsupported && zip(h.features,surfaces).allSatisfy{$0.mesh==$1.mesh} && h.observations==inputs.flatMap{$0.observations}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let package=try encoder.encode(h)
    try DurableFiles.write(package,to:repo.root.appendingPathComponent("reconstructed-rooms-private.json"))
    let passed=walkingEnabled && completed==16 && !links.limited && roomPairs==[[0,1]] &&
      missingFloorRefused && upperWalkingEnabled && abs(upper.z-5.2)<0.003 && preserved
    return ["version":1,"profile":"registered-reconstructed-fragments-v1","passed":passed,
      "privatePackageSHA256":TourProvenance.digest(package),"fragments":3,"capturedViewsPerFragment":9,
      "vertices":surfaces.map{$0.mesh.vertices.count},"generatorMeshesSupplied":0,
      "registrationSupplied":true,"floorClassificationSupplied":true,"links":roomPairs,
      "graphLimited":links.limited,"missingFloorRefused":missingFloorRefused,"missingFloorTrace":missingFloorTrace,
      "walkingEnabled":walkingEnabled,"completedSteps":completed,"trace":trace,
      "upperFloorJump":point(upper),"upperWalkingEnabled":upperWalkingEnabled,"sourceGeometryUnchanged":preserved,
      "wholeHouseQualified":false,"physicalQualification":false,"protectedBenchmark":false]
  }

  static func comfortWalk()throws->Bool {
    let sourceFixture=fixture(),house=sourceFixture.house
    for height in [0.8,1.7] {
      let walk=prepared(house,V3(-7,2,1.6));defer{walk.stop()}
      var settings=ViewerComfort();settings.eyeHeight=height;walk.applyComfort(settings)
      guard !walk.flying else{throw HouseError.message("Comfort height \(height) did not establish supported walking.")}
      for direction in [1.0,-1.0] {for _ in 0..<142 {
        let before=V3(ar:walk.camera.simdPosition);walk.stepMove(SIMD2(Float(direction),0))
        let after=V3(ar:walk.camera.simdPosition),requested=before.x+direction*0.2
        let low=floorHeight(after.x+0.2-0.0001)+height,high=floorHeight(after.x+0.2+0.0001)+height
        guard abs(after.x-requested)<0.0001,abs(after.y-2)<0.0001,after.z>=low-0.0001,after.z<=high+0.0001 else {
          throw HouseError.message("Comfort height \(height) failed its connected room/stair route at \(requested).")
        }
      }}
      guard walk.house==house else{throw HouseError.message("Viewer preferences changed captured records.")}
    }
    let tall=prepared(house,V3(-5.4,2,1.6));defer{tall.stop()}
    var settings=ViewerComfort();settings.eyeHeight=2.2;tall.applyComfort(settings)
    guard !tall.flying else{return false}
    var moved=0,refused=0
    for _ in 0..<16 {
      let before=tall.camera.simdPosition;tall.stepMove(SIMD2(1,0))
      if simd_length(tall.camera.simdPosition-before)<0.00001 {refused+=1}else{moved+=1}
      guard V3(ar:tall.camera.simdPosition).x <= -4.25 else{return false}
    }
    return moved>0 && refused>0 && tall.house==house
  }

  static func checkedRoomLinks()throws->Bool {
    let h=fixture().house
    func graph(_ house:House,_ options:SceneOptions=SceneOptions(),limit:Int=256)throws->NavigationRoomGraph {
      let index=try SpatialDisplayIndex(features:NavigationGeometry.collisionFeatures(house,options:options))
      let result=try NavigationRoomGraph.build(house:house,options:options,navigation:index,candidateLimit:limit)
      if limit==256,result.limited {throw HouseError.message("Room-link diagnostic exhausted its unchanged work budget after \(result.examinedCandidates) candidates.")}
      return result
    }
    func pair(_ a:UUID,_ b:UUID)->String {[a.uuidString,b.uuidString].sorted().joined(separator:"/")}
    let expected=Set((0..<6).map{pair(h.rooms[$0].id,h.rooms[$0+1].id)})
    let baseline=try graph(h)
    guard !baseline.limited,Set(baseline.links.map{pair($0.fromRoom,$0.toRoom)})==expected,
      baseline.links.allSatisfy({link in h.observations.contains{$0.id==link.fromObservation} && h.observations.contains{$0.id==link.toObservation}}) else {
      throw HouseError.message("Checked room graph did not retain the six observed room/stair transitions; links \(baseline.links.count), limited \(baseline.limited).")
    }
    // A one-pair graph finishes with exactly one expensive candidate check.
    // Repeated observations of that same connection do not consume a second
    // check or turn complete work into a limited result. The full graph below
    // still reports limitation when its one-check budget leaves other pairs.
    var singlePair=h;singlePair.rooms=Array(h.rooms.prefix(2))
    let pairRooms=Set(singlePair.rooms.map{$0.id})
    singlePair.segments.removeAll{!pairRooms.contains($0.roomID)}
    singlePair.observations.removeAll{!pairRooms.contains($0.roomID)}
    singlePair.features.removeAll{!pairRooms.contains($0.roomID)}
    let exactBudget=try graph(singlePair,limit:1)
    guard !exactBudget.limited,exactBudget.examinedCandidates==1,
      Set(exactBudget.links.map{pair($0.fromRoom,$0.toRoom)})==Set([pair(h.rooms[0].id,h.rooms[1].id)]) else {
      throw HouseError.message("Resolved duplicate room evidence consumed another candidate check.")
    }
    var blocked=h
    blocked.features.append(Feature(name:"Closed recorded door",trade:.structure,roomID:h.rooms[1].id,
      stageID:h.stages[0].id,kind:.synthetic,mesh:.box(center:V3(0,2,1.2),size:V3(0.1,1,2.4)),segmentID:h.segments[1].id))
    let forbidden=pair(h.rooms[1].id,h.rooms[2].id)
    let closed=try graph(blocked)
    guard Set(closed.links.map{pair($0.fromRoom,$0.toRoom)})==expected.subtracting([forbidden]) else{return false}
    var hidden=SceneOptions();hidden.trades=[]
    guard Set(try graph(blocked,hidden).links.map{pair($0.fromRoom,$0.toRoom)})==expected.subtracting([forbidden]) else{return false}
    var gap=h;gap.observations.removeAll{abs($0.camera[3])<0.8}
    guard !(try graph(gap).links.contains{pair($0.fromRoom,$0.toRoom)==forbidden}) else{return false}
    var missing=h;missing.features.removeAll{$0.trade == .floor}
    guard try graph(missing).links.isEmpty else{return false}
    var planned=h
    for i in planned.features.indices where planned.features[i].trade == .floor {planned.features[i].kind = .planned}
    guard try graph(planned).links.isEmpty else{return false}
    var separate=h;separate.segments[2].registration=nil
    guard try graph(separate).links.isEmpty else{return false}
    var mixed=h
    let newSegments=h.rooms.map{Segment(roomID:$0.id,stageID:h.stages[1].id,registration:Rigid())}
    mixed.segments+=newSegments
    for original in h.observations {
      var view=original;view.id=UUID();view.stageID=h.stages[1].id
      view.segmentID=newSegments.first{$0.roomID==view.roomID}!.id;mixed.observations.append(view)
    }
    var all=SceneOptions();all.mode = .evidence
    let mixedGraph=try graph(mixed,all)
    guard mixedGraph.links.count==6,mixedGraph.links.allSatisfy({$0.stage==h.stages[0].id}) else{return false}
    let limited=try graph(h,limit:1)
    return limited.limited && limited.links.count<=1 && baseline.neighbours(of:h.rooms[7].id).isEmpty && baseline.neighbours(of:h.rooms[8].id).isEmpty
  }

  static func roomStreamingPriority()throws->Bool {
    let rooms=(0..<4).map{_ in UUID()},stage=UUID()
    let values:[(Int,Double,Trade)]=[(0,7,.structure),(1,6,.structure),(2,5,.structure),(3,4.5,.structure),(3,1,.structure),(0,6.5,.electrical)]
    let features=values.map{room,x,trade in Feature(name:"Room priority source",trade:trade,roomID:rooms[room],stageID:stage,kind:.synthetic,
      mesh:Mesh(vertices:[V3(x,0,1),V3(x,0.1,1),V3(x,0,1.1)],triangles:[0,1,2]))}
    let index=try SpatialDisplayIndex(features:features)
    let context=SpatialDisplayIndex.RoomPriority(current:rooms[0],connected:[rooms[1]],sameFloor:[rooms[0],rooms[1],rooms[2]])
    let plan=index.plan(camera:V3(0,0,1),budget:18,residents:6,rooms:context)
    guard plan.map{index.tiles[$0.tile].feature}==[4,0,5,1,2,3],plan.reduce(0,{$0+$1.budget})<=18 else{return false}
    let tight=index.plan(camera:V3(0,0,1),budget:6,residents:2,rooms:context)
    guard tight.map{index.tiles[$0.tile].feature}==[4,0] else{return false}
    let other=SpatialDisplayIndex.RoomPriority(current:rooms[1],connected:[rooms[0]],sameFloor:[rooms[0],rooms[1],rooms[2]])
    let moved=index.plan(camera:V3(0,0,1),budget:6,residents:2,rooms:other)
    return moved.map{index.tiles[$0.tile].feature}==[4,1] && index.features==features
  }

  static func sourcePickingSemantics()throws->Bool {
    let anchor=V3(50000,-40000,2),room=UUID(),stage=UUID(),scene=SceneBuilder.baseScene()
    var textures:[String:UIImage]=[:]
    let target=anchor+V3(0,0.00025,0.00025)
    let far=Feature(name:"Small surface",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,
      mesh:Mesh(vertices:[anchor,anchor+V3(0,0.001,0),anchor+V3(0,0,0.001)],triangles:[0,1,2]))
    var near=far;near.id=UUID();near.mesh.vertices=near.mesh.vertices.map{$0+V3(0.1,0,0)}
    let farNode=SceneBuilder.node(far,mesh:far.mesh,uv:nil,options:SceneOptions(),textures:&textures,renderOrigin:anchor)
    let nearNode=SceneBuilder.node(near,mesh:near.mesh,uv:nil,options:SceneOptions(),textures:&textures,renderOrigin:anchor)
    scene.rootNode.addChildNode(farNode);scene.rootNode.addChildNode(nearNode)
    func hit()->SceneBuilder.SourceHit? {SceneBuilder.pick(scene,from:target+V3(0.2,0,0),to:target-V3(0.2,0,0))}
    guard let first=hit(),first.id==near.id,(first.position-(target+V3(0.1,0,0))).length<0.000002 else{return false}
    nearNode.isHidden=true;guard hit()?.id==far.id else{return false}
    nearNode.isHidden=false;nearNode.opacity=0;guard hit()?.id==far.id else{return false}
    nearNode.opacity=1;nearNode.removeFromParentNode();guard hit()?.id==far.id else{return false}
    guard SceneBuilder.pick(scene,from:target+V3(0.2,0.01,0),to:target+V3(-0.2,0.01,0))==nil,
      SceneBuilder.pick(scene,from:V3(.nan,0,0),to:target)==nil else{return false}
    farNode.removeFromParentNode();return hit()==nil
  }

  static func localRenderCoordinates()throws->Bool {
    var house=House.empty("Local render coordinates");house.isDemo=true
    house.rooms=[Room(name:"Positive source frame",level:0,origin:V3(50000,40000,0),size:V3(4,4,3)),
      Room(name:"Negative source frame",level:0,origin:V3(-50000,-40000,0),size:V3(4,4,3))]
    house.features=house.rooms.map {room in
      Feature(name:"Source floor",trade:.floor,roomID:room.id,stageID:house.stages[0].id,kind:.synthetic,
        mesh:.box(center:room.origin+V3(2,2,-0.05),size:V3(4,4,0.1)))
    }
    let point=house.rooms[0].origin+V3(3.8,3,2),target=point+V3(0,0.00025,0.00025)
    let feature=Feature(name:"One millimetre source detail",trade:.structure,roomID:house.rooms[0].id,
      stageID:house.stages[0].id,kind:.synthetic,
      mesh:Mesh(vertices:[point,point+V3(0,0.001,0),point+V3(0,0,0.001)],triangles:[0,1,2]))
    house.features.append(feature);try house.validate()
    let walk=WalkController();defer{walk.stop()};walk.applyComfort(ViewerComfort());walk.load(house,SceneOptions())
    guard !walk.flying,(walk.canonicalPosition-(house.rooms[0].origin+V3(2,2,1.7))).length<0.000001,
      walk.renderOrigin.length>10000,simd_length(walk.camera.simdPosition)<1 else{throw HouseError.message("Local render check failed: initial supported spawn or render origin.")}
    walk.yaw=0;walk.stepMove(SIMD2(1,0))
    guard abs(walk.canonicalPosition.x-50002.2)<0.000001 else{throw HouseError.message("Local render check failed: canonical step position.")}
    let bookmark=Bookmark(name:"Precise saved source pose",position:V3(50002.123456,40002.345678,1.7),
      yaw:0.2,pitch:0,roomID:house.rooms[0].id)
    walk.bookmark(bookmark)
    guard (walk.canonicalPosition-bookmark.position).length<0.000001,
      let node=walk.view.scene?.rootNode.childNode(withName:feature.id.uuidString,recursively:false) as? SourceGeometryNode,
      node.canonicalAnchor==point,let source=node.geometry?.sources(for:.vertex).first,
      source.vectorCount==3,source.bytesPerComponent==4,source.componentsPerVector==3 else{throw HouseError.message("Local render check failed: bookmark pose or geometry-source layout.")}
    let vertices:[SIMD3<Float>]=source.data.withUnsafeBytes { data in
      (0..<3).map { i in
        let offset=source.dataOffset+i*source.dataStride
        return SIMD3(data.loadUnaligned(fromByteOffset:offset,as:Float.self),
          data.loadUnaligned(fromByteOffset:offset+4,as:Float.self),data.loadUnaligned(fromByteOffset:offset+8,as:Float.self))
      }
    }
    guard abs(Double(simd_length(vertices[1]-vertices[0]))-0.001)<0.0000001,
      abs(Double(simd_length(vertices[2]-vertices[0]))-0.001)<0.0000001 else{throw HouseError.message("Local render check failed: millimetre vertex separation.")}
    // Visible source surfaces use two-sided materials. Picking must match
    // that display from either side, without loosening the coordinate bound.
    for side in [-1.0,1.0] {
      let hit=SceneBuilder.pick(walk.view.scene!,from:target+V3(side*0.2,0,0),to:target+V3(-side*0.2,0,0))
      guard let hit,hit.id==feature.id,(hit.position-target).length<0.000002 else {
        throw HouseError.message("Local render source picking failed from side \(side).")
      }
    }
    walk.points=[target];walk.drawPoints()
    walk.setOrbit(true);walk.jump(house.rooms[1])
    guard !walk.orbit,!walk.flying,(walk.canonicalPosition-(house.rooms[1].origin+V3(2,2,1.7))).length<0.000001 else{throw HouseError.message("Local render check failed: distant orbit-to-room jump.")}
    walk.bookmark(bookmark)
    guard (walk.canonicalPosition-bookmark.position).length<0.000001,
      let marker=walk.view.scene?.rootNode.childNode(withName:"selection-points",recursively:false)?.childNodes.first,
      (walk.canonicalPoint(marker.simdWorldPosition)-target).length<0.000002 else{throw HouseError.message("Local render check failed: restored bookmark or selection marker.")}
    let index=try SpatialDisplayIndex(features:[feature]),scene=SceneBuilder.baseScene()
    let stream=SpatialSceneStream(index:index,scene:scene,options:SceneOptions());stream.renderOrigin=point
    stream.update(camera:point,time:0)
    guard let tile=stream.nodes[0] as? SourceGeometryNode,tile.canonicalAnchor==point,
      simd_length(tile.simdPosition)<0.000001,tile.name==feature.id.uuidString else{throw HouseError.message("Local render check failed: streamed tile anchor or identity.")}
    return walk.house==house && index.features==[feature]
  }

  static func directionalStreaming()throws->Bool {
    let room=UUID(),stage=UUID()
    let features=[1.0,-8.0,8.0].enumerated().map { i,x in
      Feature(name:"Directional source \(i)",trade:.structure,roomID:room,stageID:stage,kind:.synthetic,
        mesh:Mesh(vertices:[V3(x,0.2,1),V3(x+0.2,0.2,1),V3(x,0.4,1)],triangles:[0,1,2]))
    }
    let index=try SpatialDisplayIndex(features:features),camera=V3(0,0,1)
    guard index.tiles.count==3 else{return false}
    func featureOrder(_ plan:[SpatialDisplayIndex.Allocation])->[Int] {plan.map{index.tiles[$0.tile].feature}}
    let stationary=index.plan(camera:camera,budget:6,residents:2)
    let forward=index.plan(camera:camera,velocity:V3(3,0,0),budget:6,residents:2)
    let backward=index.plan(camera:camera,velocity:V3(-3,0,0),budget:6,residents:2)
    guard featureOrder(stationary)==[0,1],featureOrder(forward)==[0,2],featureOrder(backward)==[0,1],
      forward.reduce(0,{$0+$1.budget})<=6,backward.reduce(0,{$0+$1.budget})<=6,
      index.plan(camera:camera,velocity:V3(.nan,0,0),budget:6,residents:2)==stationary,
      abs(SpatialDisplayIndex.prefetchOffset(velocity:V3(1000,1000,0)).length-6)<1e-9,
      SpatialDisplayIndex.prefetchOffset(velocity:V3(0.01,0,0))==V3() else{return false}
    var local=features[0];local.id=UUID();local.mesh.vertices=local.mesh.vertices.map{$0+V3(2.5,0,0)}
    let crowded=try SpatialDisplayIndex(features:features+[local])
    let protected=crowded.plan(camera:camera,velocity:V3(4,0,0),budget:6,residents:2)
    guard protected.map({crowded.tiles[$0.tile].feature})==[0,3] else{return false}
    for allocation in forward+backward {
      let (feature,mesh,_)=index.materialize(allocation)
      guard feature==features[index.tiles[allocation.tile].feature],mesh==feature.mesh else{return false}
    }
    // Use the actual one-tile-per-frame loader. A reversal at the same camera
    // position must reprioritize unfinished work without replacing nearby nodes.
    let stream=SpatialSceneStream(index:index,scene:SceneBuilder.baseScene(),options:SceneOptions())
    stream.update(camera:camera,time:0)
    guard let close=stream.nodes[0],stream.nodes.count==1 else{return false}
    stream.update(camera:camera,time:0.6,velocity:V3(3,0,0))
    guard stream.nodes[0]===close,stream.nodes[2] != nil,stream.nodes[1]==nil else{return false}
    stream.update(camera:camera,time:1.2,velocity:V3(-3,0,0))
    guard stream.nodes[0]===close,stream.nodes.count==3,stream.pending.isEmpty else{return false}
    let before=stream.nodes
    stream.update(camera:camera,time:1.8)
    stream.update(camera:V3(.nan,0,0),time:2.4)
    return stream.pending.isEmpty && stream.nodes.count==3 && before.allSatisfy{stream.nodes[$0.key]===$0.value}
      && stream.nodes.allSatisfy{$0.value.name==features[index.tiles[$0.key].feature].id.uuidString}
      && index.features==features
  }

  static func streamedRoomJumps() async throws->[String:Any] {
    var house=House.empty("Streamed destination handoff");house.isDemo=true
    house.rooms=[Room(name:"Near room",level:0,origin:V3(),size:V3(4,4,3)),
      Room(name:"Distant room",level:0,origin:V3(100,0,0),size:V3(4,4,3))]
    let stage=house.stages[0].id
    house.features=house.rooms.map { room in
      Feature(name:"Observed floor fixture",trade:.floor,roomID:room.id,stageID:stage,kind:.synthetic,
        mesh:.box(center:room.origin+V3(2,2,-0.05),size:V3(4,4,0.1)))
    }
    // The public streaming path is selected by actual inventory size. Distant
    // source points do not provide floor support or a fabricated connection.
    for i in 0..<512 {
      house.features.append(Feature(name:"Distant point fixture",trade:.structure,roomID:house.rooms[0].id,stageID:stage,
        kind:.synthetic,mesh:Mesh(vertices:[V3(200+Double(i)*0.01,20,1)],triangles:[])))
    }
    try house.validate();let original=house
    let walk=WalkController();defer{walk.stop()};walk.applyComfort(ViewerComfort());walk.load(house,SceneOptions())
    func settled() async throws {
      for _ in 0..<300 {
        try Task.checkCancellation()
        if !walk.isPreparingNavigation {return}
        try await Task.sleep(nanoseconds:10_000_000)
      }
      throw HouseError.message("Streamed destination did not finish within the bounded diagnostic.")
    }
    try await settled()
    guard !walk.flying else{throw HouseError.message("Initial streamed floor was not admitted.")}
    walk.jump(house.rooms[1])
    let pending=V3(ar:walk.camera.simdPosition)
    guard walk.isPreparingNavigation,abs(pending.x-102)<0.0001 else{throw HouseError.message("Distant room jump reused the previous room's floor.")}
    walk.stepMove(SIMD2(1,0))
    guard (V3(ar:walk.camera.simdPosition)-pending).length<0.0001 else{throw HouseError.message("Movement began before destination clearance was ready.")}
    try await settled()
    guard !walk.flying,abs(V3(ar:walk.camera.simdPosition).x-102)<0.0001 else{throw HouseError.message("Destination validation displaced a supported room jump.")}
    walk.yaw=0;walk.stepMove(SIMD2(1,0))
    guard abs(V3(ar:walk.camera.simdPosition).x-102.2)<0.0001 else{throw HouseError.message("Walking did not resume on the destination floor.")}
    // Supersede in-flight work before yielding; the cancelled room must not
    // overwrite the latest request or move the camera back after completion.
    walk.jump(house.rooms[0]);walk.jump(house.rooms[1]);walk.jump(house.rooms[0])
    try await settled();try await Task.sleep(nanoseconds:20_000_000)
    guard !walk.flying,abs(V3(ar:walk.camera.simdPosition).x-2)<0.0001,walk.house==original else{throw HouseError.message("A stale collision task replaced the latest room jump.")}
    let missingRoom=house.rooms[1].id
    house.features.removeAll{$0.roomID==missingRoom};house.revision+=1
    walk.load(house,SceneOptions());try await settled();walk.jump(house.rooms[1]);try await settled()
    let missingFloorRefused=walk.flying && abs(V3(ar:walk.camera.simdPosition).x-102)<0.0001
    return ["test":"Distant room jumps wait for destination collision geometry","passed":missingFloorRefused && walk.house==house,
      "rooms":2,"separationMetres":100,"movementPausedDuringHandoff":true,"latestDestinationPreserved":true,
      "missingFloorRefused":missingFloorRefused,"sourceRecordsUnchanged":walk.house==house,
      "wholeHouseQualified":false,"physicalQualification":false]
  }

  static func run()throws->[String:Any] {
    let original=fixture();try original.house.validate()
    let h=original.house
    var cases:[[String:Any]]=[]
    var trace:[[String:Double]]=[]
    let controller=prepared(h,V3(-7,2,1.6));defer{controller.stop()}
    var completed=0,maximumError=0.0
    for direction in [1.0,-1.0] {
      for _ in 0..<142 {
        let before=V3(ar:controller.camera.simdPosition)
        controller.stepMove(SIMD2(Float(direction),0))
        let after=V3(ar:controller.camera.simdPosition),requested=before.x+direction*0.2
        let lo=floorHeight(after.x+0.2-0.0001)+1.6,hi=floorHeight(after.x+0.2+0.0001)+1.6
        let error=max(abs(after.x-requested),abs(after.y-2),max(0,max(lo-after.z,after.z-hi)))
        maximumError=max(maximumError,error)
        if error<0.0001 {completed+=1}
        trace.append(["x":after.x,"y":after.y,"z":after.z,"requestedX":requested])
      }
    }
    cases.append(["name":"six rooms and sixteen stair treads in both directions","passed":completed==284,
      "attemptedSteps":284,"completedSteps":completed,"maximumPositionErrorMetres":maximumError])

    func refusal(_ name:String,_ changed:House,_ startX:Double,_ limitX:Double) {
      let start=V3(startX,2,floorHeight(startX+0.2)+1.6)
      let walk=prepared(changed,start);defer{walk.stop()}
      var moved=0,refused=0
      var positions:[[String:Double]]=[]
      for _ in 0..<16 {
        let before=V3(ar:walk.camera.simdPosition);walk.stepMove(SIMD2(1,0))
        let after=V3(ar:walk.camera.simdPosition)
        if (after-before).length<0.00001 {refused+=1}else{moved+=1}
        positions.append(["x":after.x,"y":after.y,"z":after.z])
      }
      let end=V3(ar:walk.camera.simdPosition)
      cases.append(["name":name,"passed":moved>0 && refused>0 && positions.allSatisfy{($0["x"] ?? .infinity)<=limitX},
        "movedSteps":moved,"refusedSteps":refused,"startX":startX,"positions":positions,
        "finalX":end.x,"maximumAllowedX":limitX])
    }
    var blocked=h
    blocked.features.append(Feature(name:"Closed door",trade:.structure,roomID:h.rooms[1].id,
      stageID:h.stages[0].id,kind:.synthetic,mesh:.box(center:V3(0,2,1.2),size:V3(0.1,1,2.4)),segmentID:h.segments[1].id))
    refusal("closed door preserves the observed corridor but refuses passage",blocked,-1.4,-0.25)
    var hole=h;hole.features.removeAll{$0.id==original.stairIDs[7]}
    refusal("missing stair tread refuses unsupported continuation",hole,5.6,6.6)
    var beam=h
    beam.features.append(Feature(name:"Low stair beam",trade:.structure,roomID:h.rooms[3].id,
      stageID:h.stages[0].id,kind:.synthetic,mesh:.box(center:V3(6.2,2,2.9),size:V3(0.4,2,0.1)),segmentID:h.segments[3].id))
    refusal("low stair headroom refuses passage",beam,4.6,5.8)
    var gap=h;gap.observations.removeAll{let x=$0.camera[3];return x > -1 && x<1}
    refusal("unobserved doorway never invents a camera connection",gap,-2,-0.2)

    var unregistered=h;unregistered.segments[2].registration=nil
    let separate=SceneBuilder.features(unregistered,options:SceneOptions())
    let positions=NavigationGeometry.positions(house:unregistered,options:SceneOptions())
    cases.append(["name":"unregistered repeated room remains a separate frame",
      "passed":!separate.isEmpty && separate.allSatisfy{$0.segmentID==h.segments[2].id} &&
        !positions.isEmpty && positions.allSatisfy{$0.x>=0 && $0.x<4},
      "visibleFeatures":separate.count,"cameraPositions":positions.count])
    let upper=V3(2,2,4.8),lower=V3(12.4,2,1.6)
    cases.append(["name":"stacked floors without observed connections remain unavailable",
      "passed":!NavigationGeometry.observed(upper,house:h,options:SceneOptions()) &&
        !NavigationGeometry.observed(lower,house:h,options:SceneOptions())])
    var hidden=SceneOptions();hidden.trades=[];hidden.ceilings=false
    let visible=SceneBuilder.features(blocked,options:hidden)
    let collisions=NavigationGeometry.collisionFeatures(blocked,options:hidden)
    cases.append(["name":"hidden layers preserve all walking obstacles",
      "passed":visible.isEmpty && collisions.count==NavigationGeometry.collisionFeatures(blocked,options:SceneOptions()).count &&
        SpatialClearance(features:collisions).walkingDestination(from:V3(-0.6,2,1.6),toward:V3(0.6,2,1.6))==nil])

    // Recorded camera motion establishes neither a floor nor its completeness.
    // Exercise the public mode transition and the shared movement controller,
    // then restore the actual floor to show the refusal is specific to support.
    let start=V3(-7,2,1.6),destination=V3(-6.8,2,1.6)
    func point(_ p:V3)->[String:Double] {["x":p.x,"y":p.y,"z":p.z]}
    var supportCases:[[String:Any]]=[]
    for variant in ["missing floor","floor points only","unclassified surface","planned floor","documentary floor"] {
      var unsupported=h
      if variant=="missing floor" {unsupported.features.removeAll{$0.trade == .floor}}
      else {for index in unsupported.features.indices where unsupported.features[index].trade == .floor {
        switch variant {
        case "floor points only":unsupported.features[index].mesh.triangles=[]
        case "unclassified surface":unsupported.features[index].trade = .unknown
        case "planned floor":unsupported.features[index].kind = .planned
        default:unsupported.features[index].kind = .documentary
        }
      }}
      let geometry=NavigationGeometry.collisionFeatures(unsupported,options:SceneOptions())
      let check=SpatialClearance(features:geometry)
      let local=try SpatialClearance(index:SpatialDisplayIndex(features:geometry),camera:start)
      let walk=WalkController();defer{walk.stop()};walk.load(unsupported,SceneOptions())
      let initialFreeFly=walk.flying
      walk.bookmark(Bookmark(name:"Recorded viewpoint",position:start,yaw:0,pitch:0,roomID:h.rooms[0].id))
      walk.setFlying(false)
      let returnToWalkRefused=walk.flying
      // Also check movement itself refuses if an internal caller leaves walk
      // selected while the floor disappears; UI mode checks are not enough.
      walk.flying=false;walk.stepMove(SIMD2(1,0))
      let refusedPosition=V3(ar:walk.camera.simdPosition)
      walk.setFlying(true);walk.stepMove(SIMD2(1,0))
      let freePosition=V3(ar:walk.camera.simdPosition)
      let unchangedUnsupported=walk.house==unsupported
      var restored=h;restored.revision+=1;walk.load(restored,SceneOptions())
      walk.bookmark(Bookmark(name:"Supported viewpoint",position:start,yaw:0,pitch:0,roomID:h.rooms[0].id))
      walk.setFlying(false);let restoredWalkEnabled = !walk.flying
      walk.stepMove(SIMD2(1,0));let restoredPosition=V3(ar:walk.camera.simdPosition)
      let geometryRefused = !check.hasFloorSupport && !local.hasFloorSupport &&
        check.walkingDestination(from:start,toward:destination)==nil && local.walkingDestination(from:start,toward:destination)==nil
      let sourcePreserved=unchangedUnsupported && walk.house==restored
      let passed=initialFreeFly && returnToWalkRefused && geometryRefused && sourcePreserved &&
        (refusedPosition-start).length<0.0001 && (freePosition-destination).length<0.0001 &&
        restoredWalkEnabled && (restoredPosition-destination).length<0.0001
      supportCases.append(["variant":variant,"passed":passed,"cameraPositions":unsupported.observations.count,
        "initialFreeFly":initialFreeFly,"returnToWalkRefused":returnToWalkRefused,
        "globalAndIndexedSupportRefused":geometryRefused,"sourceGeometryUnchanged":sourcePreserved,
        "start":point(start),"afterRefusedWalk":point(refusedPosition),"afterFreeFly":point(freePosition),
        "restoredWalkEnabled":restoredWalkEnabled,"afterRestoredWalk":point(restoredPosition)])
    }
    cases.append(["name":"camera corridors without observed floor support cannot enable walking",
      "passed":supportCases.allSatisfy{$0["passed"] as? Bool==true},"variants":supportCases])
    let unchanged=controller.house==h
    return ["version":2,"profile":"analytic-connected-walk-v2","passed":cases.allSatisfy{$0["passed"] as? Bool==true} && unchanged,
      "rooms":h.rooms.count,"levels":2,"routeSpaces":original.routeRooms.count,"doorways":4,"stairTreads":16,
      "horizontalRouteLengthMetres":56.8,"cases":cases,"trace":trace,"sourceGeometryUnchanged":unchanged,
      "physicalQualification":false,"reconstructionQualified":false,"protectedBenchmark":false,
      "limitations":"Public analytic source geometry and camera positions through the actual native walking controller. This checks connected movement and refusals; it does not qualify reconstructed topology, localization, display performance or physical safety."]
  }
}
