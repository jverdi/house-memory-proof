import SwiftUI
import Darwin

@main struct HouseXrayApp: App {
  @StateObject private var model = AppModel()
  @State private var launchHandled = false
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(model).preferredColorScheme(.dark).tint(Color.mint).task {
        // Full-screen presentation can reattach this task. Launch commands and
        // fixtures must not rerun and replace the house the owner just chose.
        guard !launchHandled else { return }
        launchHandled = true
        #if DEBUG && targetEnvironment(simulator)
        let arguments=ProcessInfo.processInfo.arguments
        if let index=arguments.firstIndex(of:"--developer-command"),arguments.indices.contains(index+1),let repo=model.repository {
          await DeveloperCommands.launch(arguments[index+1],root:repo.root)
          return
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--guidance-empty") { model.selected = nil }
        if ProcessInfo.processInfo.arguments.contains("--service-tour-demo"),model.repository != nil {
          if let existing=model.houses.first(where:{$0.name=="Reviewed service fixture" && $0.isDemo}) {model.selected=existing.id}
          else {model.commit(SelfTests.serviceTourFixture())}
        }
        if ProcessInfo.processInfo.arguments.contains("--envelope-demo"),model.repository != nil {
          if let existing=model.houses.first(where:{$0.name=="Service envelope fixture" && $0.isDemo}) {
            model.selected=existing.id
            if ProcessInfo.processInfo.arguments.contains("--envelope-demo-reset") {model.edit{$0.features.removeAll{$0.envelope != nil}}}
          }else {
            var house=House.empty("Service envelope fixture");house.isDemo=true
            let line=[V3(0,0,1),V3(1,0,1)]
            house.features=[Feature(name:"Visible centerline",trade:.plumbing,roomID:house.rooms[0].id,stageID:house.stages[0].id,kind:.synthetic,mesh:Mesh(vertices:line,triangles:[]),route:line)]
            model.commit(house)
          }
        }
        if ProcessInfo.processInfo.arguments.contains("--drawing-demo"),let repo=model.repository {
          do {
            if let existing=model.houses.first(where:{$0.name=="Drawing marks fixture" && $0.isDemo}) {
              model.selected=existing.id
              if ProcessInfo.processInfo.arguments.contains("--drawing-demo-reset") {model.edit{$0.drawings[0].marks=nil}}
            }else {
              var house=House.empty("Drawing marks fixture");house.isDemo=true
              house.drawings=[Drawing(name:"Plan.pdf",asset:try repo.put(DrawingMarkTestFixture.pdf(),ext:"pdf"))]
              model.commit(house)
            }
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--ifc-demo"),let repo=model.repository {
          do {
            guard let path=Bundle.main.url(forResource:"IFC",withExtension:nil)?.appendingPathComponent("test-block.ifc") else{throw HouseError.message("IFC fixture missing.")}
            var h=House.empty("IFC import fixture");h.isDemo=true;h.rooms[0].name="Source room"
            h.drawings=[Drawing(name:"Source.ifc",asset:try repo.put(Data(contentsOf:path),ext:"ifc"),notes:"Synthetic IFC source; house alignment unknown")]
            model.commit(h)
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--point-cloud-demo"),let repo=model.repository {
          do {
            var h=House.empty("Point-cloud import fixture");h.isDemo=true;h.rooms[0].name="Source room"
            let raw=Data("ply\nformat ascii 1.0\nelement vertex 1\nproperty double x\nproperty double y\nproperty double z\nend_header\n1 2 3\n".utf8)
            h.drawings=[Drawing(name:"Source.ply",asset:try repo.put(raw,ext:"ply"),notes:"Synthetic PLY original; units and upright unknown")]
            model.commit(h)
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--documentary-demo"),let repo=model.repository {
          do {
            if let existing=model.houses.first(where:{$0.name=="Single-photo annotation fixture" && $0.isDemo}) {
              model.selected=existing.id
              if ProcessInfo.processInfo.arguments.contains("--documentary-demo-reset") {model.edit{$0.documentaryPhotos[0].annotations=nil}}
            } else {
              let capture=try SimulatedCapture.make(repo:repo)
              var h=House.empty("Single-photo annotation fixture");h.isDemo=true
              h.documentaryPhotos=[DocumentaryPhoto(image:capture.observations[0].image,note:"Annotation source photograph",roomID:h.rooms[0].id,stageID:h.stages[0].id)]
              model.commit(h)
            }
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--migration-fault"),let repo=model.repository {
          do {
            let root=repo.root.appendingPathComponent("migration-process-fixture-"+UUID().uuidString)
            let id=try StoreMigrationDiagnostics.legacyFixture(at:root)
            _=try Repository(root:root,migrationCheckpoint:{
              try DurableFiles.write(try JSONSerialization.data(withJSONObject:["project":id.uuidString,"fixture":root.lastPathComponent,"fault":"SIGKILL inside schema transaction before COMMIT"]),to:repo.root.appendingPathComponent("fault-ready.json"))
              raise(SIGKILL)
            })
          }catch{model.error=error.localizedDescription}
        }
        if ProcessInfo.processInfo.arguments.contains("--migration-recovery-check"),let repo=model.repository {
          do {
            let expected=try JSONSerialization.jsonObject(with:Data(contentsOf:repo.root.appendingPathComponent("fault-ready.json"))) as! [String:String]
            let root=repo.root.appendingPathComponent(expected["fixture"]!),before=try StoreMigrationDiagnostics.state(at:root)
            let recovered=try Repository(root:root),house=try recovered.all().first{$0.id.uuidString==expected["project"]}
            let assets=try house.map{try recovered.integrity($0)} ?? 0,after=try StoreMigrationDiagnostics.state(at:root)
            try DurableFiles.write(try JSONSerialization.data(withJSONObject:["passed":before.0==1 && before.1==0 && after.0==Repository.storeVersion && after.1==1 && assets>0,"verifiedAssets":assets,"fault":expected["fault"]!,"powerLossQualified":false]),to:repo.root.appendingPathComponent("process-recovery.json"))
          }catch{model.error=error.localizedDescription}
        }
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
        if ProcessInfo.processInfo.arguments.contains("--photo-demo"),let repo=model.repository {
          do {model.commit(try SimulatedCapture.make(repo:repo))}catch{model.error=error.localizedDescription}
        } else if ProcessInfo.processInfo.arguments.contains("--demo") {
          if let sample=model.houses.first(where:{$0.name=="The sample house" && $0.isDemo}){model.selected=sample.id}
          else {model.create("",demo:true)}
        }
        if ProcessInfo.processInfo.arguments.contains("--self-test") {
          await SelfTests.run(model: model)
        }
      }
    }
  }
}
