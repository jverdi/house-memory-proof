import SwiftUI

struct StagesPage:View {
  @EnvironmentObject var model:AppModel
  var house:House
  @State private var editing:Stage?
  var body:some View {
    List {
      Section {
        Text("Keep each construction date separate. Rough-in and finished categories drive layer switches; names can describe inspections, late changes, or repairs.").font(.footnote)
        Button("Add construction stage"){editing=Stage(name:"New capture stage",kind:house.isDemo ? .synthetic:.observed,phase:.rough)}
      }
      ForEach(house.stages){stage in
        Button {editing=stage} label:{VStack(alignment:.leading){Text(stage.name);Text("\(stage.category.rawValue) · \(stage.date.formatted(date:.abbreviated,time:.omitted))").font(.caption).foregroundStyle(.secondary)}}
      }
    }.navigationTitle("Construction stages").sheet(item:$editing){stage in StageEditor(houseID:house.id,stage:stage)}
  }
}
struct StageEditor:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.dismiss) var dismiss
  var houseID:UUID
  @State var stage:Stage
  var body:some View {
    NavigationStack {
      Form {
        TextField("Stage name",text:$stage.name)
        DatePicker("Construction date",selection:$stage.date,displayedComponents:.date)
        Picker("Layer category",selection:Binding(get:{stage.category},set:{stage.phase=$0})) {ForEach(ConstructionPhase.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        Text("Changing a category changes visibility, not the geometry or original photographs. Other stages remain available under All evidence.").font(.footnote)
      }.navigationTitle("Construction stage").toolbar {
        ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button("Save"){
          guard !stage.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
          if model.edit(projectID:houseID,{h in if let i=h.stages.firstIndex(where:{$0.id==stage.id}){h.stages[i]=stage}else{h.stages.append(stage)}}){dismiss()}
        }}
      }
    }
  }
}
