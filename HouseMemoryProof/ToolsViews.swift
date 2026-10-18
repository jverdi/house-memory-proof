import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ToolsPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var importing = false
  @State private var pointCloudImport:PointCloudImport?
  @State private var importReport=""
  @State private var mode: ViewMode = .rough
  @State private var ceilings = true
  @State private var duration = 20.0
  @State private var tourPreset:TourPreset = .overview
  @State private var exportRoom:UUID?
  @State private var exportStage:UUID?
  @State private var diagnostics = ""
  var options: SceneOptions { SceneOptions(mode: mode, ceilings: ceilings,room:exportRoom,stage:exportStage) }
  var body: some View {
    NavigationStack {
      Form {
        Section("Plans and spatial record") {
          NavigationLink("Construction stages") { StagesPage(house:house) }
          NavigationLink("Service endpoint connections") { ConnectionsPage(house: house) }
          NavigationLink("Drawings & design references") { PlansPage(house: house) }
          NavigationLink("Saved measurements (approximate)") {
            List {
              ForEach(house.dimensions) { d in
                VStack(alignment: .leading) {
                  Text(d.name).font(.headline)
                  Text(
                    "\(d.metres.formatted(.number.precision(.fractionLength(3)))) m  /  \((d.metres*3.2808399).formatted(.number.precision(.fractionLength(2)))) ft"
                  )
                  Text(
                    "\(d.source) · \(DerivedEvidence.measurementIsCurrent(d,house:house) ? "source geometry current":"historical measurement; source changed or unlinked")"
                  ).font(.caption).foregroundStyle(.secondary)
                  if let dependencies=d.sourceGeometry {
                    ForEach(dependencies,id:\.featureID){dependency in
                      if let source=house.features.first(where:{$0.id==dependency.featureID}) {
                        Text("\(source.name) · \(house.stages.first(where:{$0.id==source.stageID})?.name ?? "Unknown stage")").font(.caption)
                      }
                    }
                  }
                }
              }
            }.navigationTitle("Measurements")
          }
          NavigationLink("Printable references") { ReferencesPage(house: house) }
          NavigationLink("Visual references") { VisualMapsPage(house: house) }
          NavigationLink("Register capture segments") { RegistrationPage(house: house) }
          NavigationLink("Capture coverage") { CoveragePage(house: house) }
          NavigationLink("Reconstruct saved depth") { ReconstructionPage(house: house) }
        }
        Section("Export scope") {
          Picker("Room",selection:$exportRoom) {
            Text("All registered rooms").tag(Optional<UUID>.none)
            ForEach(house.rooms){Text("Level \($0.level) · \($0.name)").tag(Optional($0.id))}
          }
          Picker("Stage",selection:$exportStage) {
            Text("Selected layer stages").tag(Optional<UUID>.none)
            ForEach(house.stages){Text($0.name).tag(Optional($0.id))}
          }
          Picker("Layers", selection: $mode) {
            ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
          }
          Toggle("Include ceilings", isOn: $ceilings)
          Text(
            "Exported geometry is in metres. Unregistered captures remain in separate frames; a geometry export shows one unregistered session at a time. Register sessions before combining them. The complete archive retains every original and session."
          ).font(.caption)
        }
        Section("Automatic tour") {
          Picker("Film",selection:$tourPreset){ForEach(TourPreset.allCases){Text($0.rawValue).tag($0)}}
          if tourPreset == .beforeAfter {Text("Comparison films use both rough-in and finished stages.").font(.caption)}
          Slider(value: $duration, in: 10...60, step: 5)
          Text("\(Int(duration)) seconds · 1080p · 30 fps")
          Button("Create fly-through video") {
            guard let repo = model.repository else { return }
            model.perform("Rendering automatic tour") {
              try await MovieExporter.render(
                house, repo: repo, options: options, duration: duration,preset:tourPreset
              ) { model.progress = $0 }
            }
          }.disabled(model.busy)
          NavigationLink("Preview shot list") {
            TourShotPreviewPage(house:house,options:options,preset:tourPreset,duration:duration)
          }
          Text(
            "Shots frame visible geometry from captured viewpoints. Rooms and interrupted paths use cuts; the shot list explains omitted views. Keep the app open. Completed shots resume on retry."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        Section("Reusable 3D") {
          Text("GLB includes level, room and stage groups, source identities and automatic tour camera clips.").font(.caption)
          Button("Export GLB") {
            export("Writing GLB") { try Exporter.glb(house, options: options) }
          }
          Button("Export USDZ") {
            export("Writing USDZ") { try Exporter.usdz(house, options: options) }
          }
          Button("Export PLY") {
            export("Writing PLY") { try Exporter.meshText(house, options: options, ply: true) }
          }
          Button("Export OBJ") {
            export("Writing OBJ") { try Exporter.meshText(house, options: options, ply: false) }
          }
          Text("Metadata JSON and semantic CSV include all project records, including hidden features and separate capture frames.").font(.caption)
          Button("Export semantic CSV") {
            export("Writing semantic records") { try Exporter.semanticCSV(house) }
          }
          Button("Export metadata JSON") {
            export("Writing metadata") { try Exporter.metadata(house) }
          }
        }
        Section("Backup and recovery") {
          NavigationLink("Automatic folder snapshots") { SnapshotSettings(house: house) }
          Button("Export complete house archive") {
            guard let r = model.repository else { return }
            export("Verifying and archiving originals") { try Exporter.archive(house, repo: r) }
          }
          Button("Import archive, IFC or point cloud") { importing = true }
          if !importReport.isEmpty {Text(importReport).font(.footnote)}
          Button("Restore previous local revision") { model.undo() }
          Text(
            "Save your archive to iCloud Drive or external storage using Files. Portable archives and optional incremental folder snapshots preserve separate revisions; they do not merge edits from different devices. Archives stream originals in bounded buffers using ZIP64; available device storage is the practical limit. Originals are never evicted."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        Section("Diagnostics") {
          NavigationLink("Field checks and calibration evidence"){FieldChecksPage(house:house)}
          Button("Load paired simulated house captures") {
            guard let repo = model.repository,
              let folder = Bundle.main.url(forResource: "IFC", withExtension: nil)
            else { return }
            model.perform("Restoring simulated rough-in and finished captures") {
              let h = try await Task.detached {
                try Exporter.restore(
                  folder.appendingPathComponent("synthetic-house.hxray"), repo: repo)
              }.value
              model.commit(h)
              return nil
            }
          }
          Button("Generate simulated capture project") {
            guard let repo = model.repository else { return }
            model.perform("Rendering synthetic camera evidence") {
              let h = try await Task.detached { try SimulatedCapture.make(repo: repo) }.value
              model.commit(h)
              return nil
            }
          }
          Button("Check original file integrity") {
            guard let repo=model.repository else{return}
            model.perform("Verifying original file integrity") {
              let count=try await LocalWorker.run {try house.validate();return try repo.integrity(house)}
              diagnostics="Verified \(count) original asset hashes. Project schema valid."
              return nil
            }
          }.disabled(model.busy)
          Button("Run synthetic self-tests") {
            model.perform("Running isolated synthetic diagnostics") {
              await SelfTests.run(model: model,includeMovie:true)
              diagnostics = "Self-test report saved. Use Export diagnostics to inspect the pass/fail results."
              return nil
            }
          }.disabled(model.busy)
          Button("Export diagnostics") {
            guard let repo = model.repository else { return }
            let url = repo.root.appendingPathComponent("self-test.json")
            if FileManager.default.fileExists(atPath: url.path) {
              model.shareURL = url
            } else {
              model.error = "Run self-tests first."
            }
          }
          if !diagnostics.isEmpty { Text(diagnostics).font(.footnote) }
          Text(
            "Build \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "local") · \(Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local")"
          ).font(.caption)
        }
        Section { NavigationLink("About and open-source notices") { AboutPage() } }
        Section("Accuracy status") {
          Text(
            "Experimental local reconstruction. No device precision profile is enabled. Photographs preserve what was seen; AR maps and LiDAR geometry do not establish millimetre accuracy. Review unknown or occluded areas before closing walls."
          ).font(.footnote)
        }
      }.navigationTitle("Tools").fileImporter(
        isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls): if let url = urls.first { importFile(url) }
        case .failure(let error): model.error = error.localizedDescription
        }
      }.sheet(item:$pointCloudImport){PointCloudImportPage(candidate:$0)}
    }
  }
  func export(_ label: String, _ work: @escaping () throws -> URL) {
    model.perform(label) { try await LocalWorker.run { try work() } }
  }
  func importFile(_ url: URL) {
    guard let repo = model.repository else { return }
    importReport=""
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      if url.pathExtension.lowercased() == "ifc" {
        let data = try DurableFiles.read(url,limit:50_000_000)
        guard let room = house.rooms.first else { return }
        let key = try repo.put(data, ext: "ifc")
        let stage = Stage(name: "Imported IFC design", kind: .planned,phase:.other)
        let drawing=Drawing(name:url.lastPathComponent,asset:key,notes:"Original IFC retained. Design coordinates remain in a separate source frame; house alignment is unknown.")
        let projectID = house.id
        guard model.edit(projectID:projectID,{
          $0.drawings.append(drawing)
          $0.stages.append(stage)
        }) else{return}
        model.perform("Converting IFC locally") {
          let importer = IFCImporter()
          let features = try await importer.load(data, roomID: room.id, stageID: stage.id)
          try Task.checkCancellation()
          guard let current=model.house,current.id == projectID else {
            throw HouseError.message("Project changed; import not published.")
          }
          guard let graph=importer.propertyGraph else{throw HouseError.message("IFC property conversion did not finish.")}
          let properties=try graph.store(in:repo)
          let updated=try IFCSourceEvidence.applying(features,source:drawing,stage:stage,roomID:room.id,coordinates:importer.coordinateReference,properties:properties,to:current)
          if model.commit(updated,select:false) {importReport="IFC design imported in its own source frame. Choose Imported IFC design in Explore → Layers to inspect it. House alignment remains unknown."}
          return nil
        }
      } else if url.pathExtension.lowercased() == "ply" {
        let data = try DurableFiles.read(url,limit:50_000_000)
        let asset = try repo.put(data, ext: "ply")
        let drawing=Drawing(name:url.lastPathComponent,asset:asset,notes:"Original PLY retained. Units, upright axis and house alignment unknown until explicitly declared.")
        let projectID=house.id
        guard model.edit(projectID:projectID,{$0.drawings.append(drawing)}) else{return}
        model.perform("Reading saved point cloud") {
          do {
            let mesh=try await LocalWorker.run{try PLYReader.read(data)}
            try Task.checkCancellation()
            pointCloudImport=PointCloudImport(projectID:projectID,drawing:drawing,mesh:mesh)
          }catch is CancellationError{throw CancellationError()}
          catch{throw HouseError.message("Original PLY saved in Drawings & design references. \(error.localizedDescription)")}
          return nil
        }
      } else {
        model.commit(try Exporter.restore(url, repo: repo))
      }
    } catch { model.error = error.localizedDescription }
  }
}
struct TourShotPreviewPage:View {
  @Environment(\.scenePhase) private var scenePhase
  let house:House
  let options:SceneOptions
  let preset:TourPreset
  let duration:Double
  @State private var plan:TourPlan?
  @State private var failure=""
  private var requestID:String {
    [house.id.uuidString,String(house.revision),options.mode.rawValue,options.trades.map{$0.rawValue}.sorted().joined(separator:","),options.room?.uuidString ?? "all",options.stage?.uuidString ?? "all",String(options.ceilings),preset.rawValue,String(duration),String(describing:scenePhase)].joined(separator:"|")
  }
  var body:some View {
    Group {
      if let plan {
        List {
          ForEach(Array(plan.shots.enumerated()),id:\.offset){index,shot in
            VStack(alignment:.leading){
              Text("\(index+1). \(shot.caption)")
              Text("\(shot.duration.formatted(.number.precision(.fractionLength(2)))) seconds").font(.caption)
              if let id=shot.subject?.featureID,let feature=house.features.first(where:{$0.id==id}) {Text("Subject: "+feature.name).font(.caption)}
              if shot.reveal != nil {Text("Same camera: finish fades, recorded evidence appears, then context returns. Uncaptured areas remain unknown.").font(.caption)}
              if shot.includesPlannedGeometry==true {Text("Includes planned geometry").font(.caption)}
            }
          }
          ForEach(Array(plan.excluded.enumerated()),id:\.offset){_,reason in Text(reason).font(.caption)}
        }
      }else if !failure.isEmpty {Text(failure).padding()}
      else {ProgressView("Planning visible camera shots")}
    }.navigationTitle("Automatic shots").task(id:requestID) {
      plan=nil;failure=""
      guard scenePhase == .active else{return}
      let snapshot=house,scope=options,choice=preset,seconds=duration
      do {plan=try await LocalWorker.run{TourDirector.plan(snapshot,duration:seconds,options:scope,preset:choice)}}
      catch is CancellationError {}catch{failure=error.localizedDescription}
    }
  }
}

