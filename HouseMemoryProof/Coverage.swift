import Foundation
import SwiftUI

struct CoverageReport: Codable {
  var segmentID: UUID
  var revision: Int
  var sampledPatches: Int
  var supportedPatches: Int
  var insufficientViews: Int
  var poorQuality: Int
  var missingDepth: Int
  var observedArea: Double
  var supportedArea: Double
  var fraction: Double { observedArea > 0 ? supportedArea / observedArea : 0 }
}
enum CoverageAnalyzer {
  struct Patch {
    var center:V3;var normal:V3;var area:Double
    var positions:[V3]=[];var supported=false;var lowQuality=false;var noDepth=false
  }
  // Only observed mesh area is evaluated. No claim about unseen cavities or absent geometry.
  static func analyze(house: House, segment: Segment, repo: Repository) throws -> CoverageReport {
    // Captured meshes and these raw camera poses share the original session
    // frame. Optimized camera-only corrections must not move the mesh frame.
    let observations=VisualMapping.keyframes(house.observations.filter {
      $0.segmentID == segment.id && !$0.documentary
    },limit:120)
    var report = CoverageReport(
      segmentID: segment.id, revision: house.revision, sampledPatches: 0, supportedPatches: 0,
      insufficientViews: 0, poorQuality: 0, missingDepth: 0, observedArea: 0, supportedArea: 0)
    let surfaces = house.features.filter {
      $0.segmentID == segment.id && $0.resolvedGeometrySource == .capturedMesh
    }
    let triangleCount=surfaces.reduce(0){$0+$1.mesh.triangles.count/3}
    let strideCount=max(1,(triangleCount+4095)/4096)
    var ordinal=0,patches:[Patch]=[]
    for f in surfaces {
      try Task.checkCancellation()
      for face in 0..<(f.mesh.triangles.count/3) {
        if face%4096==0 {try Task.checkCancellation()}
        let selected=ordinal%strideCount==0;ordinal+=1
        guard selected else{continue}
        let a = f.mesh.vertices[Int(f.mesh.triangles[face * 3])]
        let b = f.mesh.vertices[Int(f.mesh.triangles[face * 3 + 1])]
        let c = f.mesh.vertices[Int(f.mesh.triangles[face * 3 + 2])]
        let cross = (b - a).cross(c - a)
        let area = cross.length * 0.5
        guard area > 1e-9 else { continue }
        let center = (a + b + c) * (1 / 3.0)
        let normal = cross.normalized
        patches.append(Patch(center:center,normal:normal,area:area))
      }
    }
    // At most 4,096 patch states and one original depth/confidence pair are
    // resident. Never multiply sampled area into unexamined triangle area.
    for o in observations {
      try Task.checkCancellation()
      if patches.allSatisfy({$0.supported}) {break}
      let w=o.depthWidth,h=o.depthHeight
      let dimensionsValid=w>0 && h>0 && w<=1_000_000/h
      let count=dimensionsValid ? w*h:0
      let depth:Data?,confidence:Data?
      if dimensionsValid {
        depth=try o.depth.map{try DurableFiles.read(repo.assetURL($0),limit:count*4)}
        confidence=try o.confidence.map{try DurableFiles.read(repo.assetURL($0),limit:count)}
      }else{depth=nil;confidence=nil}
      let position=V3(o.camera[3],-o.camera[11],o.camera[7])
      for i in patches.indices where !patches[i].supported {
          if i%64==0 {try Task.checkCancellation()}
          let center=patches[i].center,normal=patches[i].normal
          guard let (uv, z) = TextureBuilder.project(center, through: o) else { continue }
          guard let depth,dimensionsValid,depth.count==count*4 else {
            patches[i].noDepth = true
            continue
          }
          let index=min(h-1,Int(uv.v*Double(h)))*w+min(w-1,Int(uv.u*Double(w)))
          guard let confidence,confidence.count==count,confidence[index]>=2 else {
            patches[i].lowQuality=true;continue
          }
          let measured=Double(Float(bitPattern:depth.uint32(index*4)))
          guard measured.isFinite,measured>0,abs(measured-z)<=0.03 else{continue}
          let ray = (position - center).normalized
          guard abs(normal.dot(ray)) > 0.35, o.intrinsics[0] / z > 120, o.light >= 150,
            o.sharpness >= 0.02
          else {
            patches[i].lowQuality = true
            continue
          }
          if patches[i].positions.allSatisfy({ ($0 - position).length >= 0.12 }) {patches[i].positions.append(position)}
          let positions=patches[i].positions
          guard positions.count>=3 else{continue}
        var angularBaseline = false
        for a in positions.indices {
          for b in positions.indices where b > a {
            if (positions[a] - center).normalized.dot((positions[b] - center).normalized)
              < cos(15 * Double.pi / 180)
            {
              angularBaseline = true
            }
          }
        }
        if angularBaseline {patches[i].supported=true;patches[i].positions=[]}
      }
    }
    for patch in patches {
        report.sampledPatches += 1
        report.observedArea += patch.area
        if patch.supported {
          report.supportedPatches += 1
          report.supportedArea += patch.area
        } else if patch.lowQuality {
          report.poorQuality += 1
        } else if patch.noDepth {
          report.missingDepth += 1
        } else {
          report.insufficientViews += 1
        }
    }
    return report
  }
}
struct CoveragePage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var reports: [CoverageReport] = []
  var body: some View {
    List {
      Section {
        Text(
          "This checks photo support on surfaces already observed by LiDAR. It cannot certify unseen wall cavities, the far side of pipes, or completeness of an entire house."
        ).font(.footnote)
        Button("Analyze saved capture coverage") {
          guard let repo = model.repository else { return }
          let snapshot = house
          model.perform("Checking angles, lighting and depth support") {
            let result = try await LocalWorker.run {
              try snapshot.segments.map {
                try CoverageAnalyzer.analyze(house: snapshot, segment: $0, repo: repo)
              }
            }
            guard model.house?.id==snapshot.id,model.house?.revision==snapshot.revision else{throw HouseError.message("Capture changed; run coverage analysis again.")}
            reports = result
            return nil
          }
        }.disabled(model.busy)
      }
      BoundaryCoveragePanel(house:house)
      ForEach(reports, id: \.segmentID) { r in
        Section(
          house.segments.first(where: { $0.id == r.segmentID })?.started.formatted() ?? "Session"
        ) {
          if r.sampledPatches == 0 {
            Text(
              "No observed triangle mesh to evaluate. Photo count alone cannot establish coverage.")
          } else {
            ProgressView(value: r.fraction)
            Text(
              "\(Int(r.fraction*100))% of sampled observed surface has three separated, well-lit views"
            )
            Text("Unsampled and unseen areas remain unverified.").font(.footnote)
            Text(
              "Insufficient views or angles: \(r.insufficientViews)\nLow quality, uncertain depth or grazing angle: \(r.poorQuality)\nMissing depth support: \(r.missingDepth)"
            ).font(.caption)
            Text(
              "Sampled observed area: \(r.observedArea.formatted(.number.precision(.fractionLength(1)))) m² · source revision \(r.revision)"
            ).font(.caption)
          }
        }
      }
      Section("Before walls close") {
        Text(
          "Revisit dark and occluded cavities from both sides. Photograph endpoints, junction boxes, wire labels and pipe transitions. Include a measured reference and keep an independent archive. Finish with a human review of each wall and ceiling."
        ).font(.footnote)
      }
    }.navigationTitle("Capture coverage").onChange(of:house.revision){_,_ in reports=[]}
      .onChange(of:house.id){_,_ in reports=[]}
  }
}
