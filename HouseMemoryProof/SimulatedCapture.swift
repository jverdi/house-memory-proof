import Foundation
import UIKit

// Camera observations generated from a planar construction target. Ground truth is
// retained only in this generator/evaluator; Reconstruction receives ordinary observations.
enum SimulatedCapture {
  static func make(repo: Repository) throws -> House {
    var h = House.empty("Simulated capture laboratory")
    h.isDemo = true
    h.notes =
      "Synthetic camera and depth dataset. This demonstrates the processing pipeline, not iPhone precision or complete-house reconstruction."
    h.rooms[0].name = "Virtual construction wall"
    h.rooms[0].origin = V3(-1.5, 0, 0)
    h.rooms[0].size = V3(3, 3, 2.8)
    h.stages[0].kind = .synthetic
    h.stages[1].kind = .synthetic
    let s = Segment(roomID: h.rooms[0].id, stageID: h.stages[0].id)
    h.segments = [s]
    h.features = [
      Feature(
        name: "Observed LiDAR surface", trade: .unknown, roomID: s.roomID, stageID: s.stageID,
        kind: .synthetic, mesh: .box(center: V3(0, 2, 1.4), size: V3(2.4, 0.01, 2.0)),
        notes: "Synthetic target; never a real observation.", segmentID: s.id,geometrySource:.capturedMesh)
    ]
    let w = 192
    let height = 144
    let fx = 130.0
    let fy = 130.0
    for frame in 0..<9 {
      let x = Double(frame - 4) * 0.08
      var pixels = [UInt8](repeating: 255, count: w * height * 4)
      var depth = Data()
      for v in 0..<height {
        for u in 0..<w {
          let wx = x + (Double(u) - 96) * 2 / fx
          let wz = 1.4 - (Double(v) - 72) * 2 / fy
          let stud = abs(wx * 2.5 - (wx * 2.5).rounded()) < 0.08
          let wire = abs(wz - 1.1) < 0.035
          let checker = (Int(floor(wx * 12)) + Int(floor(wz * 12))) & 1 == 0
          let color: (UInt8, UInt8, UInt8) =
            wire
            ? (240, 170, 35) : stud ? (175, 126, 75) : checker ? (65, 85, 100) : (115, 130, 140)
          let i = (v * w + u) * 4
          pixels[i] = color.0
          pixels[i + 1] = color.1
          pixels[i + 2] = color.2
          depth.float(Float(2 + sin(Double(u * 7 + v * 11 + frame * 19)) * 0.001))
        }
      }
      let data = Data(pixels)
      guard let provider = CGDataProvider(data: data as CFData),
        let cg = CGImage(
          width: w, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
          decode: nil, shouldInterpolate: false, intent: .defaultIntent),
        let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.98)
      else { throw HouseError.message("Synthetic camera renderer failed.") }
      let image = try repo.put(jpeg, ext: "jpg")
      let d = try repo.put(depth, ext: "depth32")
      let confidence = try repo.put(Data(repeating: 2, count: w * height), ext: "confidence8")
      var camera = Rigid().values
      camera[3] = x
      camera[7] = 1.4
      h.observations.append(
        Observation(
          roomID: s.roomID, stageID: s.stageID, segmentID: s.id, timestamp: Double(frame),
          image: image, depth: d, confidence: confidence, depthWidth: w, depthHeight: height,
          width: w, height: height, camera: camera, intrinsics: [fx, 0, 96, 0, fy, 72, 0, 0, 1],
          tracking: "synthetic normal", light: 1000, sharpness: CaptureController.sharpness(cg),
          note: "Synthetic camera \(frame); known plane at Y=2 m. Not field evidence.",
          imageOrientation: 1))
    }
    return h
  }
}
