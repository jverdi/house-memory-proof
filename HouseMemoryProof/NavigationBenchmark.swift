import Foundation
import SceneKit
import simd

// Public analytic topology used only by owner diagnostics. This exercises the
// actual walk controller; it is neither reconstructed geometry nor field truth.
@MainActor enum NavigationBenchmark {
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
    let unchanged=controller.house==h
    return ["version":1,"profile":"analytic-connected-walk-v1","passed":cases.allSatisfy{$0["passed"] as? Bool==true} && unchanged,
      "rooms":h.rooms.count,"levels":2,"routeSpaces":original.routeRooms.count,"doorways":4,"stairTreads":16,
      "horizontalRouteLengthMetres":56.8,"cases":cases,"trace":trace,"sourceGeometryUnchanged":unchanged,
      "physicalQualification":false,"reconstructionQualified":false,"protectedBenchmark":false,
      "limitations":"Public analytic source geometry and camera positions through the actual native walking controller. This checks connected movement and refusals; it does not qualify reconstructed topology, localization, display performance or physical safety."]
  }
}
