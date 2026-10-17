import PDFKit
import SwiftUI

struct DrawingAlignmentPage: View {
  @EnvironmentObject var model: AppModel
  @Binding var drawing: Drawing
  var document: PDFDocument
  @State private var points: [CGPoint] = []
  @State private var page = 0
  @State private var target = ""
  @State private var room: UUID?
  @State private var report = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          "Place this design sheet in the house frame. Tap four identifiable points on one page: three to fit, then a separate point to check. Enter corresponding HOUSE coordinates in metres, not an unregistered session's coordinates. This remains an approximate design overlay."
        )
        .font(.footnote)
        PDFSurface(document: document, points: $points, selectedPage: $page, maximumPoints: 4)
          .frame(height: 320).background(.white)
        Text("Page \(page + 1) · \(points.count)/4 points, in tap order")
        ForEach(Array(points.enumerated()), id: \.offset) { i, p in
          Text(
            "\(i + 1): \(Double(p.x).formatted(.number.precision(.fractionLength(1)))), \(Double(p.y).formatted(.number.precision(.fractionLength(1)))) PDF points"
          )
          .font(.caption.monospacedDigit())
        }
        Button("Reset sheet points") { points = [] }
        Picker("Room", selection: $room) {
          Text("Choose room").tag(UUID?.none)
          ForEach(model.house?.rooms ?? []) { Text($0.name).tag(Optional($0.id)) }
        }
        Text("Corresponding house points: x,y,z per line")
        TextEditor(text: $target).frame(height: 120).border(.secondary.opacity(0.3))
        Button("Check and create design overlay", action: publish)
          .buttonStyle(.borderedProminent)
          .disabled(points.count != 4 || room == nil || drawing.metresPerPoint == nil)
        Text(report).font(.footnote)
        Text(
          "Scale must first be calibrated on this page. A matching four-point check does not establish that the rest of a design drawing matches construction. Changing the source scale invalidates the previous overlay."
        )
        .font(.caption).foregroundStyle(.secondary)
      }.padding()
    }.navigationTitle("Align design sheet")
      .onAppear {
        page = drawing.page
        room = drawing.roomID ?? model.house?.rooms.first?.id
      }
  }

  private func publish() {
    do {
      guard let house = model.house, let repo = model.repository, let room,
        let scale = drawing.metresPerPoint, scale.isFinite, scale > 0,
        page == drawing.page, let sheet = document.page(at: page)
      else {
        throw HouseError.message("Calibrate the selected page's scale first, and choose its room.")
      }
      let source = points.map { V3(Double($0.x) * scale, Double($0.y) * scale, 0) }
      let targets = try CheckedRegistration.coordinates(target)
      let (transform, fit, check) = try CheckedRegistration.fit(source: source, target: targets)
      let bounds = sheet.bounds(for: .cropBox)
      guard bounds.width > 0, bounds.height > 0 else {
        throw HouseError.message("The source page has no usable bounds.")
      }
      let image = try DrawingTexture.normalizedThumbnail(sheet)
      guard let bytes = image.jpegData(compressionQuality: 0.95) else {
        throw HouseError.message("Unable to render the source page.")
      }
      let texture = try repo.put(bytes, ext: "jpg")
      let corners = [
        CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
        CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
      ]
      let mesh = Mesh(
        vertices: corners.map {
          transform.apply(V3(Double($0.x) * scale, Double($0.y) * scale, 0))
        }, triangles: [0, 1, 2, 0, 2, 3])
      let stage =
        house.stages.first(where: { $0.name == "Aligned design sheets" && $0.kind == .planned })
        ?? Stage(name: "Aligned design sheets", kind: .planned)
      var feature = Feature(
        name: drawing.name + " · page \(page + 1)", trade: .unknown, roomID: room,
        stageID: stage.id, kind: .planned, mesh: mesh)
      feature.texture = texture
      feature.uv = [UV(u: 0, v: 1), UV(u: 1, v: 1), UV(u: 1, v: 0), UV(u: 0, v: 0)]
      feature.sourceDrawingID = drawing.id
      feature.notes =
        "Approximate design overlay. Fit maximum \(fit) m; independent check maximum \(check) m. Source revision \(house.revision). Not observed geometry."
      drawing.roomID = room
      drawing.alignment = DrawingAlignment(
        page: page, metresPerPoint: scale, sheetPoints: source, housePoints: targets,
        transform: transform, fitMaximum: fit, checkMaximum: check, sourceRevision: house.revision)
      let updated = drawing
      model.edit { h in
        if !h.stages.contains(where: { $0.id == stage.id }) { h.stages.append(stage) }
        for i in h.features.indices where h.features[i].sourceDrawingID == drawing.id {
          h.features[i].artifactValid = false
        }
        h.features.append(feature)
        if let i = h.drawings.firstIndex(where: { $0.id == updated.id }) { h.drawings[i] = updated }
      }
      report =
        "Saved approximate design overlay. Select Aligned design sheets in Explore's stage filter. Independent check: \((check * 1000).formatted()) mm."
    } catch { model.error = error.localizedDescription }
  }
}

@MainActor enum DrawingTexture {
  static func normalizedThumbnail(_ page:PDFPage,maximumDimension:CGFloat=2048)throws->UIImage {
    guard maximumDimension>=64,maximumDimension<=2048,let copy=page.copy() as? PDFPage else{throw HouseError.message("Unable to prepare a drawing texture.")}
    // PDFView converts taps into unrotated page coordinates. Render a private
    // zero-rotation copy in that same frame; keep the original PDF untouched.
    copy.rotation=0
    let bounds=copy.bounds(for:.cropBox)
    guard bounds.width.isFinite,bounds.height.isFinite,bounds.width>0,bounds.height>0 else{throw HouseError.message("The drawing has invalid page bounds.")}
    let image=copy.thumbnail(of:CGSize(width:maximumDimension,height:maximumDimension),for:.cropBox)
    guard let cg=image.cgImage,cg.width>0,cg.height>0,cg.width*cg.height<=40_000_000 else{throw HouseError.message("Drawing preview exceeds its raster budget.")}
    let ratio=min(1,maximumDimension/CGFloat(max(cg.width,cg.height)))
    let size=CGSize(width:CGFloat(cg.width)*ratio,height:CGFloat(cg.height)*ratio)
    let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
    return UIGraphicsImageRenderer(size:size,format:format).image{_ in image.draw(in:CGRect(origin:.zero,size:size))}
  }
}
