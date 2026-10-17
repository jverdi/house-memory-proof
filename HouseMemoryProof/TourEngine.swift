import AVFoundation
import CryptoKit
import Foundation
import SceneKit
import UIKit

enum TourPreset:String,CaseIterable,Identifiable {
  case overview="Current layers",beforeAfter="Rough-in / finished",services="Service systems"
  var id:String{rawValue}
}
struct TourShot: Codable {
  var roomID: UUID
  var position: V3
  var yaw: Double
  var pitch: Double
  var caption: String
  var duration: Double
  var startPhase = 0.0
  var endPhase = 1.0
  var endPosition: V3? = nil
  var endYaw: Double? = nil
  var endPitch: Double? = nil
  var layerMode:String?=nil
  var tradeNames:[String]?=nil
}
struct TourPlan: Codable {
  var schema = 1
  var sourceRevision: Int
  var synthetic: Bool
  var shots: [TourShot]
  var excluded: [String]
  var fps = 30
  var width = 1920
  var height = 1080
}
enum TourDirector {
  static func plan(_ h: House, duration: Double = 20, options: SceneOptions = SceneOptions(),preset:TourPreset = .overview)
    -> TourPlan
  {
    if preset != .overview {
      var variants:[(String,SceneOptions)]=[]
      if preset == .beforeAfter {
        for mode in [ViewMode.rough,.finished] {var scope=options;scope.mode=mode;scope.stage=nil;variants.append((mode.rawValue,scope))}
      }else{
        for trade in [Trade.electrical,.lowVoltage,.plumbing,.hvac] {var scope=options;scope.mode = .rough;scope.trades=[trade];variants.append((trade.rawValue,scope))}
      }
      var shots:[TourShot]=[],excluded:[String]=[]
      for (label,scope) in variants {
        let part=plan(h,duration:20,options:scope)
        excluded += part.excluded.map{label+": "+$0}
        for var shot in part.shots {shot.layerMode=scope.mode.rawValue;shot.tradeNames=scope.trades.map{$0.rawValue}.sorted();shot.caption += " · "+label;shots.append(shot)}
      }
      // Group the comparison by room, retaining explicit cuts and frames.
      let roomOrder=Dictionary(h.rooms.enumerated().map{($0.element.id,$0.offset)},uniquingKeysWith:{a,_ in a})
      shots=shots.enumerated().sorted{a,b in
        let ar=roomOrder[a.element.roomID] ?? 0,br=roomOrder[b.element.roomID] ?? 0
        return ar==br ? a.offset<b.offset:ar<br
      }.map{$0.element}
      let frames=max(150,Int((min(60,max(5,duration))*30).rounded()))
      // Every selected shot has at least one frame and the timeline is exact.
      if shots.count>frames {excluded.append("Tour duration omitted \(shots.count-frames) shots.");shots=Array(shots.prefix(frames))}
      let count=max(1,shots.count),base=frames/count,remainder=frames%count
      for i in shots.indices {shots[i].duration=Double(base+(i<remainder ? 1:0))/30}
      return TourPlan(sourceRevision:h.revision,synthetic:h.isDemo,shots:chunk(shots),excluded:excluded)
    }
    let observations=PoseRefinement.selectedForHouse(h)
    var shots: [TourShot] = []
    var excluded: [String] = []
    for r in h.rooms where options.room == nil || options.room == r.id {
      var scope = options
      scope.room = r.id
      guard !SceneBuilder.features(h,options:scope).isEmpty else{excluded.append(r.name+": no geometry in selected layers");continue}
      let stages = SceneBuilder.eligibleStages(h, options: scope)
      let unregistered = SceneBuilder.activeUnregisteredSegment(h, options: scope)
      if h.isDemo && h.observations.isEmpty {
        shots.append(
          TourShot(
            roomID: r.id, position: r.origin + V3(r.size.x / 2, r.size.y / 2, 1.6), yaw: 0,
            pitch: 0.08, caption: r.name + " · SYNTHETIC DEMONSTRATION", duration: 5))
      } else if let obs = observations.last(where: {
        $0.roomID == r.id && !$0.documentary && stages.contains($0.stageID)
          && (unregistered == nil || $0.segmentID == unregistered)
      }) {
        let samples = observations.filter {
          $0.roomID == r.id && $0.segmentID == obs.segmentID && !$0.documentary
        }.sorted { $0.timestamp < $1.timestamp }
        let clearance = SpatialClearance(features: Exporter.canonicalFeatures(h, options: scope))
        let positions=NavigationGeometry.positions(house:h,options:scope)
        var moves: [TourShot] = []
        if samples.count >= 2 {
          for i in 1..<samples.count {
            let a = samples[i - 1]
            let b = samples[i]
            guard b.timestamp > a.timestamp, b.timestamp - a.timestamp < 5 else { continue }
            let start = pose(a, house: h)
            let end = pose(b, house: h)
            guard clearPath(start.0, end.0, house: h, options: scope, clearance: clearance, positions:positions) else {
              continue
            }
            moves.append(
              TourShot(
                roomID: r.id, position: start.0, yaw: start.1, pitch: start.2,
                caption: r.name + " · approximate captured path", duration: 5, endPosition: end.0,
                endYaw: end.1, endPitch: end.2))
          }
        }
        // Select separated candidates deterministically; cuts between them are explicit.
        if !moves.isEmpty {
          let count = min(3, moves.count)
          for i in 0..<count { shots.append(moves[i * moves.count / count]) }
        } else {
          let p = pose(obs, house: h)
          shots.append(
            TourShot(
              roomID: r.id, position: p.0, yaw: p.1, pitch: p.2,
              caption: r.name + " · approximate captured geometry", duration: 5))
        }
      } else {
        excluded.append(r.name + ": no captured camera viewpoint")
      }
    }
    let frames=max(150,Int((max(5,min(60,duration))*30).rounded()))
    if shots.count>frames {excluded.append("Tour duration omitted \(shots.count-frames) shots.");shots=Array(shots.prefix(frames))}
    let count=max(1,shots.count),base=frames/count,remainder=frames%count
    for i in shots.indices {shots[i].duration=Double(base+(i<remainder ? 1:0))/30}
    return TourPlan(sourceRevision:h.revision,synthetic:h.isDemo,shots:chunk(shots),excluded:excluded)
  }
  static func chunk(_ shots:[TourShot])->[TourShot] {
    var chunks: [TourShot] = []
    for shot in shots {
      let totalFrames = max(1, Int((shot.duration * 30).rounded()))
      var completed = 0
      while completed < totalFrames {
        let n = min(150, totalFrames - completed)
        var part = shot
        part.duration = Double(n) / 30
        part.startPhase = shot.startPhase+Double(completed)/Double(totalFrames)*(shot.endPhase-shot.startPhase)
        part.endPhase = shot.startPhase+Double(completed+n)/Double(totalFrames)*(shot.endPhase-shot.startPhase)
        chunks.append(part)
        completed += n
      }
    }
    return chunks
  }
  static func pose(_ observation: Observation, house: House) -> (V3, Double, Double) {
    let m = observation.camera
    var p = V3(m[3], -m[11], m[7])
    var f = V3(-m[2], m[10], -m[6])
    if let t = house.segments.first(where: { $0.id == observation.segmentID })?.registration {
      p = t.apply(p)
      f = t.apply(f) - t.apply(V3())
    }
    return (p, atan2(-f.x, f.y), asin(max(-1, min(1, f.normalized.z))))
  }
  static func clearPath(
    _ a: V3, _ b: V3, house: House, options: SceneOptions, clearance: SpatialClearance, positions: [V3]? = nil
  )
    -> Bool
  {
    let distance = (b - a).length
    guard distance >= 0.08, distance <= 1, abs(a.z - b.z) < 0.25 else { return false }
    let corridor=positions ?? NavigationGeometry.positions(house:house,options:options)
    for i in 0...10 {
      guard
        NavigationGeometry.observed(a + (b - a) * (Double(i) / 10), positions:corridor)
      else { return false }
    }
    return clearance.isClear(from: a, to: b, radius: 0.15)
  }

