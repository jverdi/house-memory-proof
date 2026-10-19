import Foundation
import SceneKit
import UIKit
import Darwin

// Completion callbacks measure renderer cadence, not display presentation or
// GPU execution. Fixed histogram storage remains bounded for long sessions.
final class ViewerRenderCounter:NSObject,SCNSceneRendererDelegate,@unchecked Sendable {
  struct Reading:Codable,Equatable {
    var callbacks=0
    var intervals=0
    var seconds=0.0
    var maximumSeconds=0.0
    var bins=Array(repeating:0,count:9)
    static let bounds=[1.0/120,1.0/60,1.0/30,0.05,0.1,0.25,0.5,1.0]
    var valid:Bool {
      (0...10_000_000).contains(callbacks) && intervals==max(0,callbacks-1) && seconds.isFinite && seconds>=0 &&
      maximumSeconds.isFinite && maximumSeconds>=0 && maximumSeconds<=seconds &&
      bins.count==9 && bins.allSatisfy{(0...10_000_000).contains($0)} && bins.reduce(0,+)==intervals
    }
  }
  private let lock=NSLock()
  private var value=Reading()
  private var previous:Double?
  func record(at time:Double) {
    guard time.isFinite,time>=0 else{return}
    lock.lock();defer{lock.unlock()}
    if let previous {
      guard time>previous else{return}
      let duration=time-previous
      value.intervals+=1;value.seconds+=duration;value.maximumSeconds=max(value.maximumSeconds,duration)
      value.bins[Reading.bounds.firstIndex(where:{duration<=$0}) ?? 8]+=1
    }
    value.callbacks+=1;previous=time
  }
  func renderer(_ renderer:SCNSceneRenderer,didRenderScene scene:SCNScene,atTime time:TimeInterval) {
    record(at:ProcessInfo.processInfo.systemUptime)
  }
  func read()->Reading {lock.lock();defer{lock.unlock()};return value}
}

struct ViewerRuntimeSample:Codable {
  var elapsedSeconds:Double
  var rendering:ViewerRenderCounter.Reading
  var displayedVertices:Int
  var residentTiles:Int
  var decodedTextures:Int
  var navigationWaiting:Bool
  var memoryWarnings:Int
  var thermalState:String
  var lowPowerMode:Bool
  var processMemory:[String:UInt64]
  var valid:Bool {
    elapsedSeconds.isFinite && elapsedSeconds>=0 && rendering.valid && displayedVertices>=0 &&
    (0...512).contains(residentTiles) && (0...24).contains(decodedTextures) && memoryWarnings>=0 &&
    ["nominal","fair","serious","critical","unknown"].contains(thermalState)
  }
}
struct ViewerRuntimeReport:Codable {
  var version=1
  var sessionID=UUID()
  var projectID:UUID
  var projectRevision:Int
  var sourceRevision:String
  var build:String
  var hardware:String
  var systemVersion:String
  var platform:String
  var startedUTC=Date()
  var endedUTC:Date?
  var stopReason:String?
  var physicalQualification=false
  var intervalUpperBoundsSeconds=ViewerRenderCounter.Reading.bounds
  var samples:[ViewerRuntimeSample]=[]
  var limitation="User-started local session; completed render callbacks are not presented FPS or GPU timing. Histogram has eight upper bounds and a final overflow bin. Samples are ten seconds apart, up to two hours. Missing endedUTC means interrupted. Source images, room names and coordinates are excluded. This report does not grant device or accuracy qualification."
  var valid:Bool {
    version==1 && projectRevision>0 && !physicalQualification && intervalUpperBoundsSeconds==ViewerRenderCounter.Reading.bounds &&
    !samples.isEmpty && samples.count<=721 && samples.allSatisfy(\.valid) &&
    ((endedUTC==nil && stopReason==nil) || (endedUTC != nil && endedUTC!>=startedUTC && !(stopReason ?? "").isEmpty)) &&
    zip(samples,samples.dropFirst()).allSatisfy { a,b in
      b.elapsedSeconds>a.elapsedSeconds && b.memoryWarnings>=a.memoryWarnings &&
      b.rendering.callbacks>=a.rendering.callbacks && b.rendering.seconds>=a.rendering.seconds &&
      b.rendering.maximumSeconds>=a.rendering.maximumSeconds && zip(a.rendering.bins,b.rendering.bins).allSatisfy{before,after in after>=before}
    }
  }
}

