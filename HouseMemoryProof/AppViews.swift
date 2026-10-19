import PDFKit
import PhotosUI
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.035, green: 0.055, blue: 0.08)
struct RootView: View {
  @Environment(\.scenePhase) private var phase
  @EnvironmentObject var model: AppModel
  @StateObject private var guidance = HomeownerGuidance()
  @State private var tab = 0
  @State private var guidanceRoutes: [Int: UUID] = [:]
  @State private var newProject = false
  @State private var name = "My house"
  private struct TabIdentity: Hashable {
    let tab: Int
    let house: UUID
    let route: UUID?
  }
  private func identity(_ index: Int, house: House) -> TabIdentity {
    // House-local picks and navigation must not carry sample-room IDs into a
    // new project. Revisions deliberately do not reset an editor mid-save.
    TabIdentity(tab: index, house: house.id, route: guidanceRoutes[index])
  }
  var body: some View {
    Group {
      if let house = model.house {
        TabView(selection: $tab) {
          OverviewView(house: house, openExplore: { tab = 1 }, openCapture: { tab = 2 }).id(identity(0, house: house)).tabItem {
            Label("House", systemImage: "house")
          }.tag(0)
          ExploreView(house: house).id(identity(1, house: house)).tabItem { Label("Explore", systemImage: "cube.transparent") }
            .tag(1)
          CapturePage(house: house).id(identity(2, house: house)).tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            .tag(2)
          EvidencePage(house: house).id(identity(3, house: house)).tabItem { Label("Evidence", systemImage: "photo.stack") }.tag(
            3)
          ToolsPage(house: house).id(identity(4, house: house)).tabItem { Label("Tools", systemImage: "slider.horizontal.3") }
            .tag(4)
        }
      } else {
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 28) {
              Text("HOUSE XRAY").font(.caption.weight(.bold)).tracking(4).foregroundStyle(.mint)
              Image(systemName: "cube.transparent.fill").font(
                .system(size: 84, weight: .ultraLight)
              ).foregroundStyle(.mint).padding(.top, 35)
              Text("Remember what\nthe walls hide.").font(
                .system(size: 44, weight: .semibold, design: .rounded))
              Text(
                "Your construction record. On your iPhone. Save photos and notes before walls close, then find them by room and date."
              ).font(.title3).foregroundStyle(.secondary)
              HomeHelpButton()
              Button {
                newProject = true
              } label: {
                Label("Create your house", systemImage: "plus").frame(maxWidth: .infinity).padding(
                  10)
              }.buttonStyle(.borderedProminent)
              Button {
                model.create("", demo: true)
              } label: {
                Label("Explore a sample house", systemImage: "cube").frame(maxWidth: .infinity)
                  .padding(10)
              }.buttonStyle(.bordered)
              Text(
                "No account. Works offline. No subscription.\nThe sample is a practice example. 3D views and measurements remain approximate."
              ).font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
          }.background(ink)
        }
      }
    }
    .environmentObject(guidance)
    .onAppear {model.setProcessingForeground(phase == .active);guidance.checkFirstLaunch()}
    .onChange(of: phase) { _, value in
      if value == .active {model.setProcessingForeground(true);SnapshotService.automatic(model: model)}
      if value == .inactive {model.foreground=false}
      if value == .background {model.setProcessingForeground(false)}
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
      if model.busy {model.cancelOperation(reason:.waitingForResources)}
    }
    .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
      if ProcessInfo.processInfo.thermalState == .critical,model.busy {model.cancelOperation(reason:.waitingForResources)}
      else {model.resumeCaptureQueue()}
    }
    .task(id: model.selected) { SnapshotService.automatic(model: model) }
    .alert("Create a house", isPresented: $newProject) {
      TextField("House name", text: $name)
      Button("Create") { model.create(name) }
      Button("Cancel", role: .cancel) {}
    }
    .alert(
      "House Xray",
      isPresented: Binding(get: { model.error != nil && !guidance.showHelp }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .sheet(
      isPresented: Binding(get: { model.shareURL != nil && !guidance.showHelp }, set: { if !$0 { model.shareURL = nil } })
    ) { if let url = model.shareURL { ShareSheet(url: url) } }
    .fullScreenCover(isPresented: $guidance.showIntroduction) {
      HomeownerIntroduction().environmentObject(guidance)
    }
    .sheet(isPresented: $guidance.showHelp, onDismiss: {
      guidance.helpDidDismiss()
      if let destination = guidance.destination {
        guidance.destination = nil
        switch destination {
        case .house: tab = 0
        case .explore: tab = 1
        case .capture: tab = 2
        case .evidence: tab = 3
        case .tools: tab = 4
        case .createHouse: newProject = true
        }
        // A guide's next action opens the named tab at its root, even if an
        // earlier visit left a different detail page or search open there.
        if destination != .createHouse { guidanceRoutes[tab] = UUID() }
      }
    }) {
      NavigationStack {
        Group {
          if let topic = guidance.helpTopic { HomeGuidePage(id: topic) }
          else { HomeHelpCenter() }
        }
      }.environmentObject(guidance).environmentObject(model)
        .alert("House Xray", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
          Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
          if let url = model.shareURL { ShareSheet(url: url) }
        }
    }
    .overlay(alignment: .top) {
      if model.busy {
        VStack(alignment: .leading) {
          HStack { Text(model.status).font(.caption); Spacer(); Button("Cancel") { model.cancelOperation() }.font(.caption) }
          ProgressView(value: model.progress)
        }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(
          .horizontal
        ).padding(.top, 4)
      }
    }
  }
}
struct ShareSheet: UIViewControllerRepresentable {
  var url: URL
  var items:[URL] {
    let metadata=url.deletingPathExtension().appendingPathExtension("json")
    if url.pathExtension.lowercased()=="mp4",FileManager.default.fileExists(atPath:metadata.path) {return [url,metadata]}
    return [url]
  }
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
struct MetricTile: View {
  var value: String
  var label: String
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(value).font(.title2.bold()).foregroundStyle(.mint)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
      .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
  }
}
struct OverviewView: View {
  @EnvironmentObject var model: AppModel
  var house: House
  var openExplore: () -> Void
  var openCapture: () -> Void
  @State private var adding = false
  @State private var title = ""
  @State private var newRoom = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Text(house.isDemo ? "SYNTHETIC HOUSE" : "YOUR LOCAL RECORD").font(
              .caption.weight(.bold)
            ).tracking(3).foregroundStyle(.mint)
            Spacer()
            Menu {
              ForEach(model.houses) { h in Button(h.name) { model.selected = h.id } }
              Divider()
              Button("New house") { adding = true }
              Button("Add sample house") { model.create("", demo: true) }
            } label: {
              Image(systemName: "square.stack.3d.up")
            }.accessibilityLabel("Choose house")
          }
          Text(house.name).font(.system(size: 34, weight: .semibold, design: .rounded))
          HomeownerStartCard(isSample: house.isDemo)
          ScenePreview(house: house).frame(height: 260).clipShape(
            RoundedRectangle(cornerRadius: 24)
          ).overlay(alignment: .bottomLeading) {
            Text(house.isDemo ? "Sample · not your construction" : "Approximate spatial record")
              .font(.caption).padding(12).background(.black.opacity(0.6), in: Capsule()).padding()
          }
          HStack {
            MetricTile(value: "\(house.rooms.count)", label: "Spaces")
            MetricTile(value: "\(house.observations.count)", label: "Photos")
            MetricTile(value: "\(house.features.count)", label: "Objects")
          }
          HStack {
            Button(action: openExplore) {
              Label("Explore in 3D", systemImage: "figure.walk").frame(maxWidth: .infinity).padding(
                8)
            }.buttonStyle(.borderedProminent)
            Button(action: openCapture) { Image(systemName: "camera.fill").padding(8) }.buttonStyle(
              .bordered)
              .accessibilityLabel("Open capture")
          }
          Label(
            house.isDemo
              ? "This demo includes synthetic rough-in and finished layers."
              : "3D views, measurements and camera overlays are approximate. Check the original photos for context.",
            systemImage: "info.circle"
          ).font(.footnote).foregroundStyle(.secondary)
          HStack {
            Text("Spaces").font(.title2.bold())
            Spacer()
            Button {
              newRoom = true
            } label: {
              Image(systemName: "plus.circle")
            }.accessibilityLabel("Add space")
          }
          ForEach(house.rooms) { r in
            HStack {
              Image(systemName: r.level == 0 ? "door.left.hand.open" : "building.2")
                .foregroundStyle(.mint).frame(width: 30)
              VStack(alignment: .leading) {
                Text(r.name).font(.headline)
                Text(
                  "Level \(r.level) · \(house.observations.filter{$0.roomID==r.id}.count) photos"
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(house.isDemo ? "Demo" : "Not closure-verified").font(.caption2).foregroundStyle(
                .secondary)
            }.padding().background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
          }
          NavigationLink("Closure review and notes") { ClosureReview(house: house) }
          Text("Local only • Export an archive to Files for an independent backup.").font(.footnote)
            .foregroundStyle(.secondary)
        }.padding(22)
      }.background(ink).navigationBarHidden(true).alert("New house", isPresented: $adding) {
        TextField("Name", text: $title)
        Button("Create") { model.create(title) }
        Button("Cancel", role: .cancel) {}
      }
      .sheet(isPresented: $newRoom) { RoomEditor() }
    }
  }
}
struct ScenePreview: UIViewRepresentable {
  var house: House
  func makeUIView(context: Context) -> SCNView {
    let v = SCNView()
    v.backgroundColor = .clear
    v.allowsCameraControl = true
    v.autoenablesDefaultLighting = true
    return v
  }
  func updateUIView(_ v: SCNView, context: Context) {
    guard v.accessibilityIdentifier != "\(house.id)-\(house.revision)" else { return }
    v.accessibilityIdentifier = "\(house.id)-\(house.revision)"
    let s = SceneBuilder.scene(house, options: SceneOptions())
    let points = Exporter.canonicalFeatures(house, options: SceneOptions()).flatMap {
      $0.mesh.vertices
    }
    let low = V3(
      points.map { $0.x }.min() ?? 0, points.map { $0.y }.min() ?? 0, points.map { $0.z }.min() ?? 0
    )
    let high = V3(
      points.map { $0.x }.max() ?? 6, points.map { $0.y }.max() ?? 5, points.map { $0.z }.max() ?? 3
    )
    let center = (low + high) * 0.5
    let radius = max(3, (high - low).length * 0.9)
    let c = SceneBuilder.camera(at: center + V3(radius * 0.75, -radius, radius * 0.7))
    c.look(at: SCNVector3(center.render))
    s.rootNode.addChildNode(c)
    v.scene = s
    v.pointOfView = c
  }
}
struct RoomEditor: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State var name = ""
  @State var level = 0
  @State var width = 5.0
  @State var depth = 4.0
  @State var height = 2.74
  var body: some View {
    NavigationStack {
      Form {
        TextField("Room name", text: $name)
        Stepper("Level \(level)", value: $level, in: -2...4)
        Section("Design dimensions in metres — not measurements") {
          TextField("Width", value: $width, format: .number).keyboardType(.decimalPad)
          TextField("Depth", value: $depth, format: .number).keyboardType(.decimalPad)
          TextField("Height", value: $height, format: .number).keyboardType(.decimalPad)
        }
      }.navigationTitle("Add space").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            model.edit {
              $0.rooms.append(
                Room(
                  name: name.isEmpty ? "Room" : name, level: level,
                  origin: V3(0, 0, Double(level) * 3),
                  size: V3(max(0.5, width), max(0.5, depth), max(0.5, height))))
            }
            dismiss()
          }
        }
      }
    }
  }
}
struct ExploreView: View {
  @Environment(\.scenePhase) private var phase
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @AppStorage("button-walk-controls") private var buttonWalkControls=false
  @AppStorage("viewer-comfort-v1") private var savedViewerComfort=""
  @AppStorage("show-room-mini-map") private var showMiniMap=false
  @EnvironmentObject var model: AppModel
  var house: House
  @StateObject private var controller = WalkController()
  @State private var options = SceneOptions()
  @State private var layers = false
  @State private var editor = false
  @State private var selectedFeature: Feature?
  @State private var routeName = ""
  @State private var saveRoute = false
  @State private var boundarySegment:Segment?
  @State private var routeTrade: Trade = .lowVoltage
  private var viewerComfort:ViewerComfort {ViewerComfort.decode(savedViewerComfort)}
  private var viewerComfortBinding:Binding<ViewerComfort> {
    Binding(get:{viewerComfort},set:{savedViewerComfort=$0.encoded})
  }
  private var movementControls:some View {
    Group {
      if buttonWalkControls || voiceOver {StepMovementControls(controller:controller)}
      else {Joystick {controller.move=$0}.disabled(controller.orbit)}
    }
  }
  private var viewpointControls:some View {
    VStack {
      Menu {
        ForEach(house.rooms) { r in
          Button(r.name) {
            options.room = r.id
            controller.jump(r)
          }
        }
        Divider()
        ForEach(
          house.bookmarks.filter {
            $0.segmentID == SceneBuilder.activeUnregisteredSegment(house, options: options)
          }
        ) { b in Button(b.name) { controller.bookmark(b) } }
        Button("Save viewpoint") {
          do {
            let mark=try controller.makeBookmark(name:"View \(house.bookmarks.count+1)")
            model.edit {$0.bookmarks.append(mark)}
          }catch{model.error=error.localizedDescription}
        }
      } label: {
        Label("Jump", systemImage: "location")
      }.buttonStyle(.bordered)
      Toggle("Free fly", isOn: Binding(get:{controller.flying},set:{controller.setFlying($0)})).font(.caption).fixedSize().disabled(controller.orbit)
      if controller.flying {
        HStack {
          Button("↑") { controller.camera.position.y += 0.3 }.accessibilityLabel("Move up")
          Button("↓") { controller.camera.position.y -= 0.3 }.accessibilityLabel("Move down")
        }.buttonStyle(.bordered)
      }
    }.padding(10).background(ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
  }
  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        WalkSurface(controller: controller, house: house, options: options, comfort: viewerComfort).ignoresSafeArea(
          edges: .top)
        VStack(spacing: 12) {
          HStack {
            Text(house.isDemo ? "SYNTHETIC" : "APPROXIMATE").font(.caption.bold()).padding(8)
              .background(.black.opacity(0.6), in: Capsule())
          Spacer()
            if verticalSizeClass == .compact {
              Menu {
                Picker("View", selection:$options.mode) {ForEach(ViewMode.allCases){Text($0.rawValue).tag($0)}}
              } label:{Label(options.mode.rawValue,systemImage:"cube.transparent")}
                .accessibilityLabel("View mode").buttonStyle(.bordered)
              Menu {
                Picker("Tool",selection:$controller.tool) {
                  Text("Inspect").tag("Inspect");Text("Measure").tag("Measure");Text("Trace route").tag("Trace");Text("Wall").tag("Boundary")
                }
              } label:{Label(controller.tool,systemImage:"cursorarrow.rays")}
                .accessibilityLabel("Inspection tool").buttonStyle(.bordered)
            }
            Button {
              layers = true
            } label: {
              Label("Layers", systemImage: "square.3.layers.3d").foregroundStyle(.black)
            }.buttonStyle(.borderedProminent).fixedSize(horizontal:true,vertical:false)
            HomeHelpButton(topic: .explore, title: "Help with the 3D view").labelStyle(.iconOnly)
              .buttonStyle(.bordered).accessibilityIdentifier("explore-help")
          }
          if !controller.navigationNotice.isEmpty {
            Text(controller.navigationNotice).font(.caption).fixedSize(horizontal:false,vertical:true)
              .frame(maxWidth:.infinity,alignment:.leading).padding(8)
              .background(ink.opacity(0.94),in:RoundedRectangle(cornerRadius:10)).foregroundStyle(.white)
              .accessibilityIdentifier("navigation-notice")
          }
          if verticalSizeClass != .compact {HStack {
            Picker("View", selection: $options.mode) {
              ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(4).background(
              ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
          }}
          Color.clear.overlay(alignment:.topLeading) {
            if showMiniMap,controller.tool=="Inspect" {
              MiniRoomMap(house:house,options:options,controller:controller).allowsHitTesting(false)
            }
          }.clipped().allowsHitTesting(false)
          if let id = controller.selection, let f = house.features.first(where: { $0.id == id }) {
            Button {
              selectedFeature = f
              editor = true
            } label: {
              HStack {
                Circle().fill(Color(uiColor: UIColor(rgb: f.trade.hex))).frame(
                  width: 10, height: 10)
                VStack(alignment: .leading) {
                  Text(f.name).font(.headline)
                  Text("\(f.trade.rawValue) · \(f.kind.rawValue)").font(.caption)
                }
                Spacer()
                Image(systemName: "pencil")
              }.padding().background(ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            }
          }
          if controller.tool != "Inspect" {
            VStack {
              Text(
                controller.tool == "Measure"
                  ? "Tap two surface points" : controller.tool == "Boundary" ? "Tap corner, horizontal edge, then vertical edge" : "Tap points along the route"
              ).font(.caption)
              if controller.points.count == 3, controller.tool == "Boundary" {
                Button("Define wall or ceiling volume") {
                  let sid=SceneBuilder.activeUnregisteredSegment(house,options:options) ?? house.features.first(where:{$0.id==controller.selection})?.segmentID
                  boundarySegment=house.segments.first(where:{$0.id==sid})
                  if boundarySegment == nil {model.error="Select geometry from a captured session to define its reveal volume."}
                }
              }
              if controller.points.count == 2, controller.tool == "Measure" {
                Text(
                  ((controller.points[0] - controller.points[1]).length).formatted(
                    .number.precision(.fractionLength(3))) + " m · approximate"
                ).font(.headline)
                Button("Save measurement") {
                  if let r = house.rooms.first {
                    model.edit {
                      $0.dimensions.append(
                        Dimension(
                          name: "Surface distance", a: controller.points[0],
                          b: controller.points[1],
                          roomID: controller.pointRoomID ?? options.room ?? r.id,
                          sourceRevision: house.revision,
                          segmentID: SceneBuilder.activeUnregisteredSegment(house, options: options),
                          sourceGeometry:DerivedEvidence.dependencies(controller.pointFeatureIDs,house:house)
                        ))
                    }
                    controller.clear()
                  }
                }
              }
              if controller.points.count >= 2, controller.tool == "Trace" {
                Button("Save route") { saveRoute = true }
              }
              Button("Clear points") { controller.clear() }
            }.padding(10).background(ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
          }
          HStack(alignment: .bottom) {
            if viewerComfort.leftHanded {viewpointControls} else {movementControls}
            Spacer()
            if viewerComfort.leftHanded {movementControls} else {viewpointControls}
          }
          if verticalSizeClass != .compact {Picker("Tool", selection: $controller.tool) {
            Text("Inspect").tag("Inspect")
            Text("Measure").tag("Measure")
            Text("Trace route").tag("Trace")
            Text("Wall").tag("Boundary")
          }.pickerStyle(.segmented).padding(4).background(
            ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))}
        }.padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 12)
      }.background(ink).toolbar(.hidden, for: .navigationBar).onDisappear { controller.stop() }
        .onAppear {
          controller.start()
          controller.view.isPlaying = true
        }.onChange(of: phase) { _, value in
          if value == .active { controller.start() } else { controller.stop() }
        }
        .sheet(isPresented: $layers) {
          NavigationStack {
            Form {
              Section("Navigation") {
                Toggle("Step and snap-turn buttons",isOn:$buttonWalkControls)
                Toggle("Orbit overview",isOn:Binding(get:{controller.orbit},set:{controller.setOrbit($0)}))
                NavigationLink("Movement & view") {ViewerComfortSettings(settings:viewerComfortBinding)}.accessibilityIdentifier("viewer-comfort-settings")
                NavigationLink("Room map") {
                  RoomMapPage(house:house,options:options,controller:controller,showMiniMap:$showMiniMap,
                    jump:{room in options.room=room.id;controller.setOrbit(false);controller.jump(room);layers=false},
                    bookmark:{mark in controller.setOrbit(false);controller.bookmark(mark);layers=false})
                }.accessibilityIdentifier("viewer-room-map")
                Button("Reset view to this room") {controller.resetView();layers=false}.accessibilityIdentifier("viewer-reset-room")
                Text("Move 20 cm per tap and turn 15 degrees without animation. These controls are always available with VoiceOver. Walking still checks floors and obstacles.").font(.footnote)
                Text("In Orbit overview, drag to rotate and pinch to zoom. Turn it off to return to the saved view from inside the house.").font(.footnote)
              }
              Section("Construction") {
                Toggle("Show ceilings", isOn: $options.ceilings)
                Picker("Scope", selection: $options.room) {
                  Text("All spaces").tag(UUID?.none)
                  ForEach(house.rooms) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Stage", selection: $options.stage) {
                  Text("Compose stages").tag(UUID?.none)
                  ForEach(house.stages) { Text($0.name).tag(Optional($0.id)) }
                }
              }
              Section("Systems") {
                ForEach(Trade.allCases) { trade in
                  Toggle(
                    trade.rawValue,
                    isOn: Binding(
                      get: { options.trades.contains(trade) },
                      set: {
                        if $0 { options.trades.insert(trade) } else { options.trades.remove(trade) }
                      }))
                }
              }
              Text(
                "Walking needs a captured floor, a clear route and nearby recorded views. Use Free fly to inspect beyond that route. Layers change what is shown. Separate capture sessions that have not been aligned are shown one at a time. Hiding a surface does not prove that the space behind it is empty."
              ).font(.footnote)
            }.navigationTitle("Layers").toolbar { Button("Done") { layers = false } }
          }
        }
        .sheet(isPresented: $editor) { if let f = selectedFeature { FeatureEditor(feature: f) } }
        .sheet(item:$boundarySegment) { segment in BoundaryEditor(house:house,segment:segment,points:controller.points,sourceFeatureIDs:controller.pointFeatureIDs,cameraPosition:controller.canonicalPosition) }
        .sheet(isPresented: $saveRoute) {
          NavigationStack {
            Form {
              TextField("Route name", text: $routeName)
              Picker("System", selection: $routeTrade) {
                ForEach(Trade.allCases) { Text($0.rawValue).tag($0) }
              }
              Text(
                "This is a user-traced approximate route. A crossing does not establish connectivity."
              )
            }.navigationTitle("Save route").toolbar {
              Button("Save") {
                if let r = house.rooms.first, let stage = house.stages.first {
                  let pts = controller.points
                  let sources=controller.pointFeatureIDs.compactMap{id in house.features.first{$0.id==id}}
                  let dependencies=DerivedEvidence.dependencies(controller.pointFeatureIDs,house:house)
                  let f = Feature(
                    name: routeName.isEmpty ? "Traced route" : routeName, trade: routeTrade,
                    roomID: controller.pointRoomID ?? options.room ?? r.id,
                    stageID: sources.first?.stageID ?? options.stage ?? stage.id, kind: house.isDemo ? .synthetic : .observed,
                    mesh: .route(pts, radius: 0.015), route: pts,sourceIDs:Array(Set(sources.flatMap{$0.sourceIDs})),
                    segmentID: SceneBuilder.activeUnregisteredSegment(house, options: options),annotationSources:dependencies.isEmpty ? nil:dependencies)
                  model.edit { $0.features.append(f) }
                  controller.clear()
                }
                saveRoute = false
              }
            }
          }
        }
    }
  }
}
struct FeatureEditor: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State var feature: Feature
  @State private var sourcePhoto: Observation?
  @State private var original:Feature?
  @State private var projectID:UUID?
  @State private var service=ServiceDetails()
  @FocusState private var focusedServiceField:String?
  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $feature.name)
        Picker("System", selection: $feature.trade) {
          ForEach(Trade.allCases) { Text($0.rawValue).tag($0) }
        }
        TextField("Endpoint / circuit / rack port", text: $feature.endpoint)
        TextField("Notes", text: $feature.notes, axis: .vertical)
        Toggle("Reviewed by me", isOn: $feature.reviewed)
        Toggle("Hide from scene", isOn: $feature.hidden)
        ServiceDetailsFields(details:$service,focusedField:$focusedServiceField,boundaries:(model.house?.boundaries ?? []).filter{boundary in
          model.house?.segments.contains(where:{$0.id==boundary.segmentID && $0.roomID==feature.roomID && $0.stageID==feature.stageID}) ?? false
        })
        Section("Evidence") {
          Text("\(feature.kind.rawValue) · \(feature.sourceIDs.count) linked observations")
          if let envelope=feature.envelope {
            Text("Recorded \(envelope.section.rawValue.lowercased()) outer size: \((envelope.widthMetres*1000).formatted()) mm"+(envelope.heightMetres.map{" × \(($0*1000).formatted()) mm"} ?? "")).font(.caption).accessibilityIdentifier("service-envelope-size")
            Text(envelope.evidence).font(.caption).accessibilityIdentifier("service-envelope-evidence")
            Text(envelope.sourceEndInterval.map{"Recorded source intervals \(envelope.sourceInterval+1)–\($0+1) · constant diameter · mitered bends"} ?? "Recorded source interval \(envelope.sourceInterval+1)").font(.caption)
            Text(envelope.dimensionToleranceMetres.map{"Recorded size tolerance ± \(($0*1000).formatted()) mm; centerline uncertainty remains unknown."} ?? "Dimension tolerance and centerline uncertainty remain unknown.").font(.caption)
          }else if (2...128).contains(feature.route.count),[EvidenceKind.observed,.synthetic].contains(feature.kind),let house=model.house,let current=house.features.first(where:{$0.id==feature.id}) {
            NavigationLink("Record a service envelope") {ServiceEnvelopePage(source:current,projectID:house.id)}
          }
          if let coordinates=feature.importedCoordinates {Text("Imported coordinates: \(coordinates.unit.rawValue), \(coordinates.upright.rawValue). Owner-declared; placement is not independently calibrated.").font(.caption)}
          else if feature.notes.hasPrefix("Imported PLY; units declared metres") {Text("This older PLY import assumed metres. It has no recorded unit or upright-axis confirmation; verify its source before using dimensions.").font(.caption)}
          if let sources=feature.annotationSources {Text("Traced on \(sources.count) source objects. Changes to their revisions or registration make this annotation stale.").font(.caption)}
          if let object=feature.ifcObject,let source=model.house?.drawings.first(where:{$0.id==feature.sourceDrawingID}),let properties=source.ifcProperties {
            Text("IFC #\(object.expressID) · \(object.typeName) · GUID \(object.guidStatus)").font(.caption)
            NavigationLink("Inspect this source object's properties") {IFCPropertiesPage(reference:properties,initialExpressID:object.expressID)}
          }
          Text(
            "Geometry is approximate. Reviewed identity does not certify route continuity or placement."
          ).font(.footnote)
        }
        Section("Source and session photographs") {
          ForEach(
            Array(
              (model.house?.observations ?? []).filter {
                feature.sourceIDs.contains($0.id)
                  || (feature.segmentID != nil && feature.segmentID == $0.segmentID)
              }.prefix(30))
          ) { o in
            Button {
              sourcePhoto = o
            } label: {
              HStack {
                PhotoThumbnail(asset: o.image, orientation: o.imageOrientation ?? 6).frame(
                  width: 60, height: 50
                ).clipped()
                Text(o.date.formatted()).font(.caption)
              }
            }
          }
          Text("Session association alone does not prove a photograph shows this exact object.")
            .font(.caption)
        }
      }.scrollDismissesKeyboard(.immediately).sheet(item: $sourcePhoto) { PhotoDetail(observation: $0) }.navigationTitle("Object details")
        .toolbar {
          ToolbarItemGroup(placement:.keyboard) {
            if focusedServiceField != nil {Spacer();Button("Done"){focusedServiceField=nil}.accessibilityIdentifier("service-keyboard-done")}
          }
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              guard let original,let projectID else{return}
              var replacement=feature;replacement.service=service.isEmpty ? nil:service
              if model.saveFeatureEdit(replacement,expected:original,projectID:projectID){dismiss()}
            }.disabled(original==nil || projectID==nil || !service.valid)
          }
        }
    }.onAppear{if original==nil{original=feature;projectID=model.house?.id;service=feature.service ?? ServiceDetails()}}
      .interactiveDismissDisabled(original.map{feature != $0 || service != ($0.service ?? ServiceDetails())} ?? false)
  }
}
struct CapturePage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var room: UUID?
  @State private var stage: UUID?
  private struct CaptureSelection: Identifiable {
    let id = UUID()
    let room: Room
    let stage: Stage
  }
  @State private var session: CaptureSelection?
  @State private var revealSegment: Segment?
  private var selectedRoom: Room? { house.rooms.first { $0.id == room } }
  private var selectedStage: Stage? { house.stages.first { $0.id == stage } }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Capture what will be hidden", systemImage: "camera.viewfinder").font(.title2)
          Text(
            "Before walls or ceilings are covered, record the pipes, cables and framing you want to remember. Include wide views and clear close-ups. The 3D view is approximate; keep the original photos."
          )
          HomeHelpButton(topic: .capture, title: "How to record this visit")
        }
        Section("Location") {
          Picker("Room", selection: $room) {
            ForEach(house.rooms) { Text($0.name).tag(Optional($0.id)) }
          }
          Picker("Stage", selection: $stage) {
            ForEach(house.stages) { Text($0.name).tag(Optional($0.id)) }
          }
        }
        Section {
          Button("Start capture") {
            guard let selectedRoom, let selectedStage else { return }
            session = CaptureSelection(room: selectedRoom, stage: selectedStage)
          }.disabled(house.isDemo || selectedRoom == nil || selectedStage == nil)
          if house.isDemo {
            Text("Create a real house to capture. The demo remains separate from field evidence.")
              .font(.footnote)
          }
        }
        Section("Capture checklist") {
          Label("Light every cavity; avoid glare and deep shadow", systemImage: "sun.max")
          Label("Move sideways with overlapping views", systemImage: "arrow.left.and.right")
          Label("Get close details of labels and endpoints", systemImage: "text.viewfinder")
          Label("Leave stable references accessible after finishing", systemImage: "scope")
          Label("No screen can certify an unseen cavity is empty", systemImage: "eye.slash")
        }
        Section("Saved sessions · AR reveal") {
          ForEach(house.segments.reversed()) { s in
            Button {
              revealSegment = s
            } label: {
              VStack(alignment: .leading) {
                Text(house.rooms.first { $0.id == s.roomID }?.name ?? "Room")
                Text(
                  "\(s.started.formatted()) · \(s.worldMap == nil ? "photos only":"saved AR map")"
                ).font(.caption).foregroundStyle(.secondary)
              }
            }.disabled(s.worldMap == nil && s.referencePoses.isEmpty && !house.visualMaps.contains(where:{$0.roomID==s.roomID}))
            Button("Process capture") {model.processCapture(projectID:house.id,segmentID:s.id)}.disabled(model.busy || model.captureInProgress)
            if let work=model.captureJobs.first(where:{$0.projectID==house.id && $0.segmentID==s.id}) {
              Text(work.label).font(.caption).foregroundStyle(.secondary)
              if work.resumable {Button("Pause queued processing"){model.pauseCaptureJob(work.id)}}
            }
            if let report=house.processingReports.first(where:{$0.segmentID==s.id}) {
              NavigationLink(report.complete ? "Processing report":"Processing report · needs attention") {CaptureProcessingReportPage(report:report)}
            }
          }
        }
      }.navigationTitle("Capture").onAppear {
        room = room ?? house.rooms.first?.id
        stage = stage ?? house.stages.first?.id
      }
      .fullScreenCover(item: $session) { selection in
        // Present the chosen location as one value. A Boolean cover combined
        // with separately initialized picker state can present an empty view.
        CaptureSessionView(model: model, room: selection.room, stage: selection.stage, prior: nil)
      }
      .fullScreenCover(item: $revealSegment) { seg in
        if let r = house.rooms.first(where: { $0.id == seg.roomID }),
          let s = house.stages.first(where: { $0.id == seg.stageID })
        {
          CaptureSessionView(model: model, room: r, stage: s, prior: seg)
        }
      }
    }
  }
}
struct CaptureSessionView: View {
  @EnvironmentObject private var model:AppModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.scenePhase) var phase
  @StateObject var controller: CaptureController
  var room: Room
  var stage: Stage
  var prior: Segment?
  var boundaries:[RevealBoundary]
  @State private var boundaryID:UUID?
  init(model: AppModel, room: Room, stage: Stage, prior: Segment?) {
    _controller = StateObject(wrappedValue: CaptureController(model: model))
    self.room = room
    self.stage = stage
    self.prior = prior
    self.boundaries=model.house.map { h in h.boundaries.filter{$0.segmentID==prior?.id && RevealVolumes.current($0,house:h)} } ?? []
  }
  var body: some View {
    ZStack {
      CaptureSurface(controller: controller).ignoresSafeArea()
      VStack {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("\(room.name) · \(stage.name)").font(.headline)
              .accessibilityIdentifier("capture-location")
            Spacer()
            Button("Close") {
              controller.stop()
              if !controller.processing { dismiss() }
            }.disabled(controller.processing)
          }
          Text(controller.tracking).font(.caption)
        }.padding().foregroundStyle(.white)
          .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
        Spacer()
        VStack(spacing: 12) {
          Text(controller.message).font(.callout).accessibilityIdentifier("capture-instruction")
          if model.busy {
            Text(model.status).font(.caption)
            ProgressView(value:model.progress)
            Button("Pause processing") {model.cancelOperation()}
          }
          if prior != nil && !controller.running {
            Picker("Reveal volume",selection:$boundaryID) {
              Text("Choose wall or ceiling").tag(Optional<UUID>.none)
              ForEach(boundaries){Text($0.name).tag(Optional($0.id))}
            }
            if boundaries.isEmpty {Text("Define a wall or ceiling volume with the Explore tab’s Wall tool before revealing this session.").font(.caption)}
          }
          if prior == nil {
            Text("\(controller.count) photos · \(controller.coverageCells) camera positions").font(
              .caption)
            Text("These counts do not mean every surface was recorded.").font(.caption2).foregroundStyle(.white.opacity(0.8))
            if !controller.referenceGuidance.isEmpty {Text(controller.referenceGuidance).font(.caption)}
          }
          HStack {
            if controller.running {
              if prior == nil {
                Button("Detail photo") { controller.detail() }.buttonStyle(.bordered)
              }
              Button { controller.stop() } label: {Text("Save & stop").foregroundStyle(.black)}.buttonStyle(.borderedProminent)
            } else {
              Button {
                controller.start(room: room, stage: stage, prior: prior, reveal: prior != nil, boundary:boundaries.first(where:{$0.id==boundaryID}))
              } label: {Text(controller.processing ? "Saving…" : "Start").foregroundStyle(.black)}
                .buttonStyle(.borderedProminent).disabled(controller.processing || model.busy)
            }
          }
        }.padding().foregroundStyle(.white)
          .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
      }.padding()
    }.onChange(of: phase) { _, new in if new != .active { controller.stop(reason:"application-inactive") } }.onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in controller.stop(reason:"memory-warning") }.onDisappear { controller.stop(reason:"capture-screen-closed") }
  }
}
struct EvidencePage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var search = ""
  @State private var selection: Observation?
  @State private var feature: Feature?
  @State private var documentaryPhoto:DocumentaryPhoto?
  @State private var batchClassification=false
  @State private var searchIndex:EvidenceSearch.Index?
  @State private var results=EvidenceSearch.Result()
  @State private var resultLimit=200
  @State private var searching=true
  @State private var searchRequest=UUID()
  private var hasSearch: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var datasetKey:String {"\(house.id)-\(house.revision)"}
  private var searchKey:String {"\(datasetKey)-\(searchIndex?.id.uuidString ?? "none")-\(resultLimit)-\(search)"}
  var body: some View {
    NavigationStack {
      List {
        if !hasSearch { Section {
          HomeHelpButton(topic: .find, title: "Help finding and organizing records")
          NavigationLink("Import existing photographs") { DocumentaryPhotosPage(house: house) }
          NavigationLink("Locate a point from three photos") { PhotoPointPage(house:house) }
          Button("Classify objects"){batchClassification=true}.disabled(house.features.isEmpty)
        } }
        // Keep matching records above the keyboard while searching. Setup/help
        // actions and an empty-photo explanation are useful in the unfiltered view.
        if !hasSearch || searching || !results.observations.isEmpty { Section("Original photographs") {
          if house.observations.isEmpty && !hasSearch {
            Text("No captured photographs yet. Use Capture for a new visit, or Import existing photographs for photos you already have.")
              .foregroundStyle(.secondary)
          }
          if searching {ProgressView("Searching saved evidence…")}
          ForEach(results.observations) { o in
            Button {
              selection = o
            } label: {
              HStack {
                PhotoThumbnail(asset: o.image, orientation: o.imageOrientation ?? 6).frame(
                  width: 72, height: 64
                ).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                  Text(house.rooms.first { $0.id == o.roomID }?.name ?? "Capture")
                  Text(o.date.formatted()).font(.caption)
                  Text(o.documentary ? "Documentary detail" : "Posed capture · uncalibrated").font(
                    .caption2
                  ).foregroundStyle(.secondary)
                  if let issue=o.spatialProcessingIssue {Text(issue).font(.caption2).foregroundStyle(.orange)}
                }
              }
            }
          }
        } }
        if !house.documentaryPhotos.isEmpty {Section("Imported photographs") {
          ForEach(results.documentaryPhotos) { p in
            Button {documentaryPhoto=p} label:{
              HStack {
                PhotoThumbnail(asset:p.image,orientation:1).frame(width:72,height:64).clipped().clipShape(RoundedRectangle(cornerRadius:8))
                VStack(alignment:.leading) {
                  Text(p.note.isEmpty ? "Unposed photograph":p.note).lineLimit(2)
                  Text(p.date.formatted()).font(.caption)
                  Text("Documentary original · no spatial calibration").font(.caption2).foregroundStyle(.secondary)
                }
              }
            }
          }
        }}
        Section("Systems and objects") {
          ForEach(results.features) { f in
            Button {
              feature = f
            } label: {
              HStack {
                Circle().fill(Color(uiColor: UIColor(rgb: f.trade.hex))).frame(width: 8, height: 8)
                VStack(alignment: .leading) {
                  Text(f.name)
                  Text(f.endpoint.isEmpty ? f.trade.rawValue : f.endpoint).font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if f.reviewed { Image(systemName: "checkmark.circle") }
              }
            }
          }
        }
        if !searching {
          Text("\(results.photographCount) \(results.photographCount==1 ? "photograph":"photographs") · \(results.featureCount) \(results.featureCount==1 ? "object":"objects")").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("evidence-result-count")
          if results.observations.count<results.observationCount || results.features.count<results.featureCount || results.documentaryPhotos.count<results.documentaryCount {
            Button("Show more results") {resultLimit=min(50000,resultLimit+200)}
          }
        }
      }.navigationTitle("Evidence").searchable(text: $search, prompt: "Room, stage, system, port, notes")
        .onChange(of:search){_,_ in resultLimit=200}
        .task(id:datasetKey) {
          let snapshot=house
          do {
            let prepared=try await LocalWorker.run{try EvidenceSearch.Index(house:snapshot)}
            guard !Task.isCancelled else{return}
            searchIndex=prepared
          }catch is CancellationError{}catch{model.error=error.localizedDescription}
        }
        .task(id:searchKey) {
          let request=UUID();searchRequest=request;searching=true
          guard let index=searchIndex,index.houseID==house.id,index.revision==house.revision else{results=EvidenceSearch.Result();return}
          let query=search,limit=resultLimit
          do {
            let found=try await LocalWorker.run{try index.find(query,limit:limit)}
            guard !Task.isCancelled,request==searchRequest else{return}
            results=found;searching=false
          }catch is CancellationError{}catch{
            if request==searchRequest {searching=false;model.error=error.localizedDescription}
          }
        }
        .sheet(item: $selection) { PhotoDetail(observation: $0) }.sheet(item: $feature) {
          FeatureEditor(feature: $0)
        }
        .sheet(item:$documentaryPhoto){DocumentaryPhotoDetail(photo:$0)}
        .sheet(isPresented:$batchClassification){BatchServiceEditor(house:house)}
    }
  }
}
struct PhotoThumbnail: View {
  @EnvironmentObject var model: AppModel
  var asset: String
  var orientation: Int = 6
  @State private var image: UIImage?
  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "photo").foregroundStyle(.secondary)
      }
    }.task(id: asset) {
      if let url = try? model.repository?.assetURL(asset) {
        let orientation = orientation
        image = await Task.detached(priority: .utility) {
          EvidenceImageCache.shared.thumbnail(url: url, orientation: orientation)
        }.value
      }
    }
  }

}
struct PhotoDetail: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State var observation: Observation
  @State private var image: UIImage?
  @State private var reading = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let image {
            ZoomableEvidence(image: image).frame(height: 420)
            Text("Pinch to zoom · original file preserved").font(.caption)
          }
          Text(observation.date.formatted()).font(.caption)
          TextField(
            "Notes, observed labels, circuit or endpoint", text: $observation.note, axis: .vertical
          ).textFieldStyle(.roundedBorder)
          Button(reading ? "Reading…" : "Read labels on device") {
            guard let cg = image?.cgImage else { return }
            reading = true
            Task {
              defer { reading = false }
              do {
                let text = try await TextRecognition.read(
                  cg,
                  orientation: CGImagePropertyOrientation(
                    rawValue: UInt32(observation.imageOrientation ?? 6)) ?? .right)
                observation.note += (observation.note.isEmpty ? "" : "\n") + text
              } catch { model.error = error.localizedDescription }
            }
          }.disabled(reading)
          Text(
            "OCR is a suggestion. Confirm cable identity and continuity yourself. Raw depth is preserved when available; its confidence is not an accuracy bound."
          ).font(.footnote).foregroundStyle(.secondary)
        }.padding()
      }.navigationTitle("Original evidence").toolbar {
        Button("Save") {
          model.edit {
            if let i = $0.observations.firstIndex(where: { $0.id == observation.id }) {
              $0.observations[i] = observation
            }
          }
          dismiss()
        }
      }.task {
        if let url = try? model.repository?.assetURL(observation.image),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 4096,
            ] as CFDictionary)
        {
          image = UIImage(
            cgImage: cg, scale: 1,
            orientation: PhotoOrientation.ui(observation.imageOrientation ?? 6))
        }
      }
    }
  }
}
struct ClosureReview: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var notes = ""
  @State private var savedNotes = ""
  @State private var initializedProject:UUID?
  @State private var roomID:UUID?
  @State private var stageID:UUID?
  @State private var inventory:ClosureInventory?
  var body: some View {
    Form {
      Section("Before walls close") {
        Text("No automatic closure certificate. Review the dates, unresolved gaps and changes since capture. An acknowledged obstruction remains blocked.")
        Picker("Room",selection:$roomID){Text("Choose").tag(Optional<UUID>.none);ForEach(house.rooms){Text($0.name+" · level "+String($0.level)).tag(Optional($0.id))}}
        Picker("Construction stage",selection:$stageID){Text("All stages").tag(Optional<UUID>.none);ForEach(house.stages){Text($0.name).tag(Optional($0.id))}}
        Button("Review dated evidence") {
          guard let roomID else{return};let snapshot=house,selectedStage=stageID
          model.perform("Reviewing saved evidence") {
            let result=try await LocalWorker.run{try ClosureInventory.build(house:snapshot,roomID:roomID,stageID:selectedStage)}
            guard model.house?.id==snapshot.id,model.house?.revision==snapshot.revision,self.roomID==roomID,self.stageID==selectedStage else{throw HouseError.message("The review selection or project changed. Review the evidence again.")}
            inventory=result;return nil
          }
        }.disabled(roomID==nil || model.busy)
        NavigationLink("Check wall and ceiling gaps"){CoveragePage(house:house)}
      }
      if let inventory {
        Section("Source assignment") {
          Text("\(inventory.documentaryPhotosWithoutStage) room photos have no stage · \(inventory.houseDocumentaryPhotosWithoutRoom) house photos have no room")
          if inventory.syntheticProject {Text("Demonstration evidence; this is not a construction review.")}
          Button("Export dated review inventory") {
            do {
              let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
              let file=Exporter.destination("House-Xray-closure-inventory.json")
              try DurableFiles.write(encoder.encode(inventory),to:file);model.shareURL=file
            }catch{model.error=error.localizedDescription}
          }
        }.font(.footnote)
        ForEach(inventory.stages){stage in
          Section(stage.name+" · "+stage.phase) {
            Text("Declared stage date: \(stage.declaredDate.formatted(date:.abbreviated,time:.omitted)) · \(stage.kind)")
            if let first=stage.firstPhotoDate,let last=stage.lastPhotoDate {
              Text("Photographs: \(first.formatted(date:.abbreviated,time:.shortened)) to \(last.formatted(date:.abbreviated,time:.shortened))")
            }else{Text("No photographs assigned to this room and stage.").foregroundStyle(.orange)}
            Text("\(stage.posedPhotos) capture photos · \(stage.documentaryPhotos) documentary photos · \(stage.poseIneligiblePhotos) capture photos excluded from spatial use")
            Text("\(stage.sessions) sessions · \(stage.interruptedSessions) interrupted · \(stage.unregisteredSessions) not registered to the house")
            Text("Observed objects: \(stage.reviewedCurrentObservedFeatures) current and reviewed · \(stage.unreviewedCurrentObservedFeatures) current and unreviewed · \(stage.staleObservedFeatures) stale")
            Text("\(stage.plannedFeatures) design objects · \(stage.syntheticFeatures) synthetic objects · \(stage.boundaryCount) saved boundaries")
            Text("\(stage.unconfirmedConnections) endpoint links await confirmation")
            Text("New work after the latest photographs needs another visit. These counts do not establish coverage or confirm hidden contents.")
          }.font(.footnote)
        }
      }
      Section("Gaps, blocked areas and late changes") {
        TextEditor(text: $notes).frame(minHeight: 180)
        Button("Save review notes") {
          guard model.house?.id==house.id,model.house?.closureNotes==savedNotes else{model.error="Review notes changed elsewhere. Reopen this page before saving.";return}
          if model.edit(projectID:house.id,{$0.closureNotes=notes}) {savedNotes=notes}
        }
      }
    }.navigationTitle("Closure review").onAppear {if initializedProject != house.id {initializedProject=house.id;notes=house.closureNotes;savedNotes=house.closureNotes;roomID=house.rooms.first?.id}}
      .onChange(of:house.id){_,_ in inventory=nil;initializedProject=house.id;notes=house.closureNotes;savedNotes=house.closureNotes;roomID=house.rooms.first?.id;stageID=nil}
      .onChange(of:house.revision){_,_ in inventory=nil}
      .onChange(of:roomID){_,_ in inventory=nil}
      .onChange(of:stageID){_,_ in inventory=nil}
  }
}
