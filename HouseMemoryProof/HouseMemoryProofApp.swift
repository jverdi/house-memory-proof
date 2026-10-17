import SwiftUI

@main struct HouseXrayApp: App {
  @StateObject private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(model).preferredColorScheme(.dark).tint(Color.mint).task {
        if ProcessInfo.processInfo.arguments.contains("--self-test") {
          await SelfTests.run(model: model)
        }
        if ProcessInfo.processInfo.arguments.contains("--photo-demo"),let repo=model.repository {
          do {model.commit(try SimulatedCapture.make(repo:repo))}catch{model.error=error.localizedDescription}
        } else if ProcessInfo.processInfo.arguments.contains("--demo") {
          if let sample=model.houses.first(where:{$0.name=="The sample house" && $0.isDemo}){model.selected=sample.id}
          else {model.create("",demo:true)}
        }
      }
    }
  }
}
