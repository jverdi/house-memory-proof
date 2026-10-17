import SwiftUI
import Darwin

struct FieldChecksPage:View {
  @EnvironmentObject var model:AppModel
  var house:House
  @State private var split:FieldSplit = .calibration
  @State private var kind:FieldCheckKind = .distance
  @State private var fixture=""
  @State private var session=""
  @State private var conditions=""
  @State private var measuredID:UUID?
  @State private var truthDistance=1.0
  @State private var truthPoint="0,0,0"
  @State private var uncertainty=0.002
  @State private var cameraDistance=1.5
  @State private var abstained=false
  @State private var visible=false
  @State private var saved=false
  var measurement:Dimension?{house.dimensions.first{$0.id==measuredID}}
  var body:some View {
    Form {
      Section("Prepare an independent fixture") {
        Text("Use accessible framing with a cable, pipe, box and ceiling-like surface. Establish fixed references, measure independent checkpoints, and record the uncertainty of those measurements.")
        Text("Capture exposed construction, then cover it with a removable finish of measured thickness. Repeat from new viewpoints and a later session. Keep calibration captures separate from validation; do not refit registration to validation checkpoints.")
        Text("Include an incorrect room or floor, the other side of a wall, a moved reference and tracking loss. The overlay should disappear when its alignment is not trustworthy.")
        Text("For device checks, run a 30-minute visit in short segments. Include backgrounding, interruption, reopening, movie resume and a Files-folder restore. Export the synthetic self-test report separately.")
      }.font(.footnote)
      Section("Record a field check") {
        Picker("Purpose",selection:$split){ForEach(FieldSplit.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        Picker("Check",selection:$kind){ForEach(FieldCheckKind.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        TextField("Fixture / independent region",text:$fixture)
        TextField("Session name / date",text:$session)
        TextField("Lighting, surface, lens, finish thickness and reference conditions",text:$conditions,axis:.vertical)
        if kind == .rejection {
          Toggle("Overlay remained visible",isOn:$visible)
          Text("Record what you actually observed during the rejection challenge. A visible overlay is a failed challenge.").font(.caption)
        }else{
          Toggle("App could not provide a usable result",isOn:$abstained)
          if !abstained {
            Picker("Saved measurement",selection:$measuredID){Text("Select").tag(Optional<UUID>.none);ForEach(house.dimensions){Text($0.name+" · "+$0.metres.formatted()+" m").tag(Optional($0.id))}}
            if let measurement {
              Text("Recorded distance: \(measurement.metres.formatted()) m").font(.caption)
              if !DerivedEvidence.measurementIsCurrent(measurement,house:house){Text("This measurement's source changed or is unlinked. Make a new measurement for the field check.").foregroundStyle(.orange)}
            }
            if kind == .distance {TextField("Independent true distance (metres)",value:$truthDistance,format:.number).keyboardType(.decimalPad)}
            else {
              TextField("Independent endpoint A coordinate: x,y,z metres",text:$truthPoint)
              Text("The independent coordinate must use the same registered house frame as endpoint A. A local unregistered point cannot qualify house placement.").font(.caption)
            }
          }
          TextField("Truth uncertainty (metres)",value:$uncertainty,format:.number).keyboardType(.decimalPad)
          TextField("Camera-to-surface distance (metres)",value:$cameraDistance,format:.number).keyboardType(.decimalPad)
        }
        Button("Save immutable check"){save()}.disabled(fixture.isEmpty || session.isEmpty || house.isDemo)
        if saved{Text("Saved with device, build and source evidence.").foregroundStyle(.mint)}
        if house.isDemo{Text("Create a real house to record field evidence.").font(.caption)}
      }
      Section("Recorded evidence") {
        let summary=FieldEvidence.summary(house.fieldChecks.filter{$0.kind==kind},split:split)
        Text("\(summary.accepted)/\(summary.attempts) usable nominal results · \(summary.independentSessions) named sessions")
        if let error=summary.p95Metres{Text("Recorded p95 error: \((error*1000).formatted()) mm")}
        Text("\(summary.visibleOnRejectionChallenges)/\(summary.criticalChallenges) rejection challenges left the overlay visible")
        Text("These are owner-recorded checks. Different phones, modes, conditions and check types must be evaluated separately; pooled results do not qualify a precision profile.").font(.caption)
        Button("Export field evidence") {
          do {
            let url=Exporter.destination("House-Xray-field-evidence.json")
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(house.fieldChecks).write(to:url,options:.atomic);model.shareURL=url
          }catch{model.error=error.localizedDescription}
        }
        ForEach(house.fieldChecks.reversed()){check in
          VStack(alignment:.leading){Text(check.fixture+" · "+check.kind.rawValue);Text(check.split.rawValue+" · "+check.session).font(.caption);if let error=check.errorMetres{Text("Error \((error*1000).formatted()) mm").font(.caption)}}
        }
      }
    }.navigationTitle("Field checks")
  }
  func save() {
    do {
      var source:Dimension?
      if kind != .rejection && !abstained {
        guard let measurement,DerivedEvidence.measurementIsCurrent(measurement,house:house) else{throw HouseError.message("Select a current measurement linked to captured geometry.")}
        if kind == .placement,measurement.segmentID != nil {throw HouseError.message("Register the capture and measure in the house frame before checking point placement.")}
        source=measurement
      }
      let reference:V3?
      if kind == .placement && !abstained {
        let points=try CheckedRegistration.coordinates(truthPoint);guard points.count==1 else{throw HouseError.message("Enter one independent x,y,z coordinate.")};reference=points[0]
      }else{reference=nil}
      var system=utsname();uname(&system)
      var machine=system.machine;let capacity=MemoryLayout.size(ofValue:machine)
      let hardware=withUnsafePointer(to:&machine){pointer in pointer.withMemoryRebound(to:CChar.self,capacity:capacity){String(cString:$0)}}
      let dependencies=source?.sourceGeometry ?? []
      let sources=house.features.filter{feature in dependencies.contains{$0.featureID==feature.id}}
      let originalIDs=Array(Set(sources.flatMap{$0.sourceIDs})).sorted{$0.uuidString<$1.uuidString}
      let observations=house.observations.filter{originalIDs.contains($0.id)}
      let modes=Set(observations.map{"\($0.width)×\($0.height) RGB; \($0.depthWidth)×\($0.depthHeight) depth"}).sorted().joined(separator:"; ")
      let check=FieldCheck(split:split,kind:kind,fixture:fixture,session:session,conditions:conditions,device:hardware+" / iOS "+UIDevice.current.systemVersion,sourceBuild:Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local",cameraMode:modes,truthUncertainty:uncertainty,cameraDistance:cameraDistance,measurement:source,referenceDistance:kind == .distance && !abstained ? truthDistance:nil,referencePoint:reference,abstained:abstained,overlayWasVisible:kind == .rejection ? visible:nil,originalIDs:originalIDs)
      guard check.valid else{throw HouseError.message("Check the finite measurements, uncertainty, distance and required field names.")}
      saved=model.edit{$0.fieldChecks.append(check)}
    }catch{model.error=error.localizedDescription}
  }
}
