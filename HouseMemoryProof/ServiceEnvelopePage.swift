import SwiftUI
import UIKit

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
  @State private var tapered=false
  @State private var endWidth=""
  @State private var endHeight=""
  @State private var tolerance=""
  @State private var evidence=""
  @State private var axis=2
  @State private var confirmed=false
  private enum Field:Hashable {case width,height,endWidth,endHeight,tolerance,evidence}
  @FocusState private var focused:Field?
  private var widthAxis:V3 {axis==0 ? V3(1,0,0):axis==1 ? V3(0,1,0):V3(0,0,1)}
  private func size(_ text:String)->Double? {Double(text.trimmingCharacters(in:.whitespacesAndNewlines)).map{$0/1000}}
  private func dimensionField(_ title:String,text:Binding<String>,field:Field,id:String)->some View {
    VStack(alignment:.leading,spacing:4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      TextField(title,text:text).keyboardType(.decimalPad).focused($focused,equals:field).accessibilityIdentifier(id)
    }
  }
  private var declaration:ServiceEnvelope {
    ServiceEnvelope(version:tapered ? 3:connected ? 2:1,sourceFeatureID:source.id,sourceRevision:source.revision,sourceInterval:interval,sourceEndInterval:connected ? endInterval:nil,section:section,widthMetres:size(width) ?? .nan,heightMetres:section == .rectangular ? size(height):nil,widthAxis:section == .rectangular ? widthAxis:nil,endWidthMetres:tapered ? size(endWidth) ?? .nan:nil,endHeightMetres:tapered && section == .rectangular ? size(endHeight) ?? .nan:nil,dimensionToleranceMetres:tolerance.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil:size(tolerance) ?? .nan,evidence:evidence)
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
        dimensionField((tapered ? "Start ":"")+(section == .round ? "Outer diameter · mm":"Outer width · mm"),text:$width,field:.width,id:"envelope-width")
        if section == .rectangular {
          dimensionField((tapered ? "Start ":"")+"Outer height · mm",text:$height,field:.height,id:"envelope-height")
          Picker("Width direction",selection:$axis){Text("X direction").tag(0);Text("Y direction").tag(1);Text("Z direction").tag(2)}
          Text("Direction uses the source route's coordinate frame. The chosen axis is projected across this interval; use the direction you measured as width. A nearly parallel direction is refused.").font(.caption)
        }
        Toggle("Measured linear taper",isOn:$tapered).accessibilityIdentifier("envelope-tapered")
        if tapered {
          Text("The first size is at source point \(interval+1). Enter the size at point \(interval+2) below. Check that this visible straight interval changes size linearly; two endpoint measurements alone do not establish the shape between them. Curved reducers and hidden transitions remain unknown.").font(.caption)
          dimensionField(section == .round ? "End outer diameter · mm":"End outer width · mm",text:$endWidth,field:.endWidth,id:"envelope-end-width")
          if section == .rectangular {dimensionField("End outer height · mm",text:$endHeight,field:.endHeight,id:"envelope-end-height")}
        }
        TextField("Dimension tolerance · ± mm, if known",text:$tolerance).keyboardType(.decimalPad).focused($focused,equals:.tolerance)
        Text("An entered tolerance describes the recorded size only. It is not a calibrated confidence interval or a bound on centerline placement. Leave it blank when unknown.").font(.caption)
        TextField("Measurement method and source evidence",text:$evidence,axis:.vertical).focused($focused,equals:.evidence).accessibilityIdentifier("envelope-evidence")
        Toggle(tapered ? "I measured both ends and checked the straight linear taper":connected ? "I measured this diameter along every selected interval":"I measured this interval's outer size",isOn:$confirmed).accessibilityIdentifier("envelope-confirm")
      }
      Section {
        Text("The envelope is saved as a separate approximate object linked to this source revision. Editing or re-registering the source makes it stale. End caps only delimit this recorded interval; no physical closure or connection is inferred.").font(.footnote)
        Button("Save measured envelope") {save()}.disabled(!confirmed || !declaration.valid).accessibilityIdentifier("envelope-save")
      }
    }.navigationTitle("Service envelope").scrollDismissesKeyboard(.immediately)
      .onChange(of:section){_,value in confirmed=false;if value != .round {connected=false}}
      .onChange(of:connected){_,value in confirmed=false;if value {tapered=false}}
      .onChange(of:tapered){_,value in confirmed=false;if value {connected=false}}
      .onChange(of:width){_,_ in confirmed=false}.onChange(of:height){_,_ in confirmed=false}
      .onChange(of:endWidth){_,_ in confirmed=false}.onChange(of:endHeight){_,_ in confirmed=false}
      .onChange(of:interval){_,_ in confirmed=false}
      .onChange(of:endInterval){_,_ in confirmed=false}.toolbar {
      ToolbarItemGroup(placement:.keyboard){
        if focused != nil {
          Spacer();Button("Done"){
            focused=nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
          }.accessibilityIdentifier("envelope-keyboard-done")
        }
      }
    }
  }
  private func save(){
    do {
      guard let house=model.houses.first(where:{$0.id==projectID}) else{throw HouseError.message("The source project is unavailable.")}
      let value=declaration
      let feature=try ServiceEnvelope.feature(source:source,interval:interval,endInterval:connected ? endInterval:nil,section:value.section,width:value.widthMetres,height:value.heightMetres,widthAxis:value.widthAxis,tolerance:value.dimensionToleranceMetres,evidence:value.evidence,house:house,endWidth:value.endWidthMetres,endHeight:value.endHeightMetres)
      if model.edit(projectID:projectID,{$0.features.append(feature)}){dismiss()}
    }catch{model.error=error.localizedDescription}
  }
}
