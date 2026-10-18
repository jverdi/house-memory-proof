import Foundation

enum ServiceClass:String,Codable,CaseIterable {
  case unknown="Unknown",blocking="Structure / blocking",power="Electrical power",lowVoltage="Low voltage"
  case supply="Plumbing supply",drain="Plumbing drain",vent="Plumbing vent"
  case hvacSupply="HVAC supply",hvacReturn="HVAC return",exhaust="HVAC exhaust"
  case insulation="Insulation",fireStopping="Fire-stopping",access="Access point"
}
enum IdentityConfidence:String,Codable,CaseIterable {
  case unknown="Unknown",unconfirmed="Unconfirmed",ownerConfirmed="Owner confirmed"
}

// Recorded semantic evidence, never an input to measured geometry or automatic
// route connections. Missing fields remain unknown in older and current files.
struct ServiceDetails:Codable,Equatable {
  var classification:ServiceClass?=nil
  var observedLabel:String?=nil;var circuitReference:String?=nil;var panelReference:String?=nil
  var cableCategory:String?=nil;var endpoint:String?=nil;var port:String?=nil
  var conduitSize:String?=nil;var pipeDuctEnvelope:String?=nil;var installationDate:String?=nil
  var boundaryID:UUID?=nil;var confidence:IdentityConfidence?=nil;var identityEvidence:String?=nil
  static func validDate(_ value:String)->Bool {
    let bytes=Array(value.utf8)
    guard bytes.count==10,bytes[4]==45,bytes[7]==45,
      bytes.enumerated().allSatisfy({[4,7].contains($0.offset) || (48...57).contains($0.element)}),
      let year=Int(value.prefix(4)),let month=Int(value.dropFirst(5).prefix(2)),let day=Int(value.suffix(2)),year>0 else{return false}
    guard (1...12).contains(month) else{return false}
    let leap=year%4==0 && (year%100 != 0 || year%400==0)
    let days=[31,leap ? 29:28,31,30,31,30,31,31,30,31,30,31]
    return (1...days[month-1]).contains(day)
  }
  var textValues:[String] {[observedLabel,circuitReference,panelReference,cableCategory,endpoint,port,conduitSize,pipeDuctEnvelope,installationDate,identityEvidence].compactMap{$0}}
  var valid:Bool {
    guard textValues.allSatisfy({$0.utf8.count<=4096 && !$0.contains("\0")}),
      installationDate.map({Self.validDate($0)}) ?? true else{return false}
    return confidence != .ownerConfirmed || !(identityEvidence?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?? true)
  }
  var searchableText:String {(textValues+[classification?.rawValue ?? "",confidence?.rawValue ?? "",boundaryID?.uuidString ?? ""]).joined(separator:" ")}
  var isEmpty:Bool {self==ServiceDetails()}
}

