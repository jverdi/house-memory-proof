import SwiftUI

struct ServiceConnection:Codable,Identifiable,Equatable {
    var id=UUID();var fromFeature:UUID;var fromEnd:Int;var toFeature:UUID;var toEnd:Int
    var confirmed=false;var notes="";var date=Date()
}
struct ConnectionsPage:View {
    @EnvironmentObject var model:AppModel;var house:House
    @State private var from:UUID?;@State private var to:UUID?;@State private var fromEnd=0;@State private var toEnd=0
    @State private var confirmed=false;@State private var note=""
    var routes:[Feature]{house.features.filter{!$0.route.isEmpty}}
    var body:some View{Form{
        Section{Text("Only explicit endpoint links establish connectivity. Crossings, proximity and matching colors never connect routes automatically. Leave a link unconfirmed until you have evidence.").font(.footnote)}
        Section("Add endpoint link"){
            Picker("From route",selection:$from){Text("Choose").tag(UUID?.none);ForEach(routes){Text($0.name).tag(Optional($0.id))}}
            Picker("From end",selection:$fromEnd){Text("Start").tag(0);Text("End").tag(1)}.pickerStyle(.segmented)
            Picker("To route",selection:$to){Text("Choose").tag(UUID?.none);ForEach(routes){Text($0.name).tag(Optional($0.id))}}
            Picker("To end",selection:$toEnd){Text("Start").tag(0);Text("End").tag(1)}.pickerStyle(.segmented)
            TextField("Evidence, circuit or port notes",text:$note,axis:.vertical)
            Toggle("I verified this connection",isOn:$confirmed)
            Button("Save link"){guard let from,let to,from != to else{model.error="Choose two different routes.";return};model.edit{$0.connections.append(ServiceConnection(fromFeature:from,fromEnd:fromEnd,toFeature:to,toEnd:toEnd,confirmed:confirmed,notes:note))};note="";confirmed=false}
        }
        Section("Recorded links"){ForEach(house.connections){c in VStack(alignment:.leading){Text((house.features.first{$0.id==c.fromFeature}?.name ?? "Missing route")+" → "+(house.features.first{$0.id==c.toFeature}?.name ?? "Missing route"));Label(c.confirmed ? "User-confirmed":"Unconfirmed",systemImage:c.confirmed ? "checkmark.circle":"questionmark.circle").font(.caption).foregroundStyle(c.confirmed ? .mint:.secondary);Text(c.notes).font(.footnote)}}}
    }.navigationTitle("Service connections")}
}