@MainActor final class ViewerRuntimeRecorder {
  private(set) var report:ViewerRuntimeReport
  let counter=ViewerRenderCounter()
  private let file:URL
  private let started=ProcessInfo.processInfo.systemUptime
  private let state:()->(vertices:Int,tiles:Int,textures:Int,waiting:Bool)
  private let onError:(String)->Void
  private var task:Task<Void,Never>?
  private var observer:NSObjectProtocol?
  private var warnings=0,finished=false,errorReported=false
  static func folder(_ repo:Repository)->URL {repo.root.appendingPathComponent("viewer-runtime",isDirectory:true)}
  init(repository:Repository,house:House,state:@escaping()->(vertices:Int,tiles:Int,textures:Int,waiting:Bool),onError:@escaping(String)->Void)throws {
    let folder=Self.folder(repository)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}
    guard files.count<100 else{throw HouseError.message("Viewer performance reports reached their 100-session limit. Export them, then remove old reports from viewer-runtime in Files.")}
    self.state=state;self.onError=onError
    var system=utsname();uname(&system);var machine=system.machine
    let capacity=MemoryLayout.size(ofValue:machine)
    let hardware=withUnsafePointer(to:&machine){$0.withMemoryRebound(to:CChar.self,capacity:capacity){String(cString:$0)}}
    #if targetEnvironment(simulator)
    let platform="iPhone simulator"
    #else
    let platform="physical iPhone or iPad"
    #endif
    let initial=ViewerRuntimeReport(projectID:house.id,projectRevision:house.revision,
      sourceRevision:Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local",
      build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "local",
      hardware:hardware,systemVersion:UIDevice.current.systemVersion,platform:platform)
    report=initial
    file=folder.appendingPathComponent(initial.sessionID.uuidString+".json")
    sample()
    guard !errorReported else{throw HouseError.message("The initial viewer performance report could not be saved.")}
    observer=NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.warnings+=1 }}
    task=Task { [weak self] in
      while !Task.isCancelled {
        do{try await Task.sleep(nanoseconds:10_000_000_000)}catch{return}
        guard let self,!self.finished else{return}
        if self.report.samples.count>=720 {self.finish(reason:"two-hour-report-limit");return}
        self.sample()
      }
    }
  }
  deinit {task?.cancel();if let observer{NotificationCenter.default.removeObserver(observer)}}
  func sample() {
    guard !finished,report.samples.count<721 else{return}
    let elapsed=ProcessInfo.processInfo.systemUptime-started
    guard report.samples.last.map({elapsed>$0.elapsedSeconds}) ?? true else{return}
    let thermal:String
    switch ProcessInfo.processInfo.thermalState {case .nominal:thermal="nominal";case .fair:thermal="fair";case .serious:thermal="serious";case .critical:thermal="critical";@unknown default:thermal="unknown"}
    let current=state()
    report.samples.append(ViewerRuntimeSample(elapsedSeconds:elapsed,rendering:counter.read(),displayedVertices:current.vertices,
      residentTiles:current.tiles,decodedTextures:current.textures,navigationWaiting:current.waiting,memoryWarnings:warnings,
      thermalState:thermal,lowPowerMode:ProcessInfo.processInfo.isLowPowerModeEnabled,processMemory:SelfTests.memorySample()))
    persist()
  }
  func finish(reason:String) {
    guard !finished else{return}
    report.endedUTC=Date();report.stopReason=reason;sample();persist();finished=true
    task?.cancel();task=nil
    if let observer{NotificationCenter.default.removeObserver(observer);self.observer=nil}
  }
  private func persist() {
    do {
      guard report.valid else{throw HouseError.message("Viewer performance sample failed validation.")}
      let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
      try DurableFiles.write(encoder.encode(report),to:file)
    }catch{if !errorReported{errorReported=true;onError("Viewer performance report could not be saved: "+error.localizedDescription)}}
  }
  static func export(repository:Repository)throws->URL {
    let folder=folder(repository)
    guard FileManager.default.fileExists(atPath:folder.path) else{throw HouseError.message("Start a performance recording in Explore → Layers first.")}
    let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
    guard !files.isEmpty,files.count<=100 else{throw HouseError.message("No bounded viewer performance reports are available.")}
    let reports=try files.map { file->ViewerRuntimeReport in
      let data=try DurableFiles.read(file,limit:2_000_000)
      let report=try JSONDecoder().decode(ViewerRuntimeReport.self,from:data)
      guard report.valid else{throw HouseError.message("Viewer performance report is invalid; its original is retained.")}
      return report
    }
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    let destination=Exporter.destination("House-Xray-viewer-performance.json")
    try DurableFiles.write(encoder.encode(reports),to:destination);return destination
  }
}

