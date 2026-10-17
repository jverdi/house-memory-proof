import SwiftUI
import Darwin

@main struct HouseXrayApp: App {
  @StateObject private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(model).preferredColorScheme(.dark).tint(Color.mint).task {
        #if DEBUG
        if (ProcessInfo.processInfo.arguments.contains("--journal-fault") || ProcessInfo.processInfo.arguments.contains("--capture-row-fault")),let repo=model.repository {
          do {
            var h=try SimulatedCapture.make(repo:repo);let observation=h.observations[0];h.observations=[];h.name="Process recovery fixture"
            guard model.commit(h) else{return}
            try repo.journalCapture(projectID:h.id,observation:observation)
            let rowFault=ProcessInfo.processInfo.arguments.contains("--capture-row-fault")
            if rowFault {
              try repo.stageCapture(observation,projectID:h.id,room:h.rooms[0],stage:h.stages.first{$0.id==observation.stageID}!,segment:h.segments[0])
              try repo.finishCaptureJournal(observation.id)
            }
            try DurableFiles.write(try JSONSerialization.data(withJSONObject:["project":h.id.uuidString,"observation":observation.id.uuidString,"fault":rowFault ? "SIGKILL after capture row commit, before project checkpoint":"SIGKILL after durable journal, before observation SQLite commit"]),to:repo.root.appendingPathComponent("fault-ready.json"))
            raise(SIGKILL)
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--journal-recovery-check"),let repo=model.repository {
          do {
            let expected=try JSONSerialization.jsonObject(with:Data(contentsOf:repo.root.appendingPathComponent("fault-ready.json"))) as! [String:String]
            let h=model.houses.first{$0.id.uuidString==expected["project"]}
            let passed=h?.observations.filter{$0.id.uuidString==expected["observation"]}.count==1
            let count=try h.map{try repo.integrity($0)} ?? 0
            try DurableFiles.write(try JSONSerialization.data(withJSONObject:["passed":passed && count>0,"recoveredExactlyOnce":passed,"verifiedAssets":count,"fault":expected["fault"] ?? "unknown","powerLossQualified":false]),to:repo.root.appendingPathComponent("process-recovery.json"))
          }catch{model.error=error.localizedDescription}
        }
        #endif
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
