import Foundation
import SceneKit
import UIKit

struct TourRevealEvent:Codable,Equatable {
  var profile="matched-reveal-v1"
  var finishes:[TourSubject]
  var roughStageID:UUID
  var finishedStageIDs:[UUID]
  // Normalized timeline survives shot chunking and resumable encoding.
  var fadeOutStart=0.15,fadeOutEnd=0.35,restoreStart=0.65,restoreEnd=0.85
  func amount(at phase:Double)->Double {
    func smooth(_ t:Double)->Double {let x=max(0,min(1,t));return x*x*(3-2*x)}
    return smooth((phase-fadeOutStart)/(fadeOutEnd-fadeOutStart))*(1-smooth((phase-restoreStart)/(restoreEnd-restoreStart)))
  }
}

enum TourReveal {
  static func plan(_ house:House,duration:Double,options:SceneOptions,aspect:Double)->TourPlan {
    var roughScope=options;roughScope.mode = .rough;roughScope.stage=nil
    let source=TourDirector.plan(house,duration:duration,options:roughScope,aspect:aspect)
    var shots:[TourShot]=[],excluded=source.excluded
    let allFrames=max(150,Int((min(60,max(5,duration))*30).rounded()))
    for room in house.rooms where options.room==nil || options.room==room.id {
      var rough=roughScope;rough.room=room.id
      var finished=rough;finished.mode = .finished
      guard SceneBuilder.activeUnregisteredSegment(house,options:rough)==nil,
        SceneBuilder.activeUnregisteredSegment(house,options:finished)==nil else {
        excluded.append(room.name+": before/after needs both stages in a checked shared frame");continue
      }
      func admissible(_ f:Feature)->Bool {f.kind == .observed || (house.isDemo && f.kind == .synthetic)}
      let roughFeatures=SceneBuilder.features(house,options:rough).filter(admissible)
      let finishedFeatures=SceneBuilder.features(house,options:finished).filter(admissible)
      let surfaces=finishedFeatures.filter{($0.trade == .finish || $0.trade == .ceiling) && !$0.mesh.triangles.isEmpty}
      guard !roughFeatures.isEmpty,!surfaces.isEmpty,surfaces.count<=64 else {
        excluded.append(room.name+": no bounded pair of captured rough and finished surfaces");continue
      }
      let roughIndex=TourSightlines(features:roughFeatures,house:house),finishedIndex=TourSightlines(features:finishedFeatures,house:house)
      guard roughIndex.complete,finishedIndex.complete else {excluded.append(room.name+": comparison geometry exceeds the sightline budget");continue}
      let surfaceIndexes=surfaces.map{TourSightlines(features:[$0],house:house)}
      let body=SpatialClearance(features:NavigationGeometry.collisionFeatures(house,options:rough)+NavigationGeometry.collisionFeatures(house,options:finished))
      let finishedPositions=NavigationGeometry.positions(house:house,options:finished)
      let targets=Set(roughFeatures.filter{$0.trade != .floor && $0.trade != .ceiling}.map{$0.id})
      let cameras=source.shots.filter{$0.roomID==room.id}.prefix(3)
      var roomShots=0,used=Set<UUID>()
      for original in cameras {
        guard !Task.isCancelled else{return TourPlan(sourceRevision:house.revision,synthetic:house.isDemo,shots:[],excluded:["Comparison planning cancelled"])}
        let held=TourFraming.held(original),position=held.position
        guard body.isClear(from:position,to:position,radius:0.15),
          (house.isDemo && house.observations.isEmpty) || NavigationGeometry.observed(position,positions:finishedPositions) else{continue}
        let candidates=roughIndex.candidates.enumerated().filter{entry in let distance=(entry.element.point-position).length;return targets.contains(entry.element.featureID) && !used.contains(entry.element.featureID) && distance>=0.35 && distance<=30}.sorted { a,b in
          let x=(a.element.point-position).length,y=(b.element.point-position).length
          return x==y ? a.offset<b.offset:x<y
        }.prefix(128).map{$0.element}
        for target in candidates {
          var shot=TourFraming.framed(held,subject:target)
          guard TourFraming.check(shot,sightlines:roughIndex,steps:1,aspect:aspect) else{continue}
          var finishes:[TourSubject]=[]
          for (index,surface) in surfaces.enumerated() {
            if let point=surfaceIndexes[index].firstSurface(from:position,to:target.point),TourFraming.inFrame(point,camera:(position,shot.yaw,shot.pitch),aspect:aspect) {
              finishes.append(.init(featureID:surface.id,featureRevision:surface.revision,point:point))
            }
          }
          guard !finishes.isEmpty,finishes.count<=8 else{continue}
          let fadedIDs=Set(finishes.map{$0.featureID})
          let remaining=TourSightlines(features:finishedFeatures.filter{!fadedIDs.contains($0.id)},house:house)
          guard remaining.visible(from:position,to:target.point),let feature=roughFeatures.first(where:{$0.id==target.featureID}) else{continue}
          let stages=house.stages.filter{stage in surfaces.contains{fadedIDs.contains($0.id) && $0.stageID==stage.id}}
          let date=ISO8601DateFormatter()
          let roughDate=house.stages.first{$0.id==feature.stageID}.map{date.string(from:$0.date)} ?? "date unavailable"
          let finishedDates=stages.map{date.string(from:$0.date)}.joined(separator:", ")
          shot.caption=(house.isDemo ? "SYNTHETIC · ":"")+room.name+" · Same-camera reveal · "+feature.name+" · "+roughDate+" → "+finishedDates
          shot.layerMode=ViewMode.finished.rawValue;shot.tradeNames=rough.trades.map{$0.rawValue}.sorted()
          shot.includesPlannedGeometry=false
          shot.reveal=TourRevealEvent(finishes:finishes,roughStageID:feature.stageID,finishedStageIDs:stages.map{$0.id})
          shots.append(shot);used.insert(target.featureID);roomShots+=1;break
        }
      }
      if roomShots==0 {excluded.append(room.name+": no shared clear camera frames captured evidence behind a finish surface")}
    }
    if shots.count>allFrames {excluded.append("Duration omitted \(shots.count-allFrames) comparison shots");shots=Array(shots.prefix(allFrames))}
    if !shots.isEmpty {
      let base=allFrames/shots.count,remainder=allFrames%shots.count
      for i in shots.indices {shots[i].duration=Double(base+(i<remainder ? 1:0))/30}
    }
    return TourPlan(sourceRevision:house.revision,synthetic:house.isDemo,shots:TourDirector.chunk(shots),excluded:excluded)
  }
  static func scene(_ house:House,shot:TourShot,options:SceneOptions,assetRoot:URL?=nil)throws->SCNScene {
    let scope=SceneOptions(mode:shot.layerMode.flatMap(ViewMode.init(rawValue:)) ?? options.mode,trades:shot.tradeNames.map{Set($0.compactMap(Trade.init(rawValue:)))} ?? options.trades,ceilings:options.ceilings,room:shot.roomID,stage:shot.layerMode==nil ? options.stage:nil)
    try TourServices.validate(shot,house:house,scope:scope)
    let scene=SceneBuilder.scene(house,options:scope,assetRoot:assetRoot)
    TourServices.decorate(scene,shot:shot,house:house)
    guard let event=shot.reveal else{return scene}
    for feature in house.features where feature.kind != .observed && !(house.isDemo && feature.kind == .synthetic) {
      scene.rootNode.childNode(withName:feature.id.uuidString,recursively:false)?.removeFromParentNode()
    }
    guard event.profile=="matched-reveal-v1",let target=shot.subject,
      let feature=house.features.first(where:{$0.id==target.featureID && $0.revision==target.featureRevision}),
      feature.stageID==event.roughStageID,feature.roomID==shot.roomID,
      !event.finishes.isEmpty,event.finishes.count<=8,
      event.finishes.allSatisfy({subject in house.features.contains{$0.id==subject.featureID && $0.revision==subject.featureRevision && event.finishedStageIDs.contains($0.stageID)} && scene.rootNode.childNode(withName:subject.featureID.uuidString,recursively:false) != nil}) else{throw HouseError.message("Comparison inputs changed. Rebuild the tour preview.")}
    var rough=scope;rough.mode = .rough;rough.stage=nil
    guard SceneBuilder.features(house,options:rough).contains(where:{$0.id==feature.id}) else{throw HouseError.message("Comparison evidence is no longer in its checked frame.")}
    var mesh=feature.mesh
    if let id=feature.segmentID,let registration=house.segments.first(where:{$0.id==id})?.registration {mesh.vertices=mesh.vertices.map{registration.apply($0)}}
    var textures:[String:UIImage]=[:]
    let node=SceneBuilder.node(feature,mesh:mesh,uv:feature.uv,options:rough,textures:&textures,assetRoot:assetRoot)
    node.geometry?.firstMaterial?.emission.contents=UIColor(rgb:feature.trade.hex)
    scene.rootNode.addChildNode(node)
    apply(shot,to:scene,phase:shot.startPhase)
    return scene
  }
  static func apply(_ shot:TourShot,to scene:SCNScene,phase:Double) {
    guard let event=shot.reveal,let target=shot.subject else{return}
    SCNTransaction.begin();SCNTransaction.disableActions=true;SCNTransaction.animationDuration=0
    defer{SCNTransaction.commit()}
    let amount=event.amount(at:phase)
    for finish in event.finishes {
      if let node=scene.rootNode.childNode(withName:finish.featureID.uuidString,recursively:false) {
        // Retain a translucent context surface so missing capture never looks
        // like a certified empty cavity. Only the recorded target is revealed.
        node.opacity=CGFloat(1-0.85*amount)
        node.geometry?.firstMaterial?.writesToDepthBuffer=amount<0.001
      }
    }
    scene.rootNode.childNode(withName:target.featureID.uuidString,recursively:false)?.opacity=CGFloat(amount)
  }
}
