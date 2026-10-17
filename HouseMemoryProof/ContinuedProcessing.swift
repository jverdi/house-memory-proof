import BackgroundTasks
import Foundation

// A grant applies to one foreground-started operation. Work may begin in the
// foreground while admission is pending, but may continue in the background
// only after the launch handler grants it. Rejection retains foreground work.
@MainActor final class ContinuedProcessing {
  private var identifier:String?
  private var task:BGContinuedProcessingTask?
  private var expiration:(()->Void)?
  private var fraction=0.0
  private var detail="Starting"
  var granted:Bool {task != nil}
  static var backgroundGPUAvailable:Bool {BGTaskScheduler.supportedResources.contains(.gpu)}

  @discardableResult func begin(title:String,onExpiration:@escaping ()->Void)->Bool {
    finish(success:false)
    let id=(Bundle.main.bundleIdentifier ?? "HouseXray")+".continued."+UUID().uuidString
    identifier=id;expiration=onExpiration;fraction=0;detail="Starting"
    guard BGTaskScheduler.shared.register(forTaskWithIdentifier:id,using:.main,launchHandler:{[weak self] incoming in
      Task { @MainActor in
        guard let self,self.identifier==id,let continued=incoming as? BGContinuedProcessingTask else {
          incoming.setTaskCompleted(success:false);return
        }
        self.task=continued
        continued.progress.totalUnitCount=1000
        continued.expirationHandler = {[weak self] in
          Task { @MainActor in
            guard let self,self.identifier==id else{return}
            let stop=self.expiration
            self.finish(success:false)
            stop?()
          }
        }
        self.update(fraction:self.fraction,detail:self.detail)
      }
    }) else {identifier=nil;expiration=nil;return false}
    let request=BGContinuedProcessingTaskRequest(identifier:id,title:String(title.prefix(80)),subtitle:"Starting saved capture processing")
    request.strategy = .fail
    // This path is CPU-only. Movie/SceneKit jobs retain foreground checkpoints;
    // supported GPU hardware alone does not establish the signing entitlement.
    request.requiredResources=[]
    do {try BGTaskScheduler.shared.submit(request);return true}
    catch {finish(success:false);return false}
  }
  func update(fraction:Double,detail:String) {
    guard fraction.isFinite else{return}
    self.fraction=max(self.fraction,min(1,max(0,fraction)))
    self.detail=String(detail.prefix(120))
    guard let task else{return}
    task.progress.completedUnitCount=Int64(self.fraction*1000)
    task.updateTitle(task.title,subtitle:self.detail)
  }
  func finish(success:Bool) {
    let old=task,id=identifier
    task=nil;identifier=nil;expiration=nil
    if let old {
      old.expirationHandler=nil
      if success {old.progress.completedUnitCount=old.progress.totalUnitCount}
      old.setTaskCompleted(success:success)
    } else if let id {BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:id)}
  }
}
