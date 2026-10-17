import SwiftUI

struct VisualMapsPage:View {
  @EnvironmentObject var model:AppModel
  var house:House
  @State private var selected:UUID?
  var body:some View{Form{
    Text("Build an experimental visual reference from sharp, overlapping depth photographs. Later views must match two separated captured viewpoints. Blank planar walls are deliberately rejected. This does not enable a precision profile.").font(.footnote)
    Picker("Capture segment",selection:$selected){Text("Choose").tag(UUID?.none);ForEach(house.segments){s in Text("\(house.rooms.first(where:{$0.id==s.roomID})?.name ?? "Room") · \(house.stages.first(where:{$0.id==s.stageID})?.name ?? "Stage") · \(s.started.formatted())").tag(Optional(s.id))}}
    Button("Build visual reference"){
      guard let repo=model.repository,let s=house.segments.first(where:{$0.id==selected}) else{return}
      model.perform("Building local visual reference"){
        let map=try await Task.detached(priority:.userInitiated){try VisualMapping.build(house:house,segment:s,repo:repo)}.value
        guard let current=model.house,current.id==house.id,let segment=current.segments.first(where:{$0.id==s.id}),try VisualMapping.fingerprint(house:current,segment:segment)==map.fingerprint else{throw HouseError.message("Capture inputs changed. Rebuild the reference from the latest originals.")}
        let key=try repo.put(JSONEncoder().encode(map),ext:"vmap")
        model.edit{$0.visualMaps.removeAll{$0.segmentID==s.id};$0.visualMaps.append(VisualMapReference(segmentID:s.id,roomID:s.roomID,stageID:s.stageID,asset:key,fingerprint:map.fingerprint))}
        return nil
      }
    }.disabled(selected==nil || model.busy)
    Section("Saved references"){ForEach(house.visualMaps){ref in VStack(alignment:.leading){Text(house.rooms.first(where:{$0.id==ref.roomID})?.name ?? "Room");Text(ref.date.formatted()).font(.caption);Text("Experimental. Coordinate edits require rebuilding.").font(.caption)}}}
  }.navigationTitle("Visual references")}
}
