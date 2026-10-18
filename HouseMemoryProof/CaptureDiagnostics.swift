import Foundation
import ARKit
import SceneKit
import UIKit
import Darwin

// Counts completed SceneKit render callbacks, not display presentation or GPU timing.
final class CaptureRenderCounter:NSObject,ARSCNViewDelegate,@unchecked Sendable {
  private let lock=NSLock()
  private var value=0
  func renderer(_ renderer:SCNSceneRenderer,didRenderScene scene:SCNScene,atTime time:TimeInterval) {
    lock.lock();value += 1;lock.unlock()
  }
  func read()->Int {lock.lock();defer{lock.unlock()};return value}
}

struct CaptureRuntimeSample:Codable,Equatable {
  var elapsedSeconds:Double
  var deliveredCameraFrames:Int
  var normalTrackingFrames:Int
  var renderedCallbacks:Int
  var savedImages:Int
  var saveFailures:Int
  var pendingSaves:Int
  var maximumPendingSaves:Int
  var completedSaveSeconds:Double
  var maximumSaveSeconds:Double
  var memoryWarnings:Int
  var thermalState:String
  var lowPowerMode:Bool
  var batteryLevel:Double?
  var batteryState:String
  var freeDiskBytes:Int64
  var processMemory:[String:UInt64]
  var valid:Bool {
    elapsedSeconds.isFinite && elapsedSeconds>=0 && deliveredCameraFrames>=0 &&
    (0...deliveredCameraFrames).contains(normalTrackingFrames) && renderedCallbacks>=0 &&
    savedImages>=0 && saveFailures>=0 && pendingSaves>=0 && maximumPendingSaves>=pendingSaves &&
    completedSaveSeconds.isFinite && completedSaveSeconds>=0 && maximumSaveSeconds.isFinite &&
    maximumSaveSeconds>=0 && maximumSaveSeconds<=completedSaveSeconds && memoryWarnings>=0 &&
    ["nominal","fair","serious","critical","unknown"].contains(thermalState) &&
    ["unknown","unplugged","charging","full"].contains(batteryState) &&
    (batteryLevel==nil || (batteryLevel!.isFinite && (0...1).contains(batteryLevel!))) && freeDiskBytes>=0
  }
}
struct CaptureRuntimeReport:Codable {
  var version=1
  var sessionID:UUID
  var projectID:UUID
  var mode:String
  var startedUTC:Date
  var sourceRevision:String
  var build:String
  var hardware:String
  var systemVersion:String
  var platform:String
  var samples:[CaptureRuntimeSample]=[]
  var acquisitionEndSeconds:Double?
  var endedUTC:Date?
  var stopReason:String?
  var physicalQualification=false
  var samplePeriodSeconds=10
  var sampleLimit=721
  var limitation="Sampled resources and cumulative ARKit/SceneKit callbacks. Render callbacks are not display-presented FPS or GPU timing. Battery is the OS estimate; disk is volume free space. A report without endedUTC was interrupted before finalization. Camera images, coordinates and field accuracy are not included."
  var valid:Bool {
    version==1 && ["capture","reveal"].contains(mode) && !samples.isEmpty && samples.count<=sampleLimit &&
    sampleLimit==721 && samplePeriodSeconds==10 && !physicalQualification &&
    (acquisitionEndSeconds==nil || (acquisitionEndSeconds!.isFinite && acquisitionEndSeconds!>=0 && acquisitionEndSeconds!<=samples.last!.elapsedSeconds)) &&
    (endedUTC==nil || (endedUTC!>=startedUTC && stopReason != nil && acquisitionEndSeconds != nil)) &&
    samples.allSatisfy(\.valid) && zip(samples,samples.dropFirst()).allSatisfy { a,b in
      b.elapsedSeconds>a.elapsedSeconds && b.deliveredCameraFrames>=a.deliveredCameraFrames &&
      b.normalTrackingFrames>=a.normalTrackingFrames && b.renderedCallbacks>=a.renderedCallbacks &&
      b.savedImages>=a.savedImages && b.saveFailures>=a.saveFailures &&
      b.maximumPendingSaves>=a.maximumPendingSaves && b.completedSaveSeconds>=a.completedSaveSeconds &&
      b.maximumSaveSeconds>=a.maximumSaveSeconds && b.memoryWarnings>=a.memoryWarnings
    }
  }
  static func rate(_ before:Int,_ after:Int,seconds:Double)->Double? {
    guard seconds.isFinite,seconds>0,before>=0,after>=before else{return nil}
    return Double(after-before)/seconds
  }
}

