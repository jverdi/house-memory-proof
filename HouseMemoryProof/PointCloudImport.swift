import Foundation
import CryptoKit

enum ImportedUnit:String,Codable,CaseIterable {
  case metres="Metres",millimetres="Millimetres",centimetres="Centimetres",feet="Feet",inches="Inches"
  var metresPerUnit:Double {switch self {case .metres:return 1;case .millimetres:return 0.001;case .centimetres:return 0.01;case .feet:return 0.3048;case .inches:return 0.0254}}
}
enum ImportedAxis:String,Codable,CaseIterable {case zUp="Z up",yUp="Y up"}
struct ImportedCoordinateDeclaration:Codable,Equatable {var unit:ImportedUnit;var upright:ImportedAxis}
struct PointCloudImport:Identifiable {
  let id=UUID()
  var projectID:UUID;var drawing:Drawing;var mesh:Mesh
  static func fingerprint(_ drawing:Drawing,declaration:ImportedCoordinateDeclaration)throws->String {
    struct Inputs:Encodable {var asset:String;var declaration:ImportedCoordinateDeclaration}
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    return SHA256.hash(data:try encoder.encode(Inputs(asset:drawing.asset,declaration:declaration))).map{String(format:"%02x",$0)}.joined()
  }
  func applying(unit:ImportedUnit?,upright:ImportedAxis?,roomID:UUID,to house:House)throws->House {
    guard house.id==projectID,house.drawings.contains(drawing),house.rooms.contains(where:{$0.id==roomID}) else{throw HouseError.message("The project or source changed. Reopen the original before importing geometry.")}
    guard !house.features.contains(where:{$0.id==id}) else{throw HouseError.message("This point-cloud import is already saved.")}
    guard let unit,let upright else{throw HouseError.message("Choose the original's units and upright axis. The original remains saved without spatial placement.")}
    var transformed=mesh
    transformed.vertices=mesh.vertices.map{point in
      let p=point*unit.metresPerUnit
      return upright == .zUp ? p:V3(p.x,-p.z,p.y)
    }
    guard !transformed.vertices.isEmpty,transformed.valid else{throw HouseError.message("Declared coordinates exceed the supported geometry bounds. Original retained.")}
    var h=house
    let stage=Stage(name:"Imported PLY · \(drawing.name)",kind:.documentary,phase:.other)
    let segment=Segment(roomID:roomID,stageID:stage.id)
    var feature=Feature(id:id,name:URL(fileURLWithPath:drawing.name).deletingPathExtension().lastPathComponent,trade:.unknown,roomID:roomID,stageID:stage.id,kind:.documentary,mesh:transformed,
      notes:"Imported PLY. Source units: \(unit.rawValue); source upright: \(upright.rawValue). Owner-declared, not independently calibrated. Separate source frame; no house alignment inferred.",segmentID:segment.id,sourceDrawingID:drawing.id)
    feature.importedCoordinates=ImportedCoordinateDeclaration(unit:unit,upright:upright)
    feature.sourceDrawingFingerprint=try Self.fingerprint(drawing,declaration:feature.importedCoordinates!)
    h.stages.append(stage);h.segments.append(segment);h.features.append(feature)
    try h.validate();return h
  }
}

#if canImport(UIKit)
import SwiftUI
struct PointCloudImportPage:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.dismiss) private var dismiss
  let candidate:PointCloudImport
  @State private var unit:ImportedUnit?
  @State private var upright:ImportedAxis?
  @State private var roomID:UUID?
  private var house:House? {model.houses.first(where:{$0.id==candidate.projectID})}
  var body:some View {
    NavigationStack {
      Form {
        Section {
          Text(candidate.drawing.name)
          Text("The original is saved in Drawings & design references. Choose its units and upright axis to add geometry. Leave unknown details unset to keep the source without spatial placement.").font(.footnote)
        }
        Picker("Original units",selection:$unit) {
          Text("Unknown").tag(Optional<ImportedUnit>.none)
          ForEach(ImportedUnit.allCases,id:\.self){Text($0.rawValue).tag(Optional($0))}
        }.accessibilityIdentifier("point-cloud-units")
        Picker("Original upright axis",selection:$upright) {
          Text("Unknown").tag(Optional<ImportedAxis>.none)
          ForEach(ImportedAxis.allCases,id:\.self){Text($0.rawValue).tag(Optional($0))}
        }.accessibilityIdentifier("point-cloud-upright")
        Picker("Room association",selection:$roomID) {
          Text("Choose room").tag(Optional<UUID>.none)
          ForEach(house?.rooms ?? []){Text($0.name).tag(Optional($0.id))}
        }.accessibilityIdentifier("point-cloud-room")
        Text("\(candidate.mesh.vertices.count) points · \(candidate.mesh.triangles.count/3) triangles. Geometry stays in a separate source frame until you align it. Room association alone does not establish alignment or accuracy.").font(.footnote)
        Text("After importing, choose its Imported PLY stage in Explore → Layers.").font(.footnote)
        Button("Import declared geometry") {
          guard let house,let roomID else{return}
          do{let updated=try candidate.applying(unit:unit,upright:upright,roomID:roomID,to:house);if model.commit(updated,select:false){dismiss()}}
          catch{model.error=error.localizedDescription}
        }.disabled(unit==nil || upright==nil || roomID==nil || model.busy)
      }.navigationTitle("Point-cloud coordinates")
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Keep source only"){dismiss()}}}
    }
  }
}
#endif