struct PlansPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var importing = false
  @State private var selected: Drawing?
  var body: some View {
    List {
      Section {
        Text(
          "Design drawings remain separate from observed geometry. Scale calibration does not align a sheet with the captured house."
        ).font(.footnote)
        Button("Import drawing or source file") { importing = true }
      }
      ForEach(house.drawings) { d in
        Button {
          selected = d
        } label: {
          VStack(alignment: .leading) {
            Text(d.name)
            Text(
              d.metresPerPoint.map { "\($0.formatted()) m / PDF point" } ?? "Uncalibrated source"
            ).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }.navigationTitle("Drawings").fileImporter(
      isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first, let repo = model.repository {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
          let data = try DurableFiles.read(url,limit:50_000_000)
          guard data.count < 50_000_000 else {
            throw HouseError.message("Drawing import limit is 50 MB.")
          }
          let asset = try repo.put(
            data, ext: url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber })
          model.edit { $0.drawings.append(Drawing(name: url.lastPathComponent, asset: asset)) }
        } catch { model.error = error.localizedDescription }
      }
    }.sheet(item: $selected) { DrawingPage(drawing: $0) }
  }
}
struct DrawingPage: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State var drawing: Drawing
  @State private var points: [CGPoint] = []
  @State private var metres = 1.0
  @State private var document: PDFDocument?
  @State private var selectedPage = 0
  @State private var pointCloudImport:PointCloudImport?
  @State private var ifcRoom:UUID?
  @State private var ifcReport=""
  var body: some View {
    NavigationStack {
      VStack {
        if let document {
          PDFSurface(document: document, points: $points, selectedPage: $selectedPage).background(
            .white)
          Text(
            "Tap two points on one page, then enter their known real distance. \(points.count)/2 points."
          ).font(.caption).padding(.horizontal)
          HStack {
            TextField("Metres", value: $metres, format: .number).keyboardType(.decimalPad)
              .textFieldStyle(.roundedBorder)
            Text("m")
            Button("Calibrate") {
              if points.count == 2 {
                let distance = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
                if distance > 1 && metres > 0 {
                  drawing.metresPerPoint = metres / Double(distance)
                  drawing.page = selectedPage
                  drawing.alignment = nil
                  model.edit { h in
                    for i in h.features.indices where h.features[i].sourceDrawingID == drawing.id {
                      h.features[i].artifactValid = false
                    }
                  }
                  points = []
                }
              }
            }
            Button("Reset") { points = [] }
          }.padding()
          if let scale = drawing.metresPerPoint {
            Text("Scale: \(scale.formatted()) m / PDF point · design scale only").font(.caption)
          }
          NavigationLink("Labels and boundary suggestions") {DrawingMarksPage(drawing:drawing,document:document,didSave:{drawing.marks=$0})}
          NavigationLink("Align sheet to house") {
            DrawingAlignmentPage(drawing: $drawing, document: document)
          }
        } else {
          ScrollView {VStack(spacing:12) {
          ContentUnavailableView(
            "Source preserved", systemImage: "doc",
            description: Text(
              "This original file is retained in the archive. Preview supports PDF and images. Supported spatial files can be converted locally below."
            ))
          Button("Share original") {
            if let url = try? model.repository?.assetURL(drawing.asset) { model.shareURL = url }
          }
          if drawing.asset.hasSuffix(".ply") {
            Button("Import this point cloud") {
              guard let repo=model.repository,let house=model.house,let original=house.drawings.first(where:{$0.id==drawing.id}) else{return}
              model.perform("Reading saved point cloud") {
                let mesh=try await LocalWorker.run{try PLYReader.read(repo.read(original.asset,limit:50_000_000))}
                try Task.checkCancellation()
                pointCloudImport=PointCloudImport(projectID:house.id,drawing:original,mesh:mesh)
                return nil
              }
            }.disabled(model.busy)
          }
          if drawing.asset.hasSuffix(".ifc") {
            Picker("Room association",selection:$ifcRoom) {
              Text("Choose room").tag(Optional<UUID>.none)
              ForEach(model.house?.rooms ?? []) {Text($0.name).tag(Optional($0.id))}
            }.accessibilityIdentifier("ifc-source-room")
            Button("Import this IFC design") {
              guard let repo=model.repository,let house=model.house,let roomID=ifcRoom,let original=house.drawings.first(where:{$0.id==drawing.id}) else{return}
              let stage=Stage(name:"Imported IFC design",kind:.planned,phase:.other)
              guard model.edit(projectID:house.id,{$0.stages.append(stage)}) else{return}
              ifcReport=""
              model.perform("Converting saved IFC locally") {
                let data=try await LocalWorker.run{try repo.read(original.asset,limit:50_000_000)}
                let importer=IFCImporter()
                let features=try await importer.load(data,roomID:roomID,stageID:stage.id)
                try Task.checkCancellation()
                guard let current=model.house,current.id==house.id else{throw HouseError.message("Project changed; import not published.")}
                guard let graph=importer.propertyGraph else{throw HouseError.message("IFC property conversion did not finish.")}
                let properties=try graph.store(in:repo)
                let updated=try IFCSourceEvidence.applying(features,source:original,stage:stage,roomID:roomID,coordinates:importer.coordinateReference,properties:properties,to:current)
                if model.commit(updated,select:false){drawing.ifcCoordinates=importer.coordinateReference;drawing.ifcProperties=properties;ifcReport="Imported \(features.count) design meshes in a separate source frame. House alignment remains unknown. Choose Imported IFC design in Explore → Layers."}
                return nil
              }
            }.disabled(model.busy || ifcRoom==nil)
            if let reference=drawing.ifcCoordinates {Text(reference.summary+" CRS metadata is retained without applying a house alignment.").font(.caption).accessibilityIdentifier("ifc-source-coordinates")}
            if let properties=drawing.ifcProperties {
              Text(properties.summary.description).font(.caption).accessibilityIdentifier("ifc-source-properties")
              NavigationLink("Inspect source properties") {IFCPropertiesPage(reference:properties)}
              Button("Share source properties") {if let url=try? model.repository?.assetURL(properties.asset){model.shareURL=url}}
            }
            if !ifcReport.isEmpty {Text(ifcReport).font(.footnote).accessibilityIdentifier("ifc-source-result")}
          }
          }.padding(.horizontal)}
        }
        TextField("Source notes", text: $drawing.notes, axis: .vertical).padding()
      }.navigationTitle(drawing.name).navigationBarTitleDisplayMode(.inline).toolbar {
        Button("Save") {
          model.edit {
            if let i = $0.drawings.firstIndex(where: { $0.id == drawing.id }) {
              var saved=drawing;saved.ifcCoordinates=$0.drawings[i].ifcCoordinates;saved.ifcProperties=$0.drawings[i].ifcProperties;saved.marks=$0.drawings[i].marks
              $0.drawings[i] = saved
            }
          }
          dismiss()
        }
      }.sheet(item:$pointCloudImport){PointCloudImportPage(candidate:$0)}.task {
        if let url = try? model.repository?.assetURL(drawing.asset) {
          if let pdf = PDFDocument(url: url) {
            document = pdf
          } else if let image = UIImage(contentsOfFile: url.path), let page = PDFPage(image: image)
          {
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            document = pdf
          }
        }
      }
    }
  }
}
struct PDFSurface: UIViewRepresentable {
  var document: PDFDocument
  @Binding var points: [CGPoint]
  @Binding var selectedPage: Int
  var maximumPoints = 2
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.document = document
    view.autoScales = true
    view.displayMode = .singlePage
    view.usePageViewController(true)
    if let page = document.page(at: selectedPage) { view.go(to: page) }
    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.tap(_:)))
    view.addGestureRecognizer(tap)
    return view
  }
  func updateUIView(_ v: PDFView, context: Context) { context.coordinator.parent = self }
  class Coordinator: NSObject {
    var parent: PDFSurface
    var page: PDFPage?
    init(_ p: PDFSurface) { parent = p }
    @objc func tap(_ g: UITapGestureRecognizer) {
      guard let v = g.view as? PDFView, let page = v.page(for: g.location(in: v), nearest: true)
      else { return }
      if self.page !== page || parent.points.count >= parent.maximumPoints { parent.points = [] }
      self.page = page
      parent.selectedPage = parent.document.index(for: page)
      parent.points.append(v.convert(g.location(in: v), to: page))
    }
  }
}
struct RegistrationPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var selected: UUID?
  @State private var anchorID:UUID?
  @State private var source = ""
  @State private var target = ""
  @State private var report = ""
  var body: some View {
    Form {
      Text(
        "Manual reference registration. Enter at least four corresponding measured points in metres. The first three fit a rigid transform; additional points independently check it. This does not enable a precision claim."
      ).font(.footnote)
      Picker("Segment", selection: $selected) {
        Text("Choose").tag(UUID?.none)
        ForEach(house.segments) { Text($0.started.formatted()).tag(Optional($0.id)) }
      }
      Section("Shared physical references") {
        Button("Use selected session as house origin") {
          guard let sid=selected else{return}
          if model.edit(projectID:house.id,{h in if let i=h.segments.firstIndex(where:{$0.id==sid}) {h.segments[i].registration=Rigid();h.segments[i].registrationResidual=nil;h.segments[i].registrationLink=nil}}) {report="House origin assigned. This establishes coordinates, not physical accuracy."}
        }
        Picker("Registered anchor session",selection:$anchorID) {
          Text("Choose").tag(Optional<UUID>.none)
          ForEach(house.segments.filter{$0.registration != nil && $0.id != selected}) {Text($0.started.formatted()).tag(Optional($0.id))}
        }
        Button("Align using shared reference boards") {
          do {
            guard let source=house.segments.first(where:{$0.id==selected}),let anchor=house.segments.first(where:{$0.id==anchorID}) else{throw HouseError.message("Choose source and registered anchor sessions.")}
            let (transform,residual,link)=try ReferenceRegistration.fit(source:source,anchor:anchor,house:house)
            if model.edit(projectID:house.id,{h in if let i=h.segments.firstIndex(where:{$0.id==source.id}) {h.segments[i].registration=transform;h.segments[i].registrationResidual=residual;h.segments[i].registrationLink=link}}) {report="Approximate reference alignment saved. Independent board check: \(Int((residual*1000).rounded())) mm. Rebuild derived surfaces and visual maps after alignment."}
          } catch {model.error=error.localizedDescription}
        }
        Text("Three shared, fixed boards are required. Two fit; at least one checks independently. Changing an anchor or invalidating a board removes dependent registrations.").font(.footnote)
      }
      Section("Segment points: x,y,z per line") { TextEditor(text: $source).frame(height: 120) }
      Section("House points: x,y,z per line") { TextEditor(text: $target).frame(height: 120) }
      Button("Fit and check registration") {
        do {
          let a = try parse(source)
          let b = try parse(target)
          guard a.count >= 4, a.count == b.count, let sid = selected else {
            throw HouseError.message(
              "Choose a segment and supply at least four non-collinear point pairs.")
          }
          let (transform, _, worst) = try CheckedRegistration.fit(source: a, target: b)
          guard worst <= 0.025 else {
            throw HouseError.message(
              "Independent checkpoint error \((worst*1000).formatted()) mm exceeds 25 mm. Registration was not applied."
            )
          }
          model.edit {
            if let i = $0.segments.firstIndex(where: { $0.id == sid }) {
              $0.segments[i].registration = transform
              $0.segments[i].registrationLink = nil
              $0.segments[i].registrationResidual = worst
            }
          }
          report =
            "Applied approximate registration. Worst independent checkpoint: \((worst*1000).formatted()) mm. Live localization is not calibrated."
        } catch { model.error = error.localizedDescription }
      }
      Text(report).font(.footnote)
    }.navigationTitle("Register segments")
  }
  func parse(_ text: String) throws -> [V3] {
    try text.split(separator: "\n").map { line in
      let v = line.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
      guard v.count == 3, v.allSatisfy({ $0.isFinite && abs($0) < 100000 }) else {
        throw HouseError.message("Each line needs three finite coordinates: x,y,z.")
      }
      return V3(v[0], v[1], v[2])
    }
  }
}
enum PLYReader {
  static func read(_ data: Data) throws -> Mesh {
    guard data.count < 50_000_000, let text = String(data: data, encoding: .utf8) else {
      throw HouseError.message("Only bounded ASCII PLY is supported in this build.")
    }
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    guard lines.first == "ply", lines.count > 2, lines[1] == "format ascii 1.0",
      let end = lines.firstIndex(of: "end_header") else {
      throw HouseError.message("Only a complete ASCII PLY 1.0 header is supported.")
    }
    let scalarTypes: Set<String> = ["char","uchar","short","ushort","int","uint","float","double",
      "int8","uint8","int16","uint16","int32","uint32","float32","float64"]
    var count: Int?, faces: Int?, element = "", faceList = false
    var properties: [String] = []
    for line in lines[2..<end] {
      let p = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
      if p.isEmpty || p[0] == "comment" || p[0] == "obj_info" { continue }
      if p.count == 3, p[0] == "element", let n = Int(p[2]), n >= 0 {
        if p[1] == "vertex", count == nil, faces == nil { count = n; element = "vertex" }
        else if p[1] == "face", count != nil, faces == nil { faces = n; element = "face" }
        else { throw HouseError.message("Unsupported or duplicate PLY element order.") }
      } else if p.count == 3, p[0] == "property", element == "vertex",
        scalarTypes.contains(p[1]), !properties.contains(p[2]) {
        properties.append(p[2])
      } else if p.count == 5, p[0] == "property", p[1] == "list", element == "face",
        ["uchar","uint8"].contains(p[2]), ["int","int32","uint","uint32"].contains(p[3]),
        ["vertex_indices","vertex_index"].contains(p[4]), !faceList {
        faceList = true
      } else { throw HouseError.message("Unsupported or invalid PLY property declaration.") }
    }
    let faceCount = faces ?? 0
    guard let count, count > 0, count <= 200000, faceCount <= 400000,
      (faceCount == 0 || faceList), end + 1 + count + faceCount <= lines.count,
      let xi = properties.firstIndex(of: "x"), let yi = properties.firstIndex(of: "y"),
      let zi = properties.firstIndex(of: "z") else {
      throw HouseError.message("PLY counts or coordinate properties are invalid.")
    }
    var mesh = Mesh()
    for (index,line) in lines[(end + 1)..<(end + 1 + count)].enumerated() {
      if index%256==0{try Task.checkCancellation()}
      let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      // Never discard an invalid token: doing so silently shifts x/y/z fields.
      let values = tokens.compactMap { Double($0) }
      guard tokens.count == properties.count, values.count == tokens.count,
        values.allSatisfy({ $0.isFinite }) else { throw HouseError.message("Invalid PLY vertex.") }
      mesh.vertices.append(V3(values[xi], values[yi], values[zi]))
    }
    for (index,line) in lines[(end + 1 + count)..<(end + 1 + count + faceCount)].enumerated() {
      if index%256==0{try Task.checkCancellation()}
      let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
      let p = tokens.compactMap { Int32($0) }
      guard p.count == tokens.count, let n = p.first, n >= 3, n <= 64,
        p.count == Int(n) + 1, mesh.triangles.count / 3 + Int(n) - 2 <= 400000 else {
        throw HouseError.message("Invalid PLY face or triangulation budget exceeded.")
      }
      for i in 2..<Int(n) { mesh.triangles += [p[1], p[i], p[i + 1]] }
    }
    guard lines.dropFirst(end + 1 + count + faceCount).allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }), mesh.valid else {
      throw HouseError.message("PLY contains unexpected records, invalid indices or nonfinite geometry.")
    }
    return mesh
  }
}

