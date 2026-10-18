import Foundation
import SceneKit
import UIKit

struct TourServiceInspection:Codable,Equatable {
  var profile="reviewed-route-v1"
  var routeIndex:Int
  var endpoint:Int?
  var confirmedLinkIDs:[UUID]
}

// A service tour inspects reviewed source routes. Camera cuts never assert a
// physical connection; only explicitly confirmed links order neighboring routes.
enum TourServices {
  static let trades:Set<Trade>=[.electrical,.lowVoltage,.plumbing,.hvac]
  static func plan(_ house:House,duration:Double,options:SceneOptions,aspect:Double)->TourPlan {
    var scope=options;scope.mode = .rough;scope.stage=nil
    let selected=trades.intersection(options.trades)
    scope.trades=selected.union([.structure,.floor,.ceiling,.unknown])
    let baseline=TourDirector.plan(house,duration:duration,options:scope,aspect:aspect)
    var shots:[TourShot]=[],excluded:[String]=[]
    let totalFrames=max(150,Int((min(60,max(5,duration))*30).rounded()))
    let maxShots=totalFrames/30 // At least one second to inspect each target.
    guard house.connections.count<=4096,Set(house.connections.map({$0.id})).count==house.connections.count else{return TourPlan(sourceRevision:house.revision,synthetic:house.isDemo,shots:[],excluded:["Service connection inventory is ambiguous or exceeds the budget"])}
    for room in house.rooms where options.room==nil || options.room==room.id {
      var roomScope=scope;roomScope.room=room.id
      guard SceneBuilder.activeUnregisteredSegment(house,options:roomScope)==nil else {
        excluded.append(room.name+": service routes need a checked shared frame");continue
      }
      let visible=SceneBuilder.features(house,options:roomScope)
      let candidates=visible.filter{selected.contains($0.trade) && $0.route.count>=2 && $0.envelope==nil}
      guard candidates.count<=128 else{excluded.append(room.name+": service route budget exceeded");continue}
      let routes=candidates.filter{feature in
        let admissible=feature.reviewed && (feature.kind == .observed || (house.isDemo && feature.kind == .synthetic))
          && feature.route.count<=4096 && feature.route.allSatisfy{$0.finite}
        if !admissible {excluded.append(room.name+" · "+feature.name+": route is unreviewed, unsupported or exceeds the point budget")}
        return admissible
      }
      let ids=Set(routes.map{$0.id})
      let links=house.connections.filter{link in
        link.confirmed && ids.contains(link.fromFeature) && ids.contains(link.toFeature)
          && link.fromFeature != link.toFeature && (0...1).contains(link.fromEnd) && (0...1).contains(link.toEnd)
          && routes.first(where:{$0.id==link.fromFeature})?.trade==routes.first(where:{$0.id==link.toFeature})?.trade
      }
      // Stable breadth-first ordering; cycles cannot duplicate a route and
      // proximity/crossings do not participate in the graph.
      var ordered:[Feature]=[],seen=Set<UUID>()
      for root in routes where !seen.contains(root.id) {
        var queue=[root.id],scheduled:Set<UUID>=[root.id],cursor=0
        while cursor<queue.count {
          let id=queue[cursor];cursor+=1
          guard seen.insert(id).inserted,let route=routes.first(where:{$0.id==id}) else{continue}
          ordered.append(route)
          for link in links {
            if link.fromFeature==id && !seen.contains(link.toFeature) && scheduled.insert(link.toFeature).inserted{queue.append(link.toFeature)}
            if link.toFeature==id && !seen.contains(link.fromFeature) && scheduled.insert(link.fromFeature).inserted{queue.append(link.fromFeature)}
          }
        }
      }
      let clearance=SpatialClearance(features:NavigationGeometry.collisionFeatures(house,options:roomScope))
      let cameras=baseline.shots.filter{$0.roomID==room.id}.map{TourFraming.held($0)}
      for route in ordered {
        guard !Task.isCancelled else{return TourPlan(sourceRevision:house.revision,synthetic:house.isDemo,shots:[],excluded:["Service planning cancelled"])}
        let transform=route.segmentID.flatMap{id in house.segments.first{$0.id==id}?.registration}
        let points=route.route.map{transform?.apply($0) ?? $0}
        let obstacles=TourSightlines(features:visible.filter{$0.id != route.id && $0.envelope?.sourceFeatureID != route.id},house:house)
        guard obstacles.complete else{excluded.append(route.name+": obstruction budget exceeded");continue}
        let count=min(16,points.count)
        let indices=(0..<count).map{$0*(points.count-1)/(count-1)}
        if count<points.count {excluded.append(route.name+": \(points.count-count) intermediate route points omitted by the inspection budget")}
        // Endpoints receive priority before intermediate bends if duration is
        // short; their original indices remain explicit in the saved plan.
        let priority=[indices.first!,indices.last!]+Array(indices.dropFirst().dropLast())
        for index in priority {
          let endpoint:Int?=index==0 ? 0:index==points.count-1 ? 1:nil
          let label=endpoint.map{$0==0 ? "start endpoint":"end endpoint"} ?? "route point \(index+1)"
          guard shots.count<maxShots else {excluded.append(route.name+" · "+label+": duration budget omitted this inspection");continue}
          let subject=TourSubject(featureID:route.id,featureRevision:route.revision,point:points[index])
          let viewpoints=cameras.enumerated().sorted {a,b in
            let x=(a.element.position-subject.point).length,y=(b.element.position-subject.point).length
            return x==y ? a.offset<b.offset:x<y
          }
          guard var shot=viewpoints.lazy.map({TourFraming.framed($0.element,subject:subject)}).first(where:{
            clearance.isClear(from:$0.position,to:$0.position,radius:0.15) && TourFraming.check($0,sightlines:obstacles,steps:1,aspect:aspect)
          }) else {excluded.append(route.name+" · "+label+": no clear captured inspection viewpoint");continue}
          let relevant=links.filter{link in
            guard let endpoint else{return false}
            return (link.fromFeature==route.id && link.fromEnd==endpoint) || (link.toFeature==route.id && link.toEnd==endpoint)
          }.map{$0.id}
          shot.serviceInspection=TourServiceInspection(routeIndex:index,endpoint:endpoint,confirmedLinkIDs:relevant)
          let identity=route.service?.confidence == .ownerConfirmed ? "owner-confirmed identity":"identity unconfirmed"
          let connection=relevant.isEmpty ? "no confirmed link in this scope":"user-confirmed link; camera cut"
          let date=house.stages.first{$0.id==route.stageID}.map{ISO8601DateFormatter().string(from:$0.date)} ?? "date unavailable"
          shot.caption=(house.isDemo ? "SYNTHETIC · ":"")+room.name+" · "+route.trade.rawValue+" · "+route.name+" · Recorded centerline · "+label+" · "+identity+" · "+connection+" · "+date
          shot.layerMode=ViewMode.rough.rawValue;shot.tradeNames=roomScope.trades.map{$0.rawValue}.sorted()
          shot.includesPlannedGeometry=visible.contains{$0.kind == .planned}
          shots.append(shot)
        }
      }
      if routes.isEmpty {excluded.append(room.name+": no reviewed service routes in the selected trades")}
    }
    if !shots.isEmpty {
      let base=totalFrames/shots.count,remainder=totalFrames%shots.count
      for index in shots.indices {shots[index].duration=Double(base+(index<remainder ? 1:0))/30}
    }
    return TourPlan(sourceRevision:house.revision,synthetic:house.isDemo,shots:TourDirector.chunk(shots),excluded:excluded)
  }
  static func validate(_ shot:TourShot,house:House,scope:SceneOptions)throws {
    guard let inspection=shot.serviceInspection else{return}
    guard inspection.profile=="reviewed-route-v1",let subject=shot.subject,
      let feature=SceneBuilder.features(house,options:scope).first(where:{$0.id==subject.featureID}),
      feature.revision==subject.featureRevision,feature.reviewed,feature.route.count>=2,
      feature.kind == .observed || (house.isDemo && feature.kind == .synthetic),
      SceneBuilder.activeUnregisteredSegment(house,options:scope)==nil,
      feature.route.indices.contains(inspection.routeIndex),shot.endPosition==nil else {
      throw HouseError.message("Reviewed service inputs changed. Rebuild the tour preview.")
    }
    let endpoint:Int?=inspection.routeIndex==0 ? 0:inspection.routeIndex==feature.route.count-1 ? 1:nil
    let transform=feature.segmentID.flatMap{id in house.segments.first{$0.id==id}?.registration}
    let point=transform?.apply(feature.route[inspection.routeIndex]) ?? feature.route[inspection.routeIndex]
    let peers=SceneBuilder.features(house,options:scope)
    guard endpoint==inspection.endpoint,(point-subject.point).length<1e-9,
      inspection.confirmedLinkIDs.allSatisfy({id in house.connections.contains{link in
        guard let endpoint else{return false}
        let peerID=link.fromFeature==feature.id ? link.toFeature:link.fromFeature
        let peer=peers.first{$0.id==peerID}
        return link.id==id && link.confirmed && peer?.reviewed==true && peer?.trade==feature.trade
          && peerID != feature.id && (peer?.route.count ?? 0)>=2
          && (peer?.kind == .observed || (house.isDemo && peer?.kind == .synthetic))
          && (0...1).contains(link.fromEnd) && (0...1).contains(link.toEnd)
          && ((link.fromFeature==feature.id && link.fromEnd==endpoint) || (link.toFeature==feature.id && link.toEnd==endpoint))
      }}) else{throw HouseError.message("Service route or connection evidence changed. Rebuild the tour preview.")}
  }
  static func decorate(_ scene:SCNScene,shot:TourShot,house:House) {
    guard shot.serviceInspection != nil,let subject=shot.subject,
      let source=house.features.first(where:{$0.id==subject.featureID}) else{return}
    // These are centerline inspections, not claims to see inside opaque pipes.
    // Only the selected route and its measured envelope become translucent;
    // other captured obstructions retain normal depth and opacity.
    for feature in house.features where feature.id==source.id || feature.envelope?.sourceFeatureID==source.id {
      if let node=scene.rootNode.childNode(withName:feature.id.uuidString,recursively:false) {
        node.opacity=0.35;node.geometry?.firstMaterial?.writesToDepthBuffer=false
      }
    }
    let marker=SCNNode(geometry:SCNSphere(radius:0.035))
    marker.name="service-inspection-marker";marker.simdPosition=subject.point.render
    let material=SCNMaterial();material.lightingModel = .constant
    material.diffuse.contents=UIColor(rgb:source.trade.hex);marker.geometry?.materials=[material]
    scene.rootNode.addChildNode(marker)
  }
}
