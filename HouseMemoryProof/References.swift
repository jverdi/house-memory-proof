import ARKit
import CryptoKit
import SwiftUI

@MainActor enum BoardGenerator {
  static func make(name: String, repo: Repository,tagID:Int?=nil,roomID:UUID?=nil) throws -> ReferenceBoard {
    let id = UUID()
    let seed = Array(SHA256.hash(data: Data(id.uuidString.utf8)))
    var tagPixels:[UInt8]?=nil
    if let tagID {
      guard (0..<587).contains(tagID) else{throw HouseError.message("Coded reference ID is out of range.")}
      var cells=[UInt8](repeating:0,count:100)
      guard cells.withUnsafeMutableBufferPointer({hx_tag_image(UInt32(tagID),$0.baseAddress,100)})==10 else{throw HouseError.message("Coded reference could not be rendered.")}
      tagPixels=cells
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 720), format: format).image
    { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 720))
      if let cells=tagPixels {
        for y in 0..<10 {for x in 0..<10 {
          (cells[y*10+x]==0 ? UIColor.black:UIColor.white).setFill()
          ctx.fill(CGRect(x:x*72,y:y*72,width:72,height:72))
        }}
        return
      }
      UIColor.black.setStroke()
      ctx.cgContext.setLineWidth(12)
      ctx.cgContext.stroke(CGRect(x: 8, y: 8, width: 704, height: 704))
      for y in 0..<18 {
        for x in 0..<18 {
          let value = seed[(x + y * 18) % seed.count] ^ UInt8(truncatingIfNeeded: x * 31 + y * 17)
          let size = CGFloat(10 + Int(value) % 23)
          let px = CGFloat(x * 37 + 22)
          let py = CGFloat(y * 37 + 22)
          UIColor(white: CGFloat(value % 4) / 6, alpha: 1).setFill()
          if value & 1 == 0 {
            ctx.cgContext.fillEllipse(in: CGRect(x: px, y: py, width: size, height: size))
          } else {
            ctx.fill(CGRect(x: px, y: py, width: size, height: size))
          }
        }
      }
      (String(id.uuidString.prefix(8)) as NSString).draw(
        at: CGPoint(x: 200, y: 330),
        withAttributes: [
          .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .black),
          .foregroundColor: UIColor.black, .backgroundColor: UIColor.white,
        ])
    }
    guard let png = image.pngData() else {
      throw HouseError.message("Could not render reference image.")
    }
    let key = try repo.put(png, ext: "png")
    let width = 0.18
    let points = width / 0.0254 * 72
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData {
      ctx in
      ctx.beginPage()
      ("House Xray reference · " + name as NSString).draw(
        at: CGPoint(x: 30, y: 26),
        withAttributes: [.font: UIFont.systemFont(ofSize: 16, weight: .bold)])
      image.draw(in: CGRect(x: 42, y: 90, width: points, height: points))
      let instructions =
        "Print at 100% / actual size. The outer image must measure 180 mm wide. Measure the physical print and enter its actual width. Mount flat on stable structure that remains accessible after finishing. Never move a registered board; mark it invalid if moved. Image tracking is approximate and is not a surveyed precision reference.\n\nID: \(id.uuidString)"
      let coded=tagID.map{"\nAprilTag 36h11 code \($0). Black border: 144 mm at 180 mm outer width. Keep the white margin visible. Capture oblique views separated by at least 15 cm. Use four or more distributed fixed boards at different depths; placement remains uncalibrated."} ?? ""
      ((instructions+coded) as NSString).draw(
        in: CGRect(x: 30, y: 640, width: 535, height: 180),
        withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
    }
    let pdfKey = try repo.put(pdf, ext: "pdf")
    return ReferenceBoard(id: id, name: name, image: key, pdf: pdfKey, width: width,tagID:tagID,roomID:roomID)
  }
  static func images(_ h: House, repo: Repository) async -> Set<ARReferenceImage> {
    var result = Set<ARReferenceImage>()
    for board in h.references.filter({ $0.valid }).prefix(20) {
      guard board.width > 0.03, board.width < 2, let data = try? repo.read(board.image),
        let cg = UIImage(data: data)?.cgImage
      else { continue }
      let reference = ARReferenceImage(cg, orientation: .up, physicalWidth: CGFloat(board.width))
      reference.name = board.id.uuidString
      do {
        try await reference.validate()
        result.insert(reference)
      } catch { continue }
    }
    return result
  }
}
struct ReferencesPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var name = "Reference 1"
  @State private var creating = false
  @State private var selectedRoom:UUID?
  struct Placement {var count:Int;var assessment:ReferenceLayout.Assessment}
  @State private var placements:[UUID:Placement]=[:]
  var body: some View {
    List {
      Section {
        Text(
          "Print references at actual size, measure the outer image, and keep them flat and fixed. Record each coded board in at least two sharp views separated by 15 cm. For the coded alignment path, keep at least four well-distributed boards visible together. These are uncalibrated references; disagreement hides alignment."
        ).font(.footnote)
        TextField("Board name", text: $name)
        Picker("Reference room",selection:$selectedRoom) {
          Text("Shared between rooms").tag(UUID?.none)
          ForEach(house.rooms){room in Text(room.name).tag(Optional(room.id))}
        }
        Button("Create coded reference") {
          guard let repo=model.repository else{return}
          let used=Set(house.references.compactMap{$0.tagID}),start=Int.random(in:0..<587)
          guard let code=(0..<587).map({($0+start)%587}).first(where:{!used.contains($0)}) else{model.error="All reference codes are already reserved in this house.";return}
          do {
            let board=try BoardGenerator.make(name:name,repo:repo,tagID:code,roomID:selectedRoom)
            model.edit{$0.references.append(board)};model.shareURL=try repo.assetURL(board.pdf)
          }catch{model.error=error.localizedDescription}
        }
        Text("Coded references estimate board geometry from their measured size and detected corners. Capture oblique views to resolve planar ambiguity. Multiple boards and translated views must agree; fitting alone does not establish physical accuracy.").font(.footnote)
        Button("Create legacy image reference") {
          guard let repo = model.repository else { return }
          do {
            let board = try BoardGenerator.make(name: name, repo: repo,roomID:selectedRoom)
            model.edit { $0.references.append(board) }
            model.shareURL = try repo.assetURL(board.pdf)
          } catch { model.error = error.localizedDescription }
        }
      }
      Section {
        Text("For a rough-in to finished-stage handoff, retain distinct fixed references where they remain visible after drywall. Stagger their horizontal positions and heights across two walls; two straight columns may still form a nearly flat layout. Six targets can cover upper, middle and lower viewing regions. Capture translated overlapping views in both stages and check the recorded layout below.").font(.footnote)
      }
      Section("Recorded reference placement") {
        ForEach(house.segments.filter{!$0.referencePoses.isEmpty || (placements[$0.id]?.count ?? 0)>0}) {segment in
          VStack(alignment:.leading,spacing:6) {
            Text(house.rooms.first{$0.id==segment.roomID}?.name ?? "Capture")
            if let placement=placements[segment.id] {
            let assessment=placement.assessment
            Text("\(assessment.count) fixed references · \(segment.started.formatted())").font(.caption)
            Text(assessment.advice).font(.footnote).foregroundStyle(assessment.distributed ? .mint:.orange)
            Text("\(placement.count) coded boards have matching corner evidence in translated views").font(.caption)
            }else{ProgressView("Checking saved reference views…")}
          }
        }
      }
      ForEach(house.references) { board in
        NavigationLink(board.name) { ReferenceEditor(board: board) }
      }
    }.navigationTitle("References")
      .task(id:house.revision) {
        let snapshot=house
        do {
          let result=try await LocalWorker.run { () throws -> [UUID:Placement] in
            var result:[UUID:Placement]=[:]
            for segment in snapshot.segments {
              try Task.checkCancellation()
              let poses=ReferenceRegistration.currentPoses(segment:segment,house:snapshot)
              let centres=poses.map{p in V3(p.matrix[3],-p.matrix[11],p.matrix[7])}
              result[segment.id]=Placement(count:poses.filter{$0.method=="coded-corners"}.count,assessment:ReferenceLayout.assess(centres))
            }
            return result
          }
          guard !Task.isCancelled else{return};placements=result
        }catch is CancellationError {}catch {model.error=error.localizedDescription}
      }
  }
}
struct ReferenceEditor: View {
  @EnvironmentObject var model: AppModel
  @State var board: ReferenceBoard
  var body: some View {
    Form {
      TextField("Name", text: $board.name)
      Picker("Reference room",selection:$board.roomID) {
        Text("Shared between rooms").tag(UUID?.none)
        ForEach(model.house?.rooms ?? []){room in Text(room.name).tag(Optional(room.id))}
      }
      if let code=board.tagID {Text("AprilTag 36h11 · \(code)");Text("Width below measures the full image including the white margin; the black border spans 80% of that width.").font(.footnote)}
      TextField("Measured print width in metres", value: $board.width, format: .number)
        .keyboardType(.decimalPad)
      TextField("Mounting location", text: $board.location, axis: .vertical)
      Toggle("Still fixed in its original location", isOn: $board.valid)
      Button("Share printable PDF") {
        if let url = try? model.repository?.assetURL(board.pdf) { model.shareURL = url }
      }
      Button("Save reference") {
        model.edit { h in
          if let i = h.references.firstIndex(where: { $0.id == board.id }) {
            let changed = h.references[i].width != board.width || !board.valid
            h.references[i] = board
            if changed {
              for j in h.segments.indices {
                let affected = h.segments[j].referencePoses.contains { $0.boardID == board.id }
                h.segments[j].referencePoses.removeAll { $0.boardID == board.id }
                h.segments[j].approved = false
                if affected {
                  let sid = h.segments[j].id
                  for k in h.features.indices where h.features[k].segmentID == sid {
                    if !h.features[k].sourceIDs.isEmpty {
                      h.features[k].artifactValid = false
                      h.features[k].hidden = true
                    } else if h.features[k].resolvedGeometrySource == .capturedMesh {
                      h.features[k].hidden = false
                    }
                  }
                }
              }
            }
          }
        }
      }
      Text(
        "Changing its size or marking it moved removes previous pose associations. No precision claim is retained."
      ).font(.footnote)
    }.navigationTitle(board.name)
  }
}
