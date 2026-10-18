import SwiftUI

enum HomeownerGoal: String, CaseIterable, Identifiable {
  case beforeWalls, progress, findLater
  var id: String { rawValue }
  var title: String {
    switch self {
    case .beforeWalls: return "Record what walls will hide"
    case .progress: return "Document a construction visit"
    case .findLater: return "Find an earlier record"
    }
  }
  var detail: String {
    switch self {
    case .beforeWalls: return "Save pipes, wires and other details before they are covered."
    case .progress: return "Keep changes, photos and notes organized by room and date."
    case .findLater: return "Look up original photos and explore what was recorded."
    }
  }
  var symbol: String {
    switch self { case .beforeWalls: return "camera.viewfinder"; case .progress: return "calendar"; case .findLater: return "magnifyingglass" }
  }
  var guide: HomeGuideID {
    switch self { case .beforeWalls: return .capture; case .progress: return .visits; case .findLater: return .find }
  }
}

enum GuidanceDestination: Equatable { case house, capture, evidence, explore, tools, createHouse }

/// Preferences are separate from house records. Replaying guidance never edits a project.
@MainActor final class HomeownerGuidance: ObservableObject {
  private static let completedKey = "homeowner-introduction-version"
  private static let nextKey = "homeowner-introduction-next-launch"
  private static let goalKey = "homeowner-goal"
  private static let version = 1
  @Published var showIntroduction = false
  @Published var showHelp = false
  @Published var helpTopic: HomeGuideID?
  @Published var destination: GuidanceDestination?
  @Published var goal: HomeownerGoal {
    didSet { UserDefaults.standard.set(goal.rawValue, forKey: Self.goalKey) }
  }
  @Published var showNextLaunch: Bool {
    didSet { UserDefaults.standard.set(showNextLaunch, forKey: Self.nextKey) }
  }
  private var checkedLaunch = false
  private var restartAfterHelp = false

  init() {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--guidance-reset") {
      for key in [Self.completedKey, Self.nextKey, Self.goalKey] { UserDefaults.standard.removeObject(forKey: key) }
    }
    #endif
    goal = HomeownerGoal(rawValue: UserDefaults.standard.string(forKey: Self.goalKey) ?? "") ?? .beforeWalls
    showNextLaunch = UserDefaults.standard.bool(forKey: Self.nextKey)
  }
  func checkFirstLaunch() {
    guard !checkedLaunch else { return }
    checkedLaunch = true
    #if DEBUG
    let args = ProcessInfo.processInfo.arguments
    // Existing fixture/command runs keep their established entry points. Dedicated
    // homeowner UI cases exercise the real first-launch gate, including relaunch.
    let fixture = args.contains { $0.contains("demo") || $0.contains("self-test") || $0.contains("developer-command") || $0.contains("-fault") || $0.contains("recovery-check") }
    if fixture && !args.contains("--guidance-ui") { return }
    #endif
    showIntroduction = showNextLaunch || UserDefaults.standard.integer(forKey: Self.completedKey) < Self.version
  }
  func finishIntroduction() {
    UserDefaults.standard.set(Self.version, forKey: Self.completedKey)
    showNextLaunch = false
    showIntroduction = false
  }
  func openHelp(_ topic: HomeGuideID? = nil) { helpTopic = topic; showHelp = true }
  func restartIntroduction() {
    if showHelp { restartAfterHelp = true; showHelp = false }
    else { showIntroduction = true }
  }
  func helpDidDismiss() {
    if restartAfterHelp { restartAfterHelp = false; showIntroduction = true }
  }
  func open(_ target: GuidanceDestination) { destination = target; showHelp = false }
}

