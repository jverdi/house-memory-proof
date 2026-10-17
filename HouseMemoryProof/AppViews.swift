import PDFKit
import PhotosUI
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.035, green: 0.055, blue: 0.08)
struct RootView: View {
  @Environment(\.scenePhase) private var phase
  @EnvironmentObject var model: AppModel
  @State private var tab = 0
  @State private var newProject = false
  @State private var name = "My house"
  var body: some View {
    Group {
      if let house = model.house {
        TabView(selection: $tab) {
          OverviewView(house: house, openExplore: { tab = 1 }, openCapture: { tab = 2 }).tabItem {
            Label("House", systemImage: "house")
          }.tag(0)
          ExploreView(house: house).tabItem { Label("Explore", systemImage: "cube.transparent") }
            .tag(1)
          CapturePage(house: house).tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            .tag(2)
          EvidencePage(house: house).tabItem { Label("Evidence", systemImage: "photo.stack") }.tag(
            3)
          ToolsPage(house: house).tabItem { Label("Tools", systemImage: "slider.horizontal.3") }
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
                "Your construction record. On your iPhone. Capture exposed services, explore their geometry, and keep the original evidence."
              ).font(.title3).foregroundStyle(.secondary)
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
                "No account. No server. No subscription.\nThe sample is synthetic; real captures remain approximate until validated."
              ).font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
          }.background(ink)
        }
      }
    }
    .onChange(of: phase) { _, value in
      if value == .active { SnapshotService.automatic(model: model) }
    }
    .task(id: model.selected) { SnapshotService.automatic(model: model) }
    .alert("Create a house", isPresented: $newProject) {
      TextField("House name", text: $name)
      Button("Create") { model.create(name) }
      Button("Cancel", role: .cancel) {}
    }
    .alert(
      "House Xray",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .sheet(
      isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })
    ) { if let url = model.shareURL { ShareSheet(url: url) } }
    .overlay(alignment: .top) {
      if model.busy {
        VStack(alignment: .leading) {
          Text(model.status).font(.caption)
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
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
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
            }
          }
          Text(house.name).font(.system(size: 34, weight: .semibold, design: .rounded))
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
          }
          Label(
            house.isDemo
              ? "This demo includes synthetic rough-in and finished layers."
              : "No precision profile. Measurements and AR overlays are approximate.",
            systemImage: "info.circle"
          ).font(.footnote).foregroundStyle(.secondary)
          HStack {
            Text("Spaces").font(.title2.bold())
            Spacer()
            Button {
              newRoom = true
            } label: {
              Image(systemName: "plus.circle")
            }
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
  @EnvironmentObject var model: AppModel
  var house: House
  @StateObject private var controller = WalkController()
  @State private var options = SceneOptions()
  @State private var layers = false
  @State private var editor = false
  @State private var selectedFeature: Feature?
  @State private var routeName = ""
  @State private var saveRoute = false
  @State private var routeTrade: Trade = .lowVoltage
  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        WalkSurface(controller: controller, house: house, options: options).ignoresSafeArea(
          edges: .top)
        VStack(spacing: 12) {
          HStack {
            Text(house.isDemo ? "SYNTHETIC" : "APPROXIMATE").font(.caption.bold()).padding(8)
              .background(.black.opacity(0.6), in: Capsule())
            Spacer()
            Button {
              layers = true
            } label: {
              Label("Layers", systemImage: "square.3.layers.3d")
            }.buttonStyle(.borderedProminent)
          }
          HStack {
            Picker("View", selection: $options.mode) {
              ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(4).background(
              ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
          }
          Spacer()
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
                  ? "Tap two surface points" : "Tap points along the route"
              ).font(.caption)
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
                          segmentID: SceneBuilder.activeUnregisteredSegment(house, options: options)
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
            Joystick { controller.move = $0 }
            Spacer()
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
                  if let r = house.rooms.first {
                    model.edit {
                      $0.bookmarks.append(
                        Bookmark(
                          name: "View \($0.bookmarks.count+1)",
                          position: V3(ar: controller.camera.simdPosition),
                          yaw: Double(controller.yaw), pitch: Double(controller.pitch),
                          roomID: options.room ?? r.id,
                          segmentID: SceneBuilder.activeUnregisteredSegment(house, options: options)
                        ))
                    }
                  }
                }
              } label: {
                Label("Jump", systemImage: "location")
              }.buttonStyle(.bordered)
              Toggle("Free fly", isOn: $controller.flying).font(.caption).fixedSize()
              if controller.flying {
                HStack {
                  Button("↑") { controller.camera.position.y += 0.3 }
                  Button("↓") { controller.camera.position.y -= 0.3 }
                }.buttonStyle(.bordered)
              }
            }.padding(10).background(ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
          }
          Picker("Tool", selection: $controller.tool) {
            Text("Inspect").tag("Inspect")
            Text("Measure").tag("Measure")
            Text("Trace route").tag("Trace")
          }.pickerStyle(.segmented).padding(4).background(
            ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
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
                "Walk mode stays near recorded camera positions in real captures; use Free fly to inspect beyond that path. Layer switches preserve coordinates. Unregistered capture segments are not merged; one unregistered segment is shown at a time. Hidden geometry does not prove an empty cavity."
              ).font(.footnote)
            }.navigationTitle("Layers").toolbar { Button("Done") { layers = false } }
          }
        }
        .sheet(isPresented: $editor) { if let f = selectedFeature { FeatureEditor(feature: f) } }
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
                  let f = Feature(
                    name: routeName.isEmpty ? "Traced route" : routeName, trade: routeTrade,
                    roomID: controller.pointRoomID ?? options.room ?? r.id,
                    stageID: options.stage ?? stage.id, kind: house.isDemo ? .synthetic : .observed,
                    mesh: .route(pts, radius: 0.015), route: pts,
                    segmentID: SceneBuilder.activeUnregisteredSegment(house, options: options))
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
        Section("Evidence") {
          Text("\(feature.kind.rawValue) · \(feature.sourceIDs.count) linked observations")
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
      }.sheet(item: $sourcePhoto) { PhotoDetail(observation: $0) }.navigationTitle("Object details")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              feature.revision += 1
              model.edit {
                if let i = $0.features.firstIndex(where: { $0.id == feature.id }) {
                  $0.features[i] = feature
                }
              }
              dismiss()
            }
          }
        }
    }
  }
}
struct CapturePage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var room: UUID?
  @State private var stage: UUID?
  @State private var session = false
  @State private var revealSegment: Segment?
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Capture what will be hidden", systemImage: "camera.viewfinder").font(.title2)
          Text(
            "Capture each wall side, joist bay, ceiling and late change before closing it. ARKit geometry is approximate; original images remain the primary evidence."
          )
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
          Button("Start capture") { session = true }.disabled(house.isDemo)
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
            }.disabled(s.worldMap == nil && s.referencePoses.isEmpty)
          }
        }
      }.navigationTitle("Capture").onAppear {
        room = room ?? house.rooms.first?.id
        stage = stage ?? house.stages.first?.id
      }
      .fullScreenCover(isPresented: $session) {
        if let r = house.rooms.first(where: { $0.id == room }),
          let s = house.stages.first(where: { $0.id == stage })
        {
          CaptureSessionView(model: model, room: r, stage: s, prior: nil)
        }
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
  @Environment(\.dismiss) var dismiss
  @Environment(\.scenePhase) var phase
  @StateObject var controller: CaptureController
  var room: Room
  var stage: Stage
  var prior: Segment?
  init(model: AppModel, room: Room, stage: Stage, prior: Segment?) {
    _controller = StateObject(wrappedValue: CaptureController(model: model))
    self.room = room
    self.stage = stage
    self.prior = prior
  }
  var body: some View {
    ZStack {
      CaptureSurface(controller: controller).ignoresSafeArea()
      VStack {
        HStack {
          Text("\(room.name) · \(stage.name)").font(.headline)
          Spacer()
          Button("Close") {
            controller.stop()
            if !controller.processing { dismiss() }
          }.disabled(controller.processing)
        }
        Text(controller.tracking).font(.caption)
        Spacer()
        VStack(spacing: 12) {
          Text(controller.message).font(.callout)
          if prior == nil {
            Text("\(controller.count) photos · \(controller.coverageCells) camera positions").font(
              .caption)
            Text("Position count is not surface completeness.").font(.caption2).foregroundStyle(
              .secondary)
          }
          HStack {
            if controller.running {
              if prior == nil {
                Button("Detail photo") { controller.detail() }.buttonStyle(.bordered)
              }
              Button("Save & stop") { controller.stop() }.buttonStyle(.borderedProminent)
            } else {
              Button(controller.processing ? "Saving…" : "Start") {
                controller.start(room: room, stage: stage, prior: prior, reveal: prior != nil)
              }.buttonStyle(.borderedProminent).disabled(controller.processing)
            }
          }
        }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
      }.padding()
    }.onChange(of: phase) { _, new in if new != .active { controller.stop() } }.onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    ) { _ in controller.stop() }.onDisappear { controller.stop() }
  }
}
struct EvidencePage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var search = ""
  @State private var selection: Observation?
  @State private var feature: Feature?
  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink("Import existing photographs") { DocumentaryPhotosPage(house: house) }
        }
        Section("Original photographs") {
          if house.observations.isEmpty {
            Text("No captured photographs yet. Sample geometry is not photographic evidence.")
              .foregroundStyle(.secondary)
          }
          ForEach(
            house.observations.reversed().filter {
              search.isEmpty || $0.note.localizedCaseInsensitiveContains(search)
            }
          ) { o in
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
                }
              }
            }
          }
        }
        Section("Systems and objects") {
          ForEach(
            house.features.filter {
              search.isEmpty
                || ($0.name + " " + $0.notes + " " + $0.endpoint + " " + $0.trade.rawValue)
                  .localizedCaseInsensitiveContains(search)
            }.prefix(150)
          ) { f in
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
      }.navigationTitle("Evidence").searchable(text: $search, prompt: "Room, system, port, notes")
        .sheet(item: $selection) { PhotoDetail(observation: $0) }.sheet(item: $feature) {
          FeatureEditor(feature: $0)
        }
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
  var body: some View {
    Form {
      Section("Before walls close") {
        Text(
          "No automatic closure certificate. Camera positions and mesh coverage do not verify the contents of an occluded cavity."
        )
        ForEach(house.rooms) { r in
          VStack(alignment: .leading) {
            Text(r.name).font(.headline)
            Text(
              "\(house.observations.filter{$0.roomID==r.id}.count) photographs · \(house.segments.filter{$0.roomID==r.id}.count) sessions"
            ).font(.caption)
          }
        }
      }
      Section("Gaps, blocked areas and late changes") {
        TextEditor(text: $notes).frame(minHeight: 180)
        Button("Save review notes") { model.edit { $0.closureNotes = notes } }
      }
    }.navigationTitle("Closure review").onAppear { notes = house.closureNotes }
  }
}