@MainActor final class CaptureRuntimeRecorder {
  private(set) var report:CaptureRuntimeReport
  private let file:URL
  private let repository:Repository
  private let renderCounter:CaptureRenderCounter
  private let renderStart:Int
  private let started:Double
  private let oldBatteryMonitoring:Bool
  private let onError:(String)->Void
  private var task:Task<Void,Never>?
  private var observer:NSObjectProtocol?
  private var delivered=0,normal=0,saved=0,failures=0,pending=0,maximumPending=0,warnings=0
  private var saveSeconds=0.0,maximumSaveSeconds=0.0
  private var finished=false,errorReported=false
  static func folder(_ repo:Repository)->URL {repo.root.appendingPathComponent("capture-runtime",isDirectory:true)}
  init(repository:Repository,sessionID:UUID,projectID:UUID,reveal:Bool,renderCounter:CaptureRenderCounter,onError:@escaping(String)->Void)throws {
    let folder=Self.folder(repository)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let existing=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}
    guard existing.count<100 else{throw HouseError.message("Capture performance reports reached their 100-session limit. Export them, then remove old reports from the capture-runtime folder in Files. Capture originals are unaffected.")}
    self.repository=repository;self.renderCounter=renderCounter;self.renderStart=renderCounter.read();self.onError=onError
    started=ProcessInfo.processInfo.systemUptime
    oldBatteryMonitoring=UIDevice.current.isBatteryMonitoringEnabled
    var system=utsname();uname(&system);var machine=system.machine
    let capacity=MemoryLayout.size(ofValue:machine)
    let hardware=withUnsafePointer(to:&machine){$0.withMemoryRebound(to:CChar.self,capacity:capacity){String(cString:$0)}}
    #if targetEnvironment(simulator)
    let platform="iPhone simulator"
    #else
    let platform="physical iPhone or iPad"
    #endif
    report=CaptureRuntimeReport(sessionID:sessionID,projectID:projectID,mode:reveal ? "reveal":"capture",startedUTC:Date(),sourceRevision:Bundle.main.object(forInfoDictionaryKey:"ProofSourceRevision") as? String ?? "local",build:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "local",hardware:hardware,systemVersion:UIDevice.current.systemVersion,platform:platform)
    file=folder.appendingPathComponent(UUID().uuidString+".json")
    UIDevice.current.isBatteryMonitoringEnabled=true
    sample()
    observer=NotificationCenter.default.addObserver(forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.warnings += 1 }}
    task=Task { [weak self] in
      while !Task.isCancelled {
        do{try await Task.sleep(nanoseconds:10_000_000_000)}catch{return}
        guard let self,!self.finished else{return}
        if self.report.samples.count>=self.report.sampleLimit-1 {self.finish(reason:"two-hour-report-limit");return}
        self.sample()
      }
    }
  }
  deinit {task?.cancel();if let observer{NotificationCenter.default.removeObserver(observer)}}
  func frame(normalTracking:Bool) {guard !finished else{return};delivered += 1;if normalTracking{normal += 1}}
  func beganSave() {guard !finished else{return};pending += 1;maximumPending=max(maximumPending,pending)}
  func completedSave(seconds:Double,success:Bool) {
    guard !finished else{return}
    pending=max(0,pending-1)
    if success{saved += 1}else{failures += 1}
    let duration=seconds.isFinite ? max(0,seconds):0
    saveSeconds += duration;maximumSaveSeconds=max(maximumSaveSeconds,duration)
  }
  func endAcquisition() {
    guard !finished,report.acquisitionEndSeconds==nil else{return}
    sample();report.acquisitionEndSeconds=report.samples.last?.elapsedSeconds
  }
  func finish(reason:String) {
    guard !finished else{return}
    endAcquisition()
    report.endedUTC=Date();report.stopReason=reason;sample();persist();finished=true
    task?.cancel();task=nil
    if let observer{NotificationCenter.default.removeObserver(observer);self.observer=nil}
    UIDevice.current.isBatteryMonitoringEnabled=oldBatteryMonitoring
  }
  private func sample() {
    let elapsed=max(0,ProcessInfo.processInfo.systemUptime-started)
    guard report.samples.last.map({elapsed>$0.elapsedSeconds}) ?? true,report.samples.count<report.sampleLimit else{return}
    let thermal:String
    switch ProcessInfo.processInfo.thermalState {case .nominal:thermal="nominal";case .fair:thermal="fair";case .serious:thermal="serious";case .critical:thermal="critical";@unknown default:thermal="unknown"}
    let battery:String
    switch UIDevice.current.batteryState {case .unknown:battery="unknown";case .unplugged:battery="unplugged";case .charging:battery="charging";case .full:battery="full";@unknown default:battery="unknown"}
    let level=Double(UIDevice.current.batteryLevel)
    report.samples.append(CaptureRuntimeSample(elapsedSeconds:elapsed,deliveredCameraFrames:delivered,normalTrackingFrames:normal,renderedCallbacks:max(0,renderCounter.read()-renderStart),savedImages:saved,saveFailures:failures,pendingSaves:pending,maximumPendingSaves:maximumPending,completedSaveSeconds:saveSeconds,maximumSaveSeconds:maximumSaveSeconds,memoryWarnings:warnings,thermalState:thermal,lowPowerMode:ProcessInfo.processInfo.isLowPowerModeEnabled,batteryLevel:(0...1).contains(level) ? level:nil,batteryState:battery,freeDiskBytes:max(0,repository.freeBytes()),processMemory:SelfTests.memorySample()))
    persist()
  }
  private func persist() {
    do {
      guard report.valid else{throw HouseError.message("Capture performance sample failed validation.")}
      let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
      try DurableFiles.write(encoder.encode(report),to:file)
    }catch {if !errorReported{errorReported=true;onError("Capture performance report could not be saved: "+error.localizedDescription)}}
  }
  static func export(repository:Repository)throws->URL {
    let folder=folder(repository)
    let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
    guard !files.isEmpty,files.count<=100 else{throw HouseError.message("No bounded capture performance reports are available. Start and stop a capture first.")}
    let reports=try files.map{file->CaptureRuntimeReport in
      let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
      guard size>0,size<=2_000_000 else{throw HouseError.message("Capture performance report exceeds its size limit.")}
      let report=try JSONDecoder().decode(CaptureRuntimeReport.self,from:Data(contentsOf:file))
      guard report.valid else{throw HouseError.message("Capture performance report is invalid; the original file is retained.")}
      return report
    }
    let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    let destination=Exporter.destination("House-Xray-capture-performance.json")
    try DurableFiles.write(encoder.encode(reports),to:destination)
    return destination
  }
}
