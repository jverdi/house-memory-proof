import SwiftUI
import SceneKit

@MainActor fileprivate extension WalkController {
  var roomMapPose:(position:V3,yaw:Double) {
    let node=(view.pointOfView ?? camera).presentation,backward=node.simdWorldTransform.columns.2
    let direction=hypot(Double(backward.x),Double(backward.z))>1e-6 ? atan2(Double(backward.x),Double(backward.z)):Double.nan
    return(canonicalPoint(node.simdWorldPosition),direction)
  }
}

// This is an orientation aid, not a floor plan, navigation proxy or coverage
// certificate. Unregistered visits never share a map with another frame.
struct RoomMapSnapshot {
  struct Viewpoint:Identifiable {var id:UUID;var roomID:UUID;var position:V3}
  var rooms:[Room]
  var visits:[Viewpoint]
  var viewCounts:[UUID:Int]
  var bookmarks:[Bookmark]
  var separateVisit:UUID?
  var limitedBookmarks:Bool
  var omittedBookmarks:Int
  var levels:[Int] {Array(Set(rooms.map{$0.level})).sorted()}
  static func displayable(_ position:V3)->Bool {
    position.finite && max(abs(position.x),abs(position.y),abs(position.z))<=100000
  }
  static func heading(_ yaw:Double)->String {
    guard yaw.isFinite else{return "Direction unavailable"}
    let turn=yaw.truncatingRemainder(dividingBy:2 * .pi)/(2 * .pi)
    let index=(Int((turn*8).rounded())%8+8)%8
    return "Facing \(["up","upper left","left","lower left","down","lower right","right","upper right"][index]) on the map"
  }

  static func build(house:House,options:SceneOptions)throws->RoomMapSnapshot {
    let separate=SceneBuilder.activeUnregisteredSegment(house,options:options)
    let stages=SceneBuilder.eligibleStages(house,options:options)
    let separateRoom=house.segments.first{$0.id==separate}?.roomID
    let rooms=house.rooms.filter{(options.room==nil || $0.id==options.room) && (separate==nil || $0.id==separateRoom)}
    if separate==nil, !rooms.allSatisfy({displayable($0.origin) && displayable($0.origin+$0.size)}) {
      throw HouseError.message("The room map exceeds the supported drawing range.")
    }
    let roomIDs=Set(rooms.map{$0.id})
    let selected=PoseRefinement.selectedForHouse(house).filter{roomIDs.contains($0.roomID) && stages.contains($0.stageID) && (separate==nil || $0.segmentID==separate)}
    var counts:[UUID:Int]=[:],views:[Viewpoint]=[]
    // Deterministic sampling across the complete selected inventory, not just
    // its first room. Counts retain all eligible views, including omitted dots.
    let strideCount=max(1,(selected.count+255)/256)
    for (index,observation) in selected.enumerated() {
      if index%256==0 {try Task.checkCancellation()}
      counts[observation.roomID,default:0]+=1
      if index%strideCount==0 {
        let position=TourDirector.pose(observation,house:house).0
        guard displayable(position) else{throw HouseError.message("A photo position exceeds the supported map range.")}
        views.append(Viewpoint(id:observation.id,roomID:observation.roomID,position:position))
      }
    }
    let scopedBookmarks=house.bookmarks.filter{roomIDs.contains($0.roomID) && $0.segmentID==separate}
    let bookmarks=scopedBookmarks.filter{displayable($0.position) && $0.yaw.isFinite && $0.pitch.isFinite}
    return Self(rooms:rooms,visits:views,viewCounts:counts,bookmarks:Array(bookmarks.prefix(100)),
      separateVisit:separate,limitedBookmarks:bookmarks.count>100,omittedBookmarks:scopedBookmarks.count-bookmarks.count)
  }
  func room(at position:V3)->Room? {
    guard Self.displayable(position) else{return nil}
    if separateVisit != nil {return rooms.first}
    return Self.containingRoom(position,in:rooms)
  }
  static func containingRoom(_ position:V3,in rooms:[Room])->Room? {
    guard displayable(position) else{return nil}
    return rooms.filter { r in
      let local=position-r.origin
      return local.x>=0 && local.x<=r.size.x && local.y>=0 && local.y<=r.size.y && local.z>=0 && local.z<=r.size.z
    }.min{($0.origin+($0.size*0.5)-position).length<($1.origin+($1.size*0.5)-position).length}
  }
  func level(at position:V3)->Int? {room(at:position)?.level}
  func bounds(level:Int,position:V3)->(low:V3,high:V3) {
    let selected=rooms.filter{$0.level==level},ids=Set(selected.map{$0.id})
    var points=visits.filter{ids.contains($0.roomID)}.map{$0.position}+bookmarks.filter{ids.contains($0.roomID)}.map{$0.position}
    if separateVisit==nil {for r in selected {points+=[r.origin,r.origin+r.size]}}
    if self.level(at:position)==level || points.isEmpty {points.append(Self.displayable(position) ? position:V3())}
    let low=V3(points.map{$0.x}.min() ?? 0,points.map{$0.y}.min() ?? 0,0)
    let high=V3(points.map{$0.x}.max() ?? 0,points.map{$0.y}.max() ?? 0,0)
    let centre=(low+high)*0.5,half=V3(max(1,(high.x-low.x)*0.6),max(1,(high.y-low.y)*0.6),0)
    return(centre-half,centre+half)
  }
}

