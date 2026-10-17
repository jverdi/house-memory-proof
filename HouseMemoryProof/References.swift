import ARKit
import CryptoKit
import SwiftUI

@MainActor enum BoardGenerator {
  static func make(name: String, repo: Repository) throws -> ReferenceBoard {
    let id = UUID()
    let seed = Array(SHA256.hash(data: Data(id.uuidString.utf8)))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 720), format: format).image
    { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 720))
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
      (instructions as NSString).draw(
        in: CGRect(x: 30, y: 640, width: 535, height: 180),
        withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
    }
    let pdfKey = try repo.put(pdf, ext: "pdf")
    return ReferenceBoard(id: id, name: name, image: key, pdf: pdfKey, width: width)
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
  var body: some View {
    List {
      Section {
        Text(
          "Printable image references can help recover a session after construction changes. They are approximate ARKit image targets, not AprilTag survey boards. Print at actual size, measure the print, and keep it flat and fixed. Keep at least two different boards visible together for approximate drift constraints; disagreement rejects the correction."
        ).font(.footnote)
        TextField("Board name", text: $name)
        Button("Create printable reference") {
          guard let repo = model.repository else { return }
          do {
            let board = try BoardGenerator.make(name: name, repo: repo)
            model.edit { $0.references.append(board) }
            model.shareURL = try repo.assetURL(board.pdf)
          } catch { model.error = error.localizedDescription }
        }
      }
      ForEach(house.references) { board in
        NavigationLink(board.name) { ReferenceEditor(board: board) }
      }
    }.navigationTitle("References")
  }
}
struct ReferenceEditor: View {
  @EnvironmentObject var model: AppModel
  @State var board: ReferenceBoard
  var body: some View {
    Form {
      TextField("Name", text: $board.name)
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
                    } else if h.features[k].name == "Observed LiDAR surface" {
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