@MainActor enum ViewerDiagnosticsTests {
  static func run(house:House,folder:URL,output:URL)throws->Bool {
    let counter=ViewerRenderCounter()
    for time in [0.0,0.005,0.025,0.225,2.225] {counter.record(at:time)}
    let reading=counter.read()
    for time in [Double.nan,Double.infinity,-1,2.225,1] {counter.record(at:time)}
    guard counter.read()==reading,reading.valid,reading.callbacks==5,reading.intervals==4,
      reading.bins==[1,0,1,0,0,1,0,0,1],abs(reading.maximumSeconds-2)<1e-12 else{return false}
    var forged=reading;forged.bins[0]=Int.max
    guard !forged.valid else{return false}
    let repo=try Repository(root:folder.appendingPathComponent("viewer-runtime-test"))
    var errors:[String]=[]
    let recorder=try ViewerRuntimeRecorder(repository:repo,house:house,state:{(30,2,1,false)},onError:{errors.append($0)})
    defer{recorder.finish(reason:"test-cleanup")}
    for _ in 0..<4 {recorder.counter.record(at:ProcessInfo.processInfo.systemUptime)}
    recorder.sample()
    let incompleteURL=try ViewerRuntimeRecorder.export(repository:repo)
    let incomplete=try JSONDecoder().decode([ViewerRuntimeReport].self,from:Data(contentsOf:incompleteURL))
    guard incomplete.count==1,incomplete[0].valid,incomplete[0].endedUTC==nil,
      incomplete[0].samples.last?.rendering.callbacks==4 else{return false}
    recorder.finish(reason:"test-ended")
    let completeURL=try ViewerRuntimeRecorder.export(repository:repo)
    let complete=try JSONDecoder().decode([ViewerRuntimeReport].self,from:Data(contentsOf:completeURL))
    guard complete.count==1,complete[0].valid,complete[0].stopReason=="test-ended",complete[0].endedUTC != nil,
      complete[0].samples.last?.residentTiles==2,errors.isEmpty else{return false}
    var invalid=complete[0];invalid.physicalQualification=true
    guard !invalid.valid else{return false}
    invalid=complete[0];invalid.samples[invalid.samples.count-1].rendering.callbacks=0
    guard !invalid.valid else{return false}
    invalid=complete[0];invalid.samples[0].decodedTextures=25
    guard !invalid.valid else{return false}
    invalid=complete[0];invalid.intervalUpperBoundsSeconds[0]=0.5
    guard !invalid.valid else{return false}
    let path=ViewerRuntimeRecorder.folder(repo).appendingPathComponent(complete[0].sessionID.uuidString+".json")
    let corrupt=try JSONEncoder().encode(invalid)
    try DurableFiles.write(corrupt,to:path)
    do{_=try ViewerRuntimeRecorder.export(repository:repo);return false}catch{}
    guard try Data(contentsOf:path)==corrupt else{return false}
    try DurableFiles.write(JSONEncoder().encode(complete[0]),to:path)
    let walk=WalkController();defer{walk.stop()}
    walk.load(house,SceneOptions());try walk.startPerformance(repository:repo)
    guard walk.recordingPerformance,walk.view.delegate != nil else{return false}
    walk.stop()
    guard !walk.recordingPerformance,walk.view.delegate==nil else{return false}
    let stopped=try JSONDecoder().decode([ViewerRuntimeReport].self,from:Data(contentsOf:ViewerRuntimeRecorder.export(repository:repo)))
    guard stopped.count==2,stopped.contains(where:{$0.stopReason=="viewer-inactive"}),stopped.allSatisfy(\.valid) else{return false}
    let evidence=[incomplete[0]]+stopped.filter{$0.sessionID != incomplete[0].sessionID}
    try DurableFiles.write(JSONEncoder().encode(evidence),to:output)
    return true
  }
}
