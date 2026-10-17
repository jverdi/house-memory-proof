import Foundation

enum ArchiveViewer {
  static func html(_ house:House)throws->Data {
    guard let template=Bundle.main.url(forResource:"archive-viewer",withExtension:"html",subdirectory:"IFC") else{throw HouseError.message("Offline viewer template is missing.")}
    let options=SceneOptions(mode:.evidence,ceilings:true)
    let features=Exporter.canonicalFeatures(house,options:options)
    let allowance=max(24,300000/max(1,features.count));var simplified=false
    var output:[[String:Any]]=[]
    for f in features where !f.mesh.vertices.isEmpty {
      try Task.checkCancellation()
      var vertices:[Double]=[],triangles:[Int]=[]
      if f.mesh.triangles.isEmpty {
        let step=max(1,Int(ceil(Double(f.mesh.vertices.count)/Double(allowance))))
        simplified = simplified || step>1
        for i in stride(from:0,to:f.mesh.vertices.count,by:step) {let p=f.mesh.vertices[i];vertices += [p.x,p.z,-p.y]}
      } else {
        let faces=f.mesh.triangles.count/3,step=max(1,Int(ceil(Double(faces*3)/Double(allowance))))
        simplified = simplified || step>1
        for face in stride(from:0,to:faces,by:step) {for offset in 0..<3 {let p=f.mesh.vertices[Int(f.mesh.triangles[face*3+offset])];triangles.append(vertices.count/3);vertices += [p.x,p.z,-p.y]}}
      }
      let c=f.trade.hex
      output.append(["name":f.name,"stage":f.stageID.uuidString,"trade":f.trade.rawValue,"vertices":vertices,"triangles":triangles,"color":[Double((c>>16)&255)/255,Double((c>>8)&255)/255,Double(c&255)/255]])
    }
    let frame=SceneBuilder.activeUnregisteredSegment(house,options:options)
    let data=try JSONSerialization.data(withJSONObject:["name":house.name,"features":output,"stages":house.stages.map{["id":$0.id.uuidString,"name":$0.name]},"trades":Trade.allCases.map{["id":$0.rawValue,"name":$0.rawValue]},"simplified":simplified,"frameLabel":frame.map{"Capture frame "+String($0.uuidString.prefix(8))} ?? "Registered house frame"])
    let html=try String(contentsOf:template,encoding:.utf8).replacingOccurrences(of:"__HOUSE_MODEL__",with:data.base64EncodedString())
    return Data(html.utf8)
  }
}