struct RoomMapDrawing:View {
  let snapshot:RoomMapSnapshot
  let position:V3
  let yaw:Double
  let level:Int
  var body:some View {
    Canvas {context,size in
      let bounds=snapshot.bounds(level:level,position:position)
      let scale=min((size.width-24)/max(0.1,bounds.high.x-bounds.low.x),(size.height-24)/max(0.1,bounds.high.y-bounds.low.y))
      let centre=(bounds.low+bounds.high)*0.5
      func point(_ p:V3)->CGPoint {CGPoint(x:size.width/2+(p.x-centre.x)*scale,y:size.height/2-(p.y-centre.y)*scale)}
      let rooms=snapshot.rooms.filter{$0.level==level},roomIDs=Set(rooms.map{$0.id})
      if snapshot.separateVisit==nil {for room in rooms {
        let a=point(room.origin),b=point(room.origin+room.size)
        let rect=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        context.fill(Path(rect),with:.color(.gray.opacity(0.12)))
        context.stroke(Path(rect),with:.color(.gray),style:StrokeStyle(lineWidth:1,dash:[4,3]))
      }}
      for view in snapshot.visits where roomIDs.contains(view.roomID) {
        let p=point(view.position);context.fill(Path(ellipseIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(.cyan))
      }
      for bookmark in snapshot.bookmarks where roomIDs.contains(bookmark.roomID) {
        let p=point(bookmark.position);context.fill(Path(CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(.orange))
      }
      if RoomMapSnapshot.displayable(position),yaw.isFinite,snapshot.level(at:position)==level || snapshot.separateVisit != nil {
        let p=point(position),direction=CGPoint(x:-sin(yaw),y:-cos(yaw)),side=CGPoint(x:cos(yaw),y:-sin(yaw))
        var arrow=Path();arrow.move(to:CGPoint(x:p.x+direction.x*11,y:p.y+direction.y*11))
        arrow.addLine(to:CGPoint(x:p.x-direction.x*6+side.x*6,y:p.y-direction.y*6+side.y*6))
        arrow.addLine(to:CGPoint(x:p.x-direction.x*6-side.x*6,y:p.y-direction.y*6-side.y*6));arrow.closeSubpath()
        context.fill(arrow,with:.color(.white));context.stroke(arrow,with:.color(.black),lineWidth:1)
      }
    }.background(Color.black.opacity(0.8),in:RoundedRectangle(cornerRadius:12))
      .accessibilityHidden(true)
  }
}

struct RoomMapPage:View {
  @EnvironmentObject var model:AppModel
  var house:House
  var options:SceneOptions
  @ObservedObject var controller:WalkController
  @Binding var showMiniMap:Bool
  var jump:(Room)->Void
  var bookmark:(Bookmark)->Void
  @State private var snapshot:RoomMapSnapshot?
  @State private var level:Int?
  @State private var failure:String?
  @State private var coverage:[UUID:CheckedBoundaryCoverage.Summary]=[:]
  private var sourceKey:String {"\(house.id)-\(house.revision)-\(options.room?.uuidString ?? "all")-\(options.stage?.uuidString ?? "all")-\(options.mode.rawValue)-\(model.checkedCoverage.generation)"}
  var body:some View {
    Form {
      Section {
        if house.isDemo {Text("Sample house · generated demonstration").font(.caption.bold())}
        Toggle("Show mini-map in the 3D view",isOn:$showMiniMap).accessibilityIdentifier("show-mini-map")
        Text("Use this map to keep your bearings. Room outlines are approximate reference bounds. Dots show recorded photo positions; they do not prove that an area was completely recorded.").font(.footnote)
        if let room=house.rooms.first(where:{$0.id==options.room}) {
          Text("Showing \(room.name). To include other rooms, return to Layers and set Scope to All spaces. Unaligned visits still appear separately.").font(.footnote)
        }
      }
      if let snapshot {
        Section("Where you are") {
          TimelineView(.periodic(from:.now,by:0.25)) { _ in
            let pose=controller.roomMapPose,position=pose.position
            let shownLevel=level ?? snapshot.level(at:position) ?? snapshot.levels.first ?? 0
            VStack(alignment:.leading,spacing:10) {
              Text(snapshot.room(at:position).map{"\($0.name) · Level \($0.level)"} ?? "Outside the room reference bounds")
                .accessibilityIdentifier("room-map-location")
              RoomMapDrawing(snapshot:snapshot,position:position,yaw:pose.yaw,level:shownLevel).frame(height:240)
              Text(RoomMapSnapshot.heading(pose.yaw)).font(.caption)
            }
          }
          Picker("Floor",selection:$level) {
            Text("Follow my view").tag(Optional<Int>.none)
            ForEach(snapshot.levels,id:\.self){Text("Level \($0)").tag(Optional($0))}
          }
          Text("White arrow: your view and direction · blue dots: saved photo positions · orange squares: saved viewpoints. The map follows the record's axes, not compass north.").font(.footnote)
          if snapshot.separateVisit != nil {
            Text("These captures have not been aligned. This map shows one visit at a time, without combining it with other rooms.").font(.footnote)
          }
        }
        Section("Rooms and records") {
          ForEach(snapshot.rooms.filter{level==nil || $0.level==level}) { room in
            Button {jump(room)} label: {
              VStack(alignment:.leading) {
                Text(room.name)
                Text("Level \(room.level) · \(snapshot.viewCounts[room.id,default:0]) recorded photo positions").font(.caption)
                Text(coverage[room.id,default:CheckedBoundaryCoverage.Summary()].explanation).font(.caption)
              }
            }.accessibilityIdentifier("map-room-\(room.id)")
              .disabled(!house.isDemo && snapshot.viewCounts[room.id,default:0]==0)
          }
          NavigationLink("Review capture coverage") {CoveragePage(house:house)}
          Text("A room with no dots has no eligible saved photo positions in this scope. Imported ordinary photos may still be available in Evidence. Review capture coverage to check a defined wall or ceiling area. Checks reset after a project change or app restart. Overlapping areas count separately; these counts do not establish complete room coverage.").font(.footnote)
        }
        Section("Saved viewpoints") {
          if snapshot.bookmarks.isEmpty {Text("No usable saved viewpoints in this map. In Explore, open Jump → Save viewpoint to keep a place you want to return to.")}
          ForEach(snapshot.bookmarks.filter{mark in level==nil || snapshot.rooms.first{$0.id==mark.roomID}?.level==level}) {mark in
            Button(mark.name){bookmark(mark)}
          }
          if snapshot.limitedBookmarks {Text("Showing the first 100 saved viewpoints. The complete list remains in Jump.").font(.footnote)}
          if snapshot.omittedBookmarks>0 {Text("\(snapshot.omittedBookmarks) saved viewpoints could not be placed on this map. Choose a room to return to a checked view. Your saved records have not been changed.").font(.footnote)}
        }
      }else if let failure {Text(failure)}else {ProgressView("Preparing room map…")}
    }.navigationTitle("Room map").task(id:sourceKey) {
      snapshot=nil;failure=nil;coverage=[:]
      let checked=model.checkedCoverage
      do {let prepared=try await LocalWorker.run{(try RoomMapSnapshot.build(house:house,options:options),try checked.summaries(house:house,options:options))}
        try Task.checkCancellation();snapshot=prepared.0;coverage=prepared.1
        if let level,!prepared.0.levels.contains(level) {self.level=nil}
      }catch is CancellationError {}catch{failure="The map could not be prepared. You can still use Jump to choose a room or open Evidence to find the original photos."}
    }
  }
}

struct MiniRoomMap:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  var house:House
  var options:SceneOptions
  @ObservedObject var controller:WalkController
  @State private var snapshot:RoomMapSnapshot?
  @State private var failed=false
  @State private var coverage:[UUID:CheckedBoundaryCoverage.Summary]=[:]
  private var sourceKey:String {"\(house.id)-\(house.revision)-\(options.room?.uuidString ?? "all")-\(options.stage?.uuidString ?? "all")-\(options.mode.rawValue)-\(model.checkedCoverage.generation)"}
  var body:some View {
    // Keep a concrete container alive while the snapshot is absent. A Group
    // containing only a nil conditional has no child to start its task.
    ZStack(alignment:.topLeading) {
      Color.clear
      if let snapshot {
        TimelineView(.periodic(from:.now,by:0.25)) { _ in
          let pose=controller.roomMapPose,position=pose.position
          let room=snapshot.room(at:position),level=room?.level ?? snapshot.levels.first ?? 0
          let location=room.map{"\($0.name) · Level \($0.level)"} ?? "Outside room bounds"
          let checked=room.flatMap{coverage[$0.id]} ?? CheckedBoundaryCoverage.Summary()
          ViewThatFits(in:.vertical) {
            VStack(alignment:.leading,spacing:4) {
              Text(location).font(.caption).lineLimit(1)
              RoomMapDrawing(snapshot:snapshot,position:position,yaw:pose.yaw,level:level).frame(width:verticalSizeClass == .compact ? 140:160,height:verticalSizeClass == .compact ? 64:120)
              Text(checked.shortLabel).font(.caption2).lineLimit(1)
            }.frame(width:verticalSizeClass == .compact ? 140:160,alignment:.leading).padding(8)
              .background(Color.black.opacity(0.85),in:RoundedRectangle(cornerRadius:12)).fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:4) {
              Text(location).font(.caption).lineLimit(1)
              Text(checked.shortLabel).font(.caption2).lineLimit(1)
            }.padding(8).background(Color.black.opacity(0.85),in:RoundedRectangle(cornerRadius:12)).fixedSize(horizontal:false,vertical:true)
            Color.clear.frame(height:0)
          }.frame(maxHeight:.infinity,alignment:.top).foregroundStyle(.white)
            .accessibilityElement(children:.ignore).accessibilityLabel(location).accessibilityIdentifier("mini-room-map")
            .accessibilityValue(RoomMapSnapshot.heading(pose.yaw)+". Dots are photo positions. "+checked.explanation)
        }
      }else {
        Text(failed ? "Map unavailable. Open Layers → Room map for help.":"Preparing room map…")
          .font(.caption).foregroundStyle(.white).padding(8)
          .background(Color.black.opacity(0.85),in:RoundedRectangle(cornerRadius:12))
          .accessibilityIdentifier("mini-room-map-status")
      }
    }.task(id:sourceKey) {
      snapshot=nil;failed=false;coverage=[:]
      let checked=model.checkedCoverage
      do {let prepared=try await LocalWorker.run{(try RoomMapSnapshot.build(house:house,options:options),try checked.summaries(house:house,options:options))}
        try Task.checkCancellation();snapshot=prepared.0;coverage=prepared.1
      }catch is CancellationError {}catch {failed=true}
    }
  }
}
