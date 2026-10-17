import SwiftUI

@main struct HouseXrayApp:App {
    @StateObject private var model=AppModel()
    var body:some Scene {WindowGroup {RootView().environmentObject(model).preferredColorScheme(.dark).tint(Color.mint).task{
        if ProcessInfo.processInfo.arguments.contains("--self-test") {await SelfTests.run(model:model)}
        if ProcessInfo.processInfo.arguments.contains("--demo"),model.houses.isEmpty {model.create("",demo:true)}
    }}}
}