struct HomeownerIntroduction: View {
  @EnvironmentObject private var guidance: HomeownerGuidance
  @State private var page = 0
  private let titles = ["A useful record starts with one room", "Choose a room and a date", "Save what you can see", "Check it before the walls close", "Find it again and keep a copy"]
  private let symbols = ["house", "calendar", "camera.viewfinder", "checklist", "photo.on.rectangle"]
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            Text("Step \(page + 1) of \(titles.count)").font(.subheadline).foregroundStyle(.secondary).id("intro-top")
              .accessibilityIdentifier("introduction-progress")
            Image(systemName: symbols[page]).font(.largeTitle).foregroundStyle(.mint).accessibilityHidden(true)
            Text(titles[page]).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("introduction-heading")
            pageContent
            if page == 4 {
              Button("Get started") { guidance.finishIntroduction() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("introduction-finish")
              Text("Your starting guide will be on the House tab. You can always open Help & getting started, or restart this introduction in Help settings.")
                .foregroundStyle(.secondary)
            } else {
              Button("Continue") { page = min(titles.count - 1, page + 1); proxy.scrollTo("intro-top", anchor: .top) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("introduction-next")
            }
            if page > 0 {
              Button("Back") { page = max(0, page - 1); proxy.scrollTo("intro-top", anchor: .top) }
                .buttonStyle(.bordered).accessibilityIdentifier("introduction-back")
            }
          }.frame(maxWidth: 620, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
      }.navigationTitle("Welcome to House Xray").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
          Button("Skip for now") { guidance.finishIntroduction() }.accessibilityIdentifier("introduction-skip")
        } }
    }.controlSize(.large).interactiveDismissDisabled().onAppear { page = 0 }
  }
  @ViewBuilder private var pageContent: some View {
    switch page {
    case 0:
      Text("House Xray keeps photos and notes from your construction project, with a 3D view when the capture supports it. Start with a small area you want to remember.")
      Text("What would you like to do first?").font(.headline)
      ForEach(HomeownerGoal.allCases) { goal in
        Button { guidance.goal = goal } label: {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: guidance.goal == goal ? "checkmark.circle.fill" : "circle").foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 5) { Text(goal.title).font(.headline); Text(goal.detail).font(.body).foregroundStyle(.secondary) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }.buttonStyle(.plain).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
          .accessibilityIdentifier("introduction-goal-" + goal.rawValue)
          .accessibilityValue(guidance.goal == goal ? "Selected" : "Not selected")
      }
      Text("No account is needed. Your record stays on this iPhone until you choose to export it or save a folder backup.").foregroundStyle(.secondary)
      Text("You can skip now and reopen this introduction from Help & getting started → Help settings.").font(.footnote).foregroundStyle(.secondary)
    case 1:
      instruction("Create your house", "Use Create your house on the welcome screen. The sample house is only a practice example; it is not your construction record.")
      instruction("Name the space", "On House, tap + beside Spaces (Add space). Use a name you will recognize, such as Upstairs bathroom. Level 0 is the main level; use 1 for the next floor.")
      instruction("Keep each visit separate", "In Tools → Construction stages, add a stage with the date and a name such as Kitchen wiring before drywall. Rough-in means work that is still exposed; Finished means the surfaces have been covered.")
      Text("Room size entries are design estimates. Entering them does not measure your room or prove where a pipe is.").foregroundStyle(.secondary)
    case 2:
      instruction("Choose Capture", "Select the Room and Stage, tap Start capture, then Start on the camera screen. Camera permission is requested when you use the camera.")
      instruction("Move slowly around one area", "Take overlapping views of each wall, ceiling and visible service. Use Detail photo for labels and connections. Tap Save & stop, wait for saving to finish, then Close.")
      instruction("Already have photos?", "Open Evidence → Import existing photographs → Choose photographs. Add a room, stage and helpful notes to each photo, then Save. This is useful even without a 3D scan.")
    case 3:
      instruction("Look at the originals", "Open Evidence and check that your photos show the details you care about. Add notes such as Hot water pipe beside window, rather than guessing an unknown connection.")
      instruction("Make a list of missing views", "On House, open Closure review and notes, choose the room and tap Review dated evidence. Record gaps and questions for your builder, and take another visit before those details are hidden.")
      Text("The app records what was visible. It cannot see through walls or confirm that an unseen cavity is empty. The current 3D views and measurements are approximate; they do not establish a safe place to drill.").foregroundStyle(.secondary)
    default:
      instruction("Find the record", "Search Evidence by room or notes. In Explore, use Layers to choose the room, construction stage and systems you want to see. Original photos remain useful when a 3D view or camera overlay is unavailable.")
      instruction("Save a separate backup", "In Tools, tap Export complete house archive and save the file in Files. A movie or 3D export is for viewing and sharing; the complete archive keeps the house record and originals together.")
      instruction("Your next step", guidance.goal == .findLater ? "Open the starting guide to find a photo, understand layers, or restore an archive you already have." : "Create a real house, then follow the starting guide for one room. You can change your starting goal in Help settings at any time.")
    }
  }
  private func instruction(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline).accessibilityAddTraits(.isHeader); Text(body) }
  }
}

struct HomeHelpButton: View {
  @EnvironmentObject private var guidance: HomeownerGuidance
  var topic: HomeGuideID? = nil
  var title = "Help & getting started"
  var body: some View {
    Button { guidance.openHelp(topic) } label: {
      Label(title, systemImage: "questionmark.circle").frame(minHeight: 44, alignment: .leading)
    }
  }
}

struct HomeHelpToolbar: ToolbarContent {
  @EnvironmentObject private var guidance: HomeownerGuidance
  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("Done") { guidance.showHelp = false }.accessibilityIdentifier("help-close")
    }
  }
}

struct HomeownerStartCard: View {
  @EnvironmentObject private var guidance: HomeownerGuidance
  var isSample: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(isSample ? "Practice here. Record your own house next." : "Start here").font(.headline)
      Text(isSample ? "This sample shows how records can look. Choose New house from the house selector before recording your construction." : guidance.goal.detail)
        .foregroundStyle(.secondary)
      Button { guidance.openHelp(isSample ? .setup : guidance.goal.guide) } label: {
        Label(isSample ? "Set up my house" : guidance.goal.title, systemImage: guidance.goal.symbol)
      }.accessibilityIdentifier("homeowner-start-guide")
      HomeHelpButton()
    }.padding().frame(maxWidth: .infinity, alignment: .leading)
      .background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
  }
}