  static func camera(_ shot: TourShot, phase: Double) -> (V3, Double, Double) {
    let t = max(0, min(1, phase))
    let smooth = t * t * (3 - 2 * t)
    guard let end = shot.endPosition else {
      return (shot.position, shot.yaw + sin(t * Double.pi) * 0.65, shot.pitch)
    }
    let delta = atan2(
      sin((shot.endYaw ?? shot.yaw) - shot.yaw), cos((shot.endYaw ?? shot.yaw) - shot.yaw))
    return (
      shot.position + (end - shot.position) * smooth, shot.yaw + delta * smooth,
      shot.pitch + ((shot.endPitch ?? shot.pitch) - shot.pitch) * smooth
    )
  }

}
@MainActor enum MovieExporter {
  static func cacheKey(house: House, plan: TourPlan, options: SceneOptions) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(house)
    data.append(try encoder.encode(plan))
    let selection = [
      "renderer-v7", options.mode.rawValue,
      options.trades.map { $0.rawValue }.sorted().joined(separator: ","), String(options.ceilings),
      options.room?.uuidString ?? "all", options.stage?.uuidString ?? "all",
    ].joined(separator: "|")
    data.append(Data(selection.utf8))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func clipIssue(_ url:URL,frames:Int,width:Int,height:Int) async -> String? {
    do {
      let asset=AVURLAsset(url:url)
      guard let track=try await asset.loadTracks(withMediaType:.video).first else{return "No video track"}
      let duration=try await asset.load(.duration),size=try await track.load(.naturalSize),rate=try await track.load(.nominalFrameRate)
      let actual=CMTimeGetSeconds(duration),expected=Double(frames)/30
      guard abs(actual-expected)<1.0/600 else{return "Duration \(actual) seconds; expected \(expected) seconds"}
      guard Int(size.width)==width,Int(size.height)==height else{return "Dimensions \(size.width) × \(size.height); expected \(width) × \(height)"}
      guard abs(rate-30)<0.1 else{return "Frame rate \(rate); expected 30"}
      let generator=AVAssetImageGenerator(asset:asset);generator.maximumSize=CGSize(width:320,height:180)
      _=try await generator.image(at:CMTime(value:Int64(max(0,frames-1)),timescale:30))
      return nil
    }catch{return "Frame decode: \(error.localizedDescription)"}
  }
  static func validClip(_ url:URL,frames:Int,width:Int,height:Int) async -> Bool {
    await clipIssue(url,frames:frames,width:width,height:height)==nil
  }
  // Compatibility adapter: AVAssetWriter's pixel buffer adaptor remains available
  // in iOS 26. Its use is isolated here; no live screen recording is performed.
  static func render(
    _ house: House, repo: Repository, options: SceneOptions, duration: Double = 20,
    width: Int = 1920, height: Int = 1080, preset:TourPreset = .overview, progress: @escaping (Double) -> Void
  ) async throws -> URL {
    var plan = TourDirector.plan(house, duration: duration, options: options,preset:preset)
    plan.width = width
    plan.height = height
    guard !plan.shots.isEmpty else {
      throw HouseError.message("A tour needs a captured viewpoint or the synthetic sample house.")
    }
    guard repo.freeBytes() > 800_000_000 else {
      throw HouseError.message("Free at least 800 MB for movie segments and the final file.")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let planData = try encoder.encode(plan)
    let hash = try cacheKey(house: house, plan: plan, options: options)
    let folder = repo.root.appendingPathComponent("tours/" + hash, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try planData.write(to: folder.appendingPathComponent("tour.json"), options: .atomic)
    try repo.job(hash, state: "running", data: planData)
    var files: [URL] = []
    let total = plan.shots.reduce(0) { $0 + Int(($1.duration * 30).rounded()) }
    var complete = 0
    for (shotIndex, shot) in plan.shots.enumerated() {
      let url = folder.appendingPathComponent("shot-\(shotIndex).mp4")
      let frames = Int((shot.duration * 30).rounded())
      let checksumURL=url.appendingPathExtension("sha256")
      if FileManager.default.fileExists(atPath:url.path),
        let expected=try? String(contentsOf:checksumURL,encoding:.utf8),
        let actual=try? StreamingArchive.digest(url).sha,actual==expected,
        await validClip(url,frames:frames,width:width,height:height)
      {
        files.append(url)
        complete += frames
        continue
      }
      try? FileManager.default.removeItem(at: url)
      let candidate = folder.appendingPathComponent("shot-\(shotIndex).partial.mp4")
      try? FileManager.default.removeItem(at: candidate)
      let scene = SceneBuilder.scene(
        house,
        options: SceneOptions(
          mode: shot.layerMode.flatMap(ViewMode.init(rawValue:)) ?? options.mode, trades: shot.tradeNames.map{Set($0.compactMap(Trade.init(rawValue:)))} ?? options.trades, ceilings: options.ceilings, room: shot.roomID,
          stage: shot.layerMode==nil ? options.stage:nil))
      let camera = SceneBuilder.camera(at: shot.position, yaw: shot.yaw, pitch: shot.pitch)
      scene.rootNode.addChildNode(camera)
      let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
      renderer.scene = scene
      renderer.pointOfView = camera
      let writer = try AVAssetWriter(outputURL: candidate, fileType: .mp4)
      let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
          AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,AVVideoExpectedSourceFrameRateKey:30,AVVideoMaxKeyFrameIntervalKey:60],
        ])
      input.expectsMediaDataInRealTime = false
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
          kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
          kCVPixelBufferCGImageCompatibilityKey as String: true,
          kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
      guard writer.canAdd(input) else { throw HouseError.message("H.264 export is unavailable.") }
      writer.add(input)
      guard writer.startWriting() else {
        throw writer.error ?? HouseError.message("Could not start movie encoder.")
      }
      writer.startSession(atSourceTime: .zero)
      do {
        for frame in 0..<frames {
          try Task.checkCancellation()
          guard UIApplication.shared.applicationState != .background,
            ProcessInfo.processInfo.thermalState != .critical
          else {
            throw HouseError.message(
              "Movie checkpoint saved. Keep the app open and cool, then export again to resume.")
          }
          while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else {
              throw writer.error ?? HouseError.message("Movie encoder stopped.")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
          }
          let phase =
            shot.startPhase + (shot.endPhase - shot.startPhase) * Double(frame)
            / Double(max(1, frames - 1))
          let pose = TourDirector.camera(shot, phase: phase)
          camera.simdPosition = pose.0.render
          camera.eulerAngles = SCNVector3(Float(pose.2), Float(pose.1), 0)
          let image = renderer.snapshot(
            atTime: Double(frame) / 30, with: CGSize(width: width, height: height),
            antialiasingMode: .none)
          try autoreleasepool {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
              kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
              [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
              ] as CFDictionary, &buffer)
            guard status == kCVReturnSuccess, let buffer, let cg = image.cgImage else {
              throw HouseError.message("Unable to allocate a movie frame.")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard
              let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
            else { throw HouseError.message("Movie color context failed.") }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            let text =
              shot.caption + "\nHouse Xray · revision \(house.revision) · \(shot.layerMode ?? options.mode.rawValue)"
            let rect = CGRect(
              x: 24, y: CGFloat(height) - 92, width: CGFloat(width) - 48, height: 76)
            UIColor.black.withAlphaComponent(0.65).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: -10, dy: -5), cornerRadius: 8).fill()
            (text as NSString).draw(
              in: rect,
              withAttributes: [
                .font: UIFont.systemFont(ofSize: CGFloat(width) / 55, weight: .medium),
                .foregroundColor: UIColor.white,
              ])
            UIGraphicsPopContext()
            ctx.restoreGState()
            guard
              adaptor.append(
                buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            else { throw writer.error ?? HouseError.message("Movie frame was rejected.") }
          }
          progress(Double(complete + frame + 1) / Double(total))
          await Task.yield()
        }
        // Close the timeline after the last frame's full display interval.
        // Without this the writer may end at (frames-1)/fps and short clips
        // accumulate missing frame durations during passthrough assembly.
        writer.endSession(atSourceTime:CMTime(value:Int64(frames),timescale:30))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
          throw writer.error ?? HouseError.message("Movie segment did not finish.")
        }
        if let issue=await clipIssue(candidate,frames:frames,width:width,height:height){throw HouseError.message("Encoded shot: "+issue)}
        try FileManager.default.moveItem(at: candidate, to: url)
        try DurableFiles.write(Data(try StreamingArchive.digest(url).sha.utf8),to:checksumURL)
        files.append(url)
        complete += frames
        try repo.job(hash, state: "checkpointed", data: planData)
      } catch {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: candidate)
        try? repo.job(hash, state: "checkpointed", data: planData)
        throw error
      }
    }
    let composition = AVMutableComposition()
    guard
      let video = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw HouseError.message("Could not assemble the tour.") }
    var time = CMTime.zero
    for file in files {
      let asset = AVURLAsset(url: file)
      guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw HouseError.message("Movie segment has no video.")
      }
      let duration = try await asset.load(.duration)
      try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: time)
      time = CMTimeAdd(time, duration)
    }
    let output = Exporter.destination("House-Xray-tour.mp4")
    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetPassthrough)
    else { throw HouseError.message("Movie assembly unavailable.") }
    try await export.export(to: output, as: .mp4)
    if let issue=await clipIssue(output,frames:total,width:width,height:height){throw HouseError.message("Final movie: "+issue)}
    try planData.write(to: output.deletingPathExtension().appendingPathExtension("json"))
    try repo.job(hash, state: "succeeded", data: planData)
    progress(1)
    return output
  }
}
