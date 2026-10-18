import Foundation

// A dated source inventory for owner review; counts never certify hidden work.
struct ClosureStageInventory:Codable,Identifiable {
  var id:UUID
  var name:String
  var kind:String
  var phase:String
  var declaredDate:Date
  var firstPhotoDate:Date?
  var lastPhotoDate:Date?
  var posedPhotos:Int
  var documentaryPhotos:Int
  var poseIneligiblePhotos:Int
  var sessions:Int
  var interruptedSessions:Int
  var unregisteredSessions:Int
  var observedFeatures:Int
  var reviewedCurrentObservedFeatures:Int
  var unreviewedCurrentObservedFeatures:Int
  var staleObservedFeatures:Int
  var plannedFeatures:Int
  var syntheticFeatures:Int
  var boundaryCount:Int
  var unconfirmedConnections:Int
}
struct ClosureInventory:Codable {
  var version=1
  var projectID:UUID
  var sourceRevision:Int
  var generatedUTC=Date()
  var roomID:UUID
  var roomName:String
  var level:Int
  var syntheticProject:Bool
  var stages:[ClosureStageInventory]
  var documentaryPhotosWithoutStage:Int
  var houseDocumentaryPhotosWithoutRoom:Int
  var notes:String
  var closureVerified=false
  var limitation="Source dates and review/dependency states only. A missing stage, unassigned photo, stale feature or unconfirmed connection stays visible. Counts do not prove observed coverage, unchanged construction, source accuracy or absence of concealed services. Boundary coverage is a separate sampled-plane check."
  static func build(house:House,roomID:UUID,stageID:UUID?=nil)throws->ClosureInventory {
    guard let room=house.rooms.first(where:{$0.id==roomID}) else{throw HouseError.message("Choose a room for closure review.")}
    let stages=house.stages.filter{stageID==nil || $0.id==stageID}
    guard !stages.isEmpty,stages.count<=256 else{throw HouseError.message("Choose one construction stage for this large project's review.")}
    let current=DerivedEvidence.currentIDs(house)
    let photos=Dictionary(grouping:house.observations.filter{$0.roomID==roomID},by:{$0.stageID})
    let features=Dictionary(grouping:house.features.filter{$0.roomID==roomID},by:{$0.stageID})
    let sessions=Dictionary(grouping:house.segments.filter{$0.roomID==roomID},by:{$0.stageID})
    let documentary=Dictionary(grouping:house.documentaryPhotos.filter{$0.roomID==roomID},by:{$0.stageID})
    let segmentStages=Dictionary(house.segments.map{($0.id,$0.stageID)},uniquingKeysWith:{first,_ in first})
    let featureScope=Dictionary(house.features.map{($0.id,($0.roomID,$0.stageID))},uniquingKeysWith:{first,_ in first})
    let rows=stages.sorted{($0.date,$0.id.uuidString)<($1.date,$1.id.uuidString)}.map{stage->ClosureStageInventory in
      let captures=photos[stage.id] ?? [],objects=features[stage.id] ?? [],segments=sessions[stage.id] ?? [],documents=documentary[Optional(stage.id)] ?? []
      let dates=captures.map{$0.date}+documents.map{$0.date}
      let observed=objects.filter{$0.kind == .observed},eligible=observed.filter{current.contains($0.id)}
      let unconfirmed=house.connections.filter{link in
        !link.confirmed && [link.fromFeature,link.toFeature].contains{id in featureScope[id].map{$0.0==roomID && $0.1==stage.id} ?? false}
      }.count
      let segmentIDs=Set(segments.map{$0.id})
      return ClosureStageInventory(id:stage.id,name:stage.name,kind:stage.kind.rawValue,phase:stage.category.rawValue,declaredDate:stage.date,
        firstPhotoDate:dates.min(),lastPhotoDate:dates.max(),posedPhotos:captures.filter{!$0.documentary}.count,
        documentaryPhotos:captures.filter{$0.documentary}.count+documents.count,poseIneligiblePhotos:captures.filter{!$0.documentary && !$0.spatialPoseEligible}.count,
        sessions:segments.count,interruptedSessions:segments.filter{$0.interrupted}.count,unregisteredSessions:segments.filter{$0.registration==nil}.count,
        observedFeatures:observed.count,reviewedCurrentObservedFeatures:eligible.filter{$0.reviewed}.count,
        unreviewedCurrentObservedFeatures:eligible.filter{!$0.reviewed}.count,staleObservedFeatures:observed.count-eligible.count,
        plannedFeatures:objects.filter{$0.kind == .planned}.count,syntheticFeatures:objects.filter{$0.kind == .synthetic}.count,
        boundaryCount:house.boundaries.filter{segmentIDs.contains($0.segmentID) && segmentStages[$0.segmentID]==stage.id}.count,unconfirmedConnections:unconfirmed)
    }
    return ClosureInventory(projectID:house.id,sourceRevision:house.revision,roomID:room.id,roomName:room.name,level:room.level,syntheticProject:house.isDemo,
      stages:rows,documentaryPhotosWithoutStage:documentary[nil]?.count ?? 0,houseDocumentaryPhotosWithoutRoom:house.documentaryPhotos.filter{$0.roomID==nil}.count,notes:house.closureNotes)
  }
}