struct HomeHelpCenter: View {
  @EnvironmentObject private var guidance: HomeownerGuidance
  @State private var search = ""
  private var results: [HomeGuide] { HomeGuide.all.filter { $0.matches(search) } }
  var body: some View {
    List {
      if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Section {
          Text("A guide for each step of your construction project. These guides are included in the app and work without an internet connection.")
          NavigationLink { HomeGuidePage(id: guidance.goal.guide) } label: { Label("Start: " + guidance.goal.title, systemImage: guidance.goal.symbol) }
          NavigationLink("Help settings") { HomeHelpSettings() }.accessibilityIdentifier("help-settings")
        }
      }
      ForEach(HomeGuideCategory.allCases, id: \.self) { category in
        let guides = results.filter { $0.category == category }
        if !guides.isEmpty {
          Section(category.rawValue) {
            ForEach(guides) { guide in
              NavigationLink { HomeGuidePage(id: guide.id) } label: {
                VStack(alignment: .leading, spacing: 4) { Text(guide.title); Text(guide.summary).font(.subheadline).foregroundStyle(.secondary) }
              }.accessibilityIdentifier("help-guide-" + guide.id.rawValue)
            }
          }
        }
      }
      if results.isEmpty {
        Section {
          Text("No guide found").font(.headline)
          Text("Try a room, a task such as backup, or a word such as pipe, photo or drywall.")
          Button("Show all guides") { search = "" }
        }
      }
    }.navigationTitle("Help & getting started").navigationBarTitleDisplayMode(.inline)
      .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tasks or unfamiliar words")
      .toolbar { HomeHelpToolbar() }
  }
}

struct HomeHelpSettings: View {
  @EnvironmentObject private var guidance: HomeownerGuidance
  var body: some View {
    Form {
      Section("Introduction") {
        Button("Restart introduction") { guidance.restartIntroduction() }.accessibilityIdentifier("restart-introduction")
        Toggle("Show introduction next time", isOn: $guidance.showNextLaunch).accessibilityIdentifier("introduction-next-launch")
        Text("Next time means the next time you launch the app after closing it. Restarting guidance does not change your houses, photographs, notes or backups.")
      }
      Section("My starting goal") {
        Picker("Starting goal", selection: $guidance.goal) { ForEach(HomeownerGoal.allCases) { Text($0.title).tag($0) } }
        Text("This chooses the starting guide on House. Every guide and app feature remains available.")
      }
    }.navigationTitle("Help settings").navigationBarTitleDisplayMode(.inline).toolbar { HomeHelpToolbar() }
  }
}

struct HomeGuidePage: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var guidance: HomeownerGuidance
  var id: HomeGuideID
  private var guide: HomeGuide { HomeGuide.all.first { $0.id == id }! }
  var body: some View {
    List {
      Section {
        NavigationLink("All help guides") { HomeHelpCenter() }.accessibilityIdentifier("all-help-guides")
        Text(guide.summary).font(.title3)
        Text(guide.outcome).foregroundStyle(.secondary)
      }
      ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
        Section("\(index + 1). \(step.title)") { Text(step.body).textSelection(.enabled) }
      }
      if !guide.note.isEmpty { Section("Good to know") { Text(guide.note) } }
      Section("Take the next step") {
        if let house = model.house {
          if id == .visits || id == .setup { NavigationLink("Open Construction stages") { StagesPage(house: house) } }
          if id == .review { NavigationLink("Open Closure review and notes") { ClosureReview(house: house) } }
          if id == .photos { NavigationLink("Open Import existing photographs") { DocumentaryPhotosPage(house: house) } }
          if id == .references { NavigationLink("Open Printable references") { ReferencesPage(house: house) } }
          if id == .backup { NavigationLink("Open Automatic folder snapshots") { SnapshotSettings(house: house) } }
          Button(guide.actionTitle) { guidance.open(guide.destination) }.accessibilityIdentifier("guide-open-task")
        } else {
          Button("Create your house") { guidance.open(.createHouse) }.accessibilityIdentifier("guide-create-house")
          Text("You can read every guide before creating a house.")
        }
        ForEach(guide.related, id: \.self) { related in
          if let next = HomeGuide.all.first(where: { $0.id == related }) {
            NavigationLink(next.title) { HomeGuidePage(id: related) }
          }
        }
      }
    }.navigationTitle(guide.title).navigationBarTitleDisplayMode(.inline)
      .accessibilityIdentifier("guide-page-" + id.rawValue)
      .toolbar { HomeHelpToolbar() }
  }
}