struct ReconstructionPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  var body: some View {
    List {
      Text(
        "Fuse saved raw depth locally. Bounded 2 cm fusion uses raw poses, reference constraints or an optional local RGB-D pose graph. Session refinement uses at most 120 connected keyframes; other photographs stay outside the saved solution. Thin wires and precision remain unqualified."
      ).font(.footnote)
      ForEach(house.segments) { s in
        VStack(alignment: .leading) {
          Button("Process this capture") {model.processCapture(projectID:house.id,segmentID:s.id)}
            .buttonStyle(.borderedProminent).disabled(model.busy || model.captureInProgress)
          if let work=model.captureJobs.first(where:{$0.projectID==house.id && $0.segmentID==s.id}) {
            Text(work.label).font(.caption)
            Text(work.detail).font(.caption).foregroundStyle(.secondary)
            if work.resumable {Button("Pause queued processing"){model.pauseCaptureJob(work.id)}}
          }
          if let report=house.processingReports.first(where:{$0.segmentID==s.id}) {
            NavigationLink(report.complete ? "Processing report":"Processing report · needs attention") {CaptureProcessingReportPage(report:report)}
          }
          Button {
            guard let repo = model.repository else { return }
            let revision = house.revision
            model.perform("Fusing captured depth") {
              let feature = try await Reconstruction.fuse(house: house, segment: s, repo: repo) {
                model.progress = $0
              }
              try Task.checkCancellation()
              guard model.house?.id == house.id, model.house?.revision == revision else {
                throw HouseError.message(
                  "Project changed while processing. Candidate was not published; retry.")
              }
              model.edit {
                $0.features.removeAll { $0.segmentID == s.id && $0.resolvedGeometrySource == .depthPoints }
                $0.features.append(feature)
              }
              return nil
            }
          } label: {
            VStack(alignment: .leading) {
              Text(s.started.formatted())
              Text(
                "\(house.observations.filter{$0.segmentID==s.id && $0.depth != nil}.count) depth frames"
              ).font(.caption)
            }
          }.disabled(model.busy)
          Button("Triangulate photograph details") {
            guard let repo=model.repository else{return};let revision=house.revision
            model.perform("Matching and independently checking photograph details") {
              let result=try await LocalWorker.run {try PhotoReconstruction.build(house:house,segment:s,repo:repo)}
              guard model.house?.id==house.id,model.house?.revision==revision else{throw HouseError.message("Capture changed; photograph points were not published.")}
              model.edit {h in h.features.removeAll{$0.segmentID==s.id && $0.name==result.name};h.features.append(result)}
              return nil
            }
          }.disabled(model.busy)
          Button("Refine session camera poses") {
            guard let repo = model.repository else { return }
            let revision = house.revision
            model.perform("Matching depth features and refining camera poses") {
              let solution = try await LocalWorker.run {
                try PoseGraph.build(house: house, segment: s, repo: repo)
              }
              guard model.house?.id == house.id, model.house?.revision == revision else {
                throw HouseError.message("Capture changed; camera solution not published.")
              }
              model.edit { h in
                guard let index = h.segments.firstIndex(where: { $0.id == s.id }) else { return }
                h.segments[index].poseSolution = solution
                h.visualMaps.removeAll { $0.segmentID == s.id }
                for i in h.features.indices
                where h.features[i].segmentID == s.id && h.features[i].resolvedGeometrySource != .capturedMesh {
                  h.features[i].artifactValid = false
                  h.features[i].hidden = true
                }
              }
              return nil
            }
          }.disabled(model.busy)
          Button("Jointly refine cameras and photograph points") {
            guard let repo=model.repository else{return};let revision=house.revision
            model.perform("Joint camera and point refinement") {
              let result=try await LocalWorker.run{try BundleRefinement.build(house:house,segment:s,repo:repo)}
              guard model.house?.id==house.id,model.house?.revision==revision else{throw HouseError.message("Capture changed; joint solution was not published.")}
              model.edit {h in
                guard let index=h.segments.firstIndex(where:{$0.id==s.id}) else{return}
                h.segments[index].poseSolution=result.solution
                h.visualMaps.removeAll{$0.segmentID==s.id}
                for i in h.features.indices where h.features[i].segmentID==s.id && h.features[i].resolvedGeometrySource != .capturedMesh {h.features[i].artifactValid=false;h.features[i].hidden=true}
                h.features.removeAll{$0.segmentID==s.id && $0.name==result.feature.name}
                h.features.append(result.feature)
              };return nil
            }
          }.disabled(model.busy)
          if let solution = s.poseSolution {
            if let rms=solution.bundleCheckRMS {Text("Joint refinement: \(solution.bundlePointCount ?? 0) points, held-out image RMS \(rms.formatted(.number.precision(.fractionLength(2)))) px. Not a physical accuracy estimate.").font(.caption)}
            if let excluded=solution.excludedFrameCount,excluded>0 {Text("\(excluded) photographs remain outside the connected camera solution; their originals are preserved.").font(.caption)}
            Text(
              "Session graph: \(solution.cameras.count) camera views, \(solution.edges) matched connections. Rebuild surfaces and visual references after refinement. Residuals do not establish accuracy."
            ).font(.caption)
          }
          Button("Reconstruct triangle surface") {
            guard let repo = model.repository else { return }
            let revision = house.revision
            model.perform("Fusing triangle surfaces") {
              let surface = try await SurfaceReconstruction.build(
                house: house, segment: s, repo: repo
              ) { model.progress = $0 }
              let surfaces = try await LocalWorker.run {try MeshSemantics.transfer(surface, from: house.features)}
              try Task.checkCancellation()
              guard model.house?.id == house.id, model.house?.revision == revision else {
                throw HouseError.message("Project changed; surface candidate not published.")
              }
              model.edit { h in
                h.features.removeAll { $0.segmentID == s.id && ($0.resolvedGeometrySource == .depthFusion || $0.resolvedGeometrySource == .photoTexture) }
                for i in h.features.indices {
                  if h.features[i].segmentID == s.id
                    && (h.features[i].resolvedGeometrySource == .capturedMesh
                      || h.features[i].resolvedGeometrySource == .depthPoints)
                  {
                    h.features[i].hidden = true
                  }
                }
                h.features.append(contentsOf: surfaces)
              }
              return nil
            }
          }.disabled(model.busy)
          Button("Build photo textures") {
            guard let repo = model.repository else { return }
            let revision = house.revision
            model.perform("Projecting original photographs") {
              let features = try await LocalWorker.run {
                try TextureBuilder.build(house: house, segment: s, repo: repo)
              }
              try Task.checkCancellation()
              guard model.house?.id == house.id, model.house?.revision == revision else {
                throw HouseError.message("Project changed; texture candidate not published.")
              }
              model.edit { h in
                for i in h.features.indices {
                  if h.features[i].segmentID == s.id
                    && (h.features[i].resolvedGeometrySource == .capturedMesh
                      || h.features[i].resolvedGeometrySource == .depthFusion
                      || h.features[i].resolvedGeometrySource == .depthPoints)
                  {
                    h.features[i].hidden = true
                  }
                }
                h.features.removeAll {
                  $0.segmentID == s.id
                    && $0.resolvedGeometrySource == .photoTexture
                }
                h.features.append(contentsOf: features)
              }
              return nil
            }
          }.disabled(model.busy)
        }
      }
    }.navigationTitle("Local reconstruction")
  }
}