#if canImport(UIKit)
import SwiftUI
struct ServiceDetailsFields:View {
  @Binding var details:ServiceDetails
  @FocusState.Binding var focusedField:String?
  let boundaries:[RevealBoundary]
  private func text(_ key:WritableKeyPath<ServiceDetails,String?>)->Binding<String> {
    Binding(get:{details[keyPath:key] ?? ""},set:{details[keyPath:key]=$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil:$0})
  }
  var body:some View {
    Section("Service details") {
      Picker("Service class",selection:Binding(get:{details.classification ?? .unknown},set:{details.classification=$0 == .unknown ? nil:$0})) {
        ForEach(ServiceClass.allCases,id:\.self){Text($0.rawValue).tag($0)}
      }.accessibilityIdentifier("object-service-class")
      TextField("Observed label",text:text(\.observedLabel)).accessibilityIdentifier("service-observed-label").focused($focusedField,equals:"Observed label")
      TextField("Panel reference",text:text(\.panelReference)).focused($focusedField,equals:"Panel reference")
      TextField("Circuit reference",text:text(\.circuitReference)).focused($focusedField,equals:"Circuit reference")
      TextField("Cable category",text:text(\.cableCategory)).focused($focusedField,equals:"Cable category")
      TextField("Endpoint",text:text(\.endpoint)).focused($focusedField,equals:"Endpoint")
      TextField("Port",text:text(\.port)).accessibilityIdentifier("service-port").focused($focusedField,equals:"Port")
      TextField("Conduit size, including units",text:text(\.conduitSize)).focused($focusedField,equals:"Conduit size, including units")
      TextField("Pipe / duct envelope, including units",text:text(\.pipeDuctEnvelope)).focused($focusedField,equals:"Pipe / duct envelope, including units")
      TextField("Installation date · YYYY-MM-DD",text:text(\.installationDate)).textInputAutocapitalization(.never).focused($focusedField,equals:"Installation date · YYYY-MM-DD")
      Picker("Associated boundary",selection:$details.boundaryID) {
        Text("Unknown").tag(Optional<UUID>.none)
        ForEach(boundaries){Text($0.name).tag(Optional($0.id))}
      }
      Picker("Identity confidence",selection:Binding(get:{details.confidence ?? .unknown},set:{details.confidence=$0 == .unknown ? nil:$0})) {
        ForEach(IdentityConfidence.allCases,id:\.self){Text($0.rawValue).tag($0)}
      }
      TextField("Identity evidence or test notes",text:text(\.identityEvidence),axis:.vertical).focused($focusedField,equals:"Identity evidence or test notes")
      Text("Leave unavailable details blank. Sizes are recorded descriptions, not measured geometry. Appearance alone does not prove gauge, contents, circuit identity or route continuity.").font(.footnote)
      if !details.valid {Text("Use a valid YYYY-MM-DD date, keep each field within 4,096 UTF-8 bytes, and describe the evidence for an owner-confirmed identity.").font(.footnote).foregroundStyle(.red)}
    }.submitLabel(.done).onSubmit{focusedField=nil}
  }
}

struct BatchServiceEditor:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.dismiss) private var dismiss
  @State var house:House
  @State private var selected=Set<UUID>()
  @State private var classification=ServiceClass.unknown
  @State private var trade=Trade.unknown
  @State private var query=""
  @FocusState private var filterFocused:Bool
  @State private var limit=200
  private var matches:[Feature] {
    let terms=EvidenceSearch.normalized(query).split(whereSeparator:{$0.isWhitespace})
    return house.features.filter{feature in
      let text=EvidenceSearch.normalized([feature.name,feature.notes,feature.endpoint,feature.trade.rawValue,feature.id.uuidString,feature.service?.searchableText ?? "",feature.envelope?.evidence ?? ""].joined(separator:" "))
      return terms.allSatisfy{text.contains($0)}
    }
  }
  var body:some View {
    NavigationStack {
      Form {
        Section("New classification") {
          Picker("System",selection:$trade){ForEach(Trade.allCases){Text($0.rawValue).tag($0)}}.accessibilityIdentifier("batch-system")
          Picker("Service class",selection:$classification){ForEach(ServiceClass.allCases,id:\.self){Text($0.rawValue).tag($0)}}.accessibilityIdentifier("batch-class")
          Text("Changes apply only to the selected objects. Source evidence, identity confirmation, geometry and connections are preserved. The batch is saved as one project revision.").font(.footnote)
        }
        Section("Objects · \(selected.count) selected") {
          TextField("Filter objects",text:$query).focused($filterFocused).submitLabel(.done)
            .onSubmit{filterFocused=false}.onChange(of:query){_,_ in limit=200}
          let found=matches
          ForEach(Array(found.prefix(limit))){feature in
            Toggle(isOn:Binding(get:{selected.contains(feature.id)},set:{if $0{selected.insert(feature.id)}else{selected.remove(feature.id)}})) {
              VStack(alignment:.leading){Text(feature.name);Text(house.rooms.first(where:{$0.id==feature.roomID})?.name ?? "Unknown room").font(.caption)}
            }.accessibilityIdentifier("batch-object-\(feature.id.uuidString)")
          }
          if found.count>limit {Button("Show more objects"){limit=min(10000,limit+200)}}
        }
      }.navigationTitle("Classify objects")
        .toolbar {
          ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
          ToolbarItem(placement:.confirmationAction){Button("Apply to \(selected.count) objects"){
            if model.classifyFeatures(house.features.filter{selected.contains($0.id)},classification:classification,trade:trade,projectID:house.id){dismiss()}
          }.disabled(selected.isEmpty)}
        }
    }.interactiveDismissDisabled(!selected.isEmpty)
  }
}
#endif
