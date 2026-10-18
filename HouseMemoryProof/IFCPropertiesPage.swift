import SwiftUI

struct IFCPropertiesPage:View {
  @EnvironmentObject var model:AppModel
  let reference:IFCPropertyReference
  var initialExpressID:Int?=nil
  struct Record:Identifiable {var id:Int;var name:String;var text:String}
  @State private var rows:[Record]=[]
  @State private var query=""
  @State private var error=""
  var matching:[Record] {query.isEmpty ? rows:rows.filter{String($0.id).contains(query) || $0.name.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query)}}
  var body:some View {
    List {
      Section {
        Text("Documentary source values in original units. Geometry and owner-history graphs remain in the original IFC. These properties do not identify observed construction.").font(.caption)
        Text(reference.summary.description).font(.caption)
      }
      if !error.isEmpty {Text(error).foregroundStyle(.red)}
      Section("\(matching.count) matching records · showing up to 200") {
        ForEach(Array(matching.prefix(200))) {record in
          NavigationLink("#\(record.id) · \(record.name)") {
            ScrollView {Text(record.text).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding().accessibilityIdentifier("ifc-property-record-values")}.navigationTitle("#\(record.id)")
          }.accessibilityIdentifier("ifc-property-record-\(record.id)")
        }
      }
    }.navigationTitle("IFC source properties").searchable(text:$query,prompt:"EXPRESS ID, type or value").task {
      guard let repo=model.repository else{return}
      if let initialExpressID {query=String(initialExpressID)}
      do {
        rows=try await LocalWorker.run {
          let verified=try IFCProperties.read(reference,repo:repo)
          guard let root=try JSONSerialization.jsonObject(with:verified.data) as? [String:Any],let records=root["records"] as? [[String:Any]] else{throw HouseError.message("IFC records are unavailable.")}
          return try records.map{row in
            guard let id=IFCProperties.integer(row["expressID"]),let name=row["typeName"] as? String else{throw HouseError.message("IFC record identity is unavailable.")}
            return Record(id:id,name:name,text:String(decoding:try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys,.prettyPrinted]),as:UTF8.self))
          }
        }
      }catch {self.error=error.localizedDescription}
    }
  }
}