struct AboutPage: View {
  @State private var license = "Loading bundled license…"
  @State private var visionLicense = ""
  @State private var solverLicenses = ""
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("House Xray").font(.largeTitle.bold())
        Text(
          "Personal local construction record. Experimental; no field precision profile enabled.")
        Text(
          "IFC conversion: web-ifc 0.0.72, Mozilla Public License 2.0. Unmodified bundled JavaScript/WASM. Source: github.com/ThatOpen/engine_web-ifc"
        )
        Text(
          "SQLite is public domain. SwiftUI, ARKit, SceneKit, Metal, Vision, WebKit and AVFoundation are system frameworks. The application and fusion core are project source."
        )
        Text(
          "Native visual matching: OpenCV 4.13.0, Apache License 2.0. Built from official pinned source."
        )
        Text("Joint optimization: Ceres 2.2.0 (BSD-3-Clause) and Eigen 3.4.0 (MPL-2.0), built from pinned unmodified source.")
        Text(solverLicenses).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
        Text(visionLicense).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        Text(license).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
      }.padding()
    }.navigationTitle("About").task {
      solverLicenses=["CERES-LICENSE.txt","EIGEN-LICENSE.txt"].compactMap{name in Bundle.main.url(forResource:"IFC",withExtension:nil).flatMap{try? String(contentsOf:$0.appendingPathComponent(name),encoding:.utf8)}}.joined(separator:"\n\n")
      if let url = Bundle.main.url(forResource: "IFC", withExtension: nil)?.appendingPathComponent(
        "OPENCV-LICENSE.txt"), let text = try? String(contentsOf: url, encoding: .utf8)
      {
        visionLicense = text
      }
      if let url = Bundle.main.url(forResource: "IFC", withExtension: nil)?.appendingPathComponent(
        "LICENSE.md"), let text = try? String(contentsOf: url, encoding: .utf8)
      {
        license = text
      } else {
        license = "Bundled web-ifc license was not found; see repository THIRD_PARTY.md."
      }
    }
  }
}

struct CaptureProcessingReportPage:View {
  var report:CaptureProcessingReport
  var body:some View {
    List {
      Text("Saved photographs are unchanged. These results describe processing at the date below; later capture changes may require another run. They do not establish physical accuracy or hidden-service completeness.").font(.footnote)
      Text(report.date.formatted()).font(.caption)
      ForEach(Array(report.steps.enumerated()),id:\.offset) {_,step in
        VStack(alignment:.leading,spacing:6) {
          Label(step.name,systemImage:step.passed ? "checkmark.circle":"exclamationmark.circle").foregroundStyle(step.passed ? .mint:.orange)
          Text(step.detail).font(.footnote)
        }
      }
    }.navigationTitle("Processing report")
  }
}

