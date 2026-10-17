import AVFoundation
import CryptoKit
import Foundation
import SceneKit
import UIKit

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
  static func plan(_ h: House, duration: Double = 20, options: SceneOptions = SceneOptions())
    -> TourPlan
  {
    let observations=PoseRefinement.selectedForHouse(h)
    var shots: [TourShot] = []
    var excluded: [String] = []
    for r in h.rooms where options.room == nil || options.room == r.id {
      var scope = options
      scope.room = r.id
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
    let length = max(5, min(60, duration)) / Double(max(1, shots.count))
    for i in shots.indices { shots[i].duration = length }
    var chunks: [TourShot] = []
    for shot in shots {
      let totalFrames = max(1, Int((shot.duration * 30).rounded()))
      var completed = 0
      while completed < totalFrames {
        let n = min(150, totalFrames - completed)
        var part = shot
        part.duration = Double(n) / 30
        part.startPhase = Double(completed) / Double(totalFrames)
        part.endPhase = Double(completed + n) / Double(totalFrames)
        chunks.append(part)
        completed += n
      }
    }
    return TourPlan(
      sourceRevision: h.revision, synthetic: h.isDemo, shots: chunks, excluded: excluded)
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
      "renderer-v4", options.mode.rawValue,
      options.trades.map { $0.rawValue }.sorted().joined(separator: ","), String(options.ceilings),
      options.room?.uuidString ?? "all", options.stage?.uuidString ?? "all",
    ].joined(separator: "|")
    data.append(Data(selection.utf8))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  // Compatibility adapter: AVAssetWriter's pixel buffer adaptor remains available
  // in iOS 26. Its use is isolated here; no live screen recording is performed.
  static func render(
    _ house: House, repo: Repository, options: SceneOptions, duration: Double = 20,
    width: Int = 1920, height: Int = 1080, progress: @escaping (Double) -> Void
  ) async throws -> URL {
    var plan = TourDirector.plan(house, duration: duration, options: options)
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
      if FileManager.default.fileExists(atPath: url.path),
        let d = try? await AVURLAsset(url: url).load(.duration),
        abs(CMTimeGetSeconds(d) - Double(frames) / 30) < 0.1
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
          mode: options.mode, trades: options.trades, ceilings: options.ceilings, room: shot.roomID,
          stage: options.stage))
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
          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
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
              shot.caption + "\nHouse Xray · revision \(house.revision) · \(options.mode.rawValue)"
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
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
          throw writer.error ?? HouseError.message("Movie segment did not finish.")
        }
        try FileManager.default.moveItem(at: candidate, to: url)
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
    let final = AVURLAsset(url: output)
    let actual = try await final.load(.duration)
    guard abs(CMTimeGetSeconds(actual) - Double(total) / 30) < 0.15 else {
      throw HouseError.message("Final movie duration did not match its plan.")
    }
    try planData.write(to: output.deletingPathExtension().appendingPathExtension("json"))
    try repo.job(hash, state: "succeeded", data: planData)
    progress(1)
    return output
  }
}
