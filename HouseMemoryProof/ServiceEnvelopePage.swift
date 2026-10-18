import SwiftUI

struct ServiceEnvelopePage:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.dismiss) private var dismiss
  let source:Feature
  let projectID:UUID
  @State private var interval=0
  @State private var connected=false
  @State private var endInterval=1
  @State private var section:EnvelopeSection = .round
  @State private var width=""
  @State private var height=""
  @State private var tolerance=""
  @State private var evidence=""
  @State private var axis=2
  @State private var confirmed=false
  @FocusState private var focused:Bool
  private var widthAxis:V3 {axis==0 ? V3(1,0,0):axis==1 ? V3(0,1,0):V3(0,0,1)}
  private func size(_ text:String)->Double? {Double(text.trimmingCharacters(in:.whitespacesAndNewlines)).map{$0/1000}}
  private var declaration:ServiceEnvelope {
    ServiceEnvelope(version:connected ? 2:1,sourceFeatureID:source.id,sourceRevision:source.revision,sourceInterval:interval,sourceEndInterval:connected ? endInterval:nil,section:section,widthMetres:size(width) ?? .nan,heightMetres:section == .rectangular ? size(height):nil,widthAxis:section == .rectangular ? widthAxis:nil,dimensionToleranceMetres:tolerance.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil:size(tolerance) ?? .nan,evidence:evidence)
  }
  var body:some View {
    Form {
      Section("Recorded outer envelope") {
        Text("Record a pipe, duct, conduit or bundle's measured outer size. A circular section can follow connected recorded intervals when the same diameter was measured throughout. Fittings, hidden continuation and bundle members remain unknown.").font(.footnote)
        Picker("Source interval",selection:$interval){ForEach(0..<max(0,source.route.count-1),id:\.self){i in
          Text("\(i+1) · \((source.route[i+1]-source.route[i]).length.formatted(.number.precision(.fractionLength(2)))) m centerline").tag(i)
        }}
        Picker("Cross section",selection:$section){ForEach(EnvelopeSection.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        if section == .round && source.route.count>2 {
          Toggle("Measured along connected intervals",isOn:$connected).accessibilityIdentifier("envelope-connected")
          if connected {
            Picker("Last source interval",selection:$endInterval){ForEach(1..<source.route.count-1,id:\.self){i in Text("\(i+1)").tag(i)}}
            Text("Choose a last interval after the start. Bends follow the recorded points with mitered circular sections; no curved fitting is inferred. Tight, reversing or overlapping intervals are refused.").font(.caption)
          }
        }
        TextField(section == .round ? "Outer diameter · mm":"Outer width · mm",text:$width).keyboardType(.decimalPad).focused($focused).accessibilityIdentifier("envelope-width")
        if section == .rectangular {
          TextField("Outer height · mm",text:$height).keyboardType(.decimalPad).focused($focused)
          Picker("Width direction",selection:$axis){Text("X direction").tag(0);Text("Y direction").tag(1);Text("Z direction").tag(2)}
          Text("Direction uses the source route's coordinate frame. The chosen axis is projected across this interval; use the direction you measured as width. A nearly parallel direction is refused.").font(.caption)
        }
        TextField("Dimension tolerance · ± mm, if known",text:$tolerance).keyboardType(.decimalPad).focused($focused)
        Text("An entered tolerance describes the recorded size only. It is not a calibrated confidence interval or a bound on centerline placement. Leave it blank when unknown.").font(.caption)
        TextField("Measurement method and source evidence",text:$evidence,axis:.vertical).focused($focused).accessibilityIdentifier("envelope-evidence")
        Toggle(connected ? "I measured this diameter along every selected interval":"I measured this interval's outer size",isOn:$confirmed).accessibilityIdentifier("envelope-confirm")
      }
      Section {
        Text("The envelope is saved as a separate approximate object linked to this source revision. Editing or re-registering the source makes it stale. End caps only delimit this recorded interval; no physical closure or connection is inferred.").font(.footnote)
        Button("Save measured envelope") {save()}.disabled(!confirmed || !declaration.valid).accessibilityIdentifier("envelope-save")
      }
    }.navigationTitle("Service envelope").scrollDismissesKeyboard(.immediately)
      .onChange(of:section){_,value in confirmed=false;if value != .round {connected=false}}
      .onChange(of:connected){_,_ in confirmed=false}
      .onChange(of:interval){_,_ in confirmed=false}
      .onChange(of:endInterval){_,_ in confirmed=false}.toolbar {
      ToolbarItemGroup(placement:.keyboard){Spacer();Button("Done"){focused=false}.accessibilityIdentifier("envelope-keyboard-done")}
    }
  }
  private func save(){
    do {
      guard let house=model.houses.first(where:{$0.id==projectID}) else{throw HouseError.message("The source project is unavailable.")}
      let value=declaration
      let feature=try ServiceEnvelope.feature(source:source,interval:interval,endInterval:connected ? endInterval:nil,section:value.section,width:value.widthMetres,height:value.heightMetres,widthAxis:value.widthAxis,tolerance:value.dimensionToleranceMetres,evidence:value.evidence,house:house)
      if model.edit(projectID:projectID,{$0.features.append(feature)}){dismiss()}
    }catch{model.error=error.localizedDescription}
  }
}
