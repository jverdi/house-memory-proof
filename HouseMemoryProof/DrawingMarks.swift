import Foundation

enum DrawingMarkKind:String,Codable,CaseIterable {case roomName="Room name",boundary="Possible boundary"}
enum DrawingMarkMethod:String,Codable {case manual,visionText,visionRectangle}

// Page coordinates are normalized against the unrotated crop box, top-left
// origin. Neither a room label nor a closed outline establishes a 3D room.
struct DrawingMark:Codable,Identifiable,Equatable {
  var id=UUID();var sourceAsset:String;var page:Int;var kind:DrawingMarkKind
  var points:[UV];var label:String;var reviewed=false
  var method:DrawingMarkMethod = .manual
  var originalPoints:[UV]?=nil;var originalLabel:String?=nil
  var profileHash:String?=nil;var runtime:String?=nil;var rawScore:Double?=nil
  static let profileHash="9f858468f850556e2d7799d6389e839e53bf6c16ef58e5af5d3c92e85893dc36"
  static func bounded(_ text:String)->Bool {text.utf8.count<=4096 && !text.contains("\0")}
  private func validShape(_ points:[UV])->Bool {
    let shape:ImageAnnotationKind=kind == .roomName ? .box:.polygon
    guard points.count<=128,ImageAnnotation(kind:shape,points:points).valid else{return false}
    guard kind == .boundary else{return true}
    func turn(_ a:UV,_ b:UV,_ c:UV)->Double {(b.u-a.u)*(c.v-a.v)-(b.v-a.v)*(c.u-a.u)}
    func onSegment(_ a:UV,_ b:UV,_ p:UV)->Bool {
      abs(turn(a,b,p))<1e-12 && p.u>=min(a.u,b.u)-1e-12 && p.u<=max(a.u,b.u)+1e-12 && p.v>=min(a.v,b.v)-1e-12 && p.v<=max(a.v,b.v)+1e-12
    }
    for i in points.indices {for j in points.indices where j>i+1 && !(i==0 && j==points.count-1) {
      let a=points[i],b=points[(i+1)%points.count],c=points[j],d=points[(j+1)%points.count]
      if turn(a,b,c)*turn(a,b,d)<0 && turn(c,d,a)*turn(c,d,b)<0 {return false}
      if onSegment(a,b,c) || onSegment(a,b,d) || onSegment(c,d,a) || onSegment(c,d,b) {return false}
    }}
    return true
  }
  var valid:Bool {
    guard page>=0,page<10000,sourceAsset.count<=100,sourceAsset.rangeOfCharacter(from:.whitespacesAndNewlines)==nil,
      sourceAsset.range(of:"^[0-9a-f]{64}\\.[A-Za-z0-9]+$",options:.regularExpression) != nil,
      Self.bounded(label),validShape(points),rawScore.map({$0.isFinite && (0...1).contains($0)}) ?? true else{return false}
    if method == .manual {return originalPoints==nil && originalLabel==nil && profileHash==nil && runtime==nil && rawScore==nil}
    guard let originalPoints,let originalLabel,let runtime,!runtime.isEmpty,
      validShape(originalPoints),Self.bounded(originalLabel),Self.bounded(runtime),
      profileHash==Self.profileHash,rawScore != nil else{return false}
    return method == .visionText ? kind == .roomName:kind == .boundary
  }
  func current(for drawing:Drawing)->Bool {sourceAsset==drawing.asset}
  var annotation:ImageAnnotation {
    ImageAnnotation(id:id,kind:kind == .roomName ? .box:.polygon,points:points,label:label,reviewed:reviewed)
  }
}

enum DrawingMarkEdits {
  static func saving(_ marks:[DrawingMark],source:Drawing,to house:House)throws->House {
    guard let index=house.drawings.firstIndex(where:{$0.id==source.id}),
      house.drawings[index].asset==source.asset,house.drawings[index].marks==source.marks else {
      throw HouseError.message("The source drawing or its marks changed. Reopen the page before saving.")
    }
    var updated=house;updated.drawings[index].marks=marks
    try updated.validate();return updated
  }
}

#if canImport(UIKit)
import Vision
import UIKit

enum DrawingSuggestions {
  static func detect(_ image:CGImage,sourceAsset:String,page:Int)throws->[DrawingMark] {
    guard image.width<=2048,image.height<=2048,image.width>0,image.height>0 else {
      throw HouseError.message("Use a drawing preview no larger than 2,048 pixels per side.")
    }
    try Task.checkCancellation()
    let text=VNRecognizeTextRequest();text.revision=VNRecognizeTextRequestRevision3
    text.recognitionLevel = .accurate;text.usesLanguageCorrection=false;text.recognitionLanguages=["en-US"]
    text.minimumTextHeight=0.015
    let rectangles=VNDetectRectanglesRequest();rectangles.revision=VNDetectRectanglesRequestRevision1
    rectangles.maximumObservations=16;rectangles.minimumSize=0.05
    rectangles.minimumAspectRatio=0.1;rectangles.maximumAspectRatio=1
    rectangles.quadratureTolerance=15;rectangles.minimumConfidence=0.5
    try VNImageRequestHandler(cgImage:image,orientation:.up,options:[:]).perform([text,rectangles])
    try Task.checkCancellation()
    let runtime=ProcessInfo.processInfo.operatingSystemVersionString
    func point(_ value:CGPoint)->UV {UV(u:Double(value.x),v:1-Double(value.y))}
    func mark(_ kind:DrawingMarkKind,_ points:[UV],_ label:String,_ method:DrawingMarkMethod,_ score:Float)->DrawingMark {
      DrawingMark(sourceAsset:sourceAsset,page:page,kind:kind,points:points,label:label,method:method,
        originalPoints:points,originalLabel:label,profileHash:DrawingMark.profileHash,runtime:runtime,rawScore:Double(score))
    }
    var result:[DrawingMark]=[]
    for observation in (text.results ?? []).prefix(200) {
      guard let candidate=observation.topCandidates(1).first else{continue}
      let box=observation.boundingBox
      let value=mark(.roomName,[point(CGPoint(x:box.minX,y:box.maxY)),point(CGPoint(x:box.maxX,y:box.minY))],candidate.string,.visionText,candidate.confidence)
      if value.valid {result.append(value)}
    }
    for observation in (rectangles.results ?? []).prefix(16) {
      let points=[observation.topLeft,observation.topRight,observation.bottomRight,observation.bottomLeft].map(point)
      let value=mark(.boundary,points,"Possible boundary",.visionRectangle,observation.confidence)
      if value.valid {result.append(value)}
    }
    return result
  }
}
#if DEBUG
enum DrawingMarkTestFixture {
  static func pdf()->Data {
    UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:900,height:650)).pdfData{context in
      context.beginPage();UIColor.white.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:900,height:650))
      UIColor.black.setStroke();context.cgContext.setLineWidth(8)
      context.cgContext.stroke(CGRect(x:70,y:70,width:330,height:480))
      context.cgContext.stroke(CGRect(x:490,y:70,width:330,height:480))
      let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:36,weight:.bold),.foregroundColor:UIColor.black]
      ("ROOM A" as NSString).draw(at:CGPoint(x:145,y:260),withAttributes:attributes)
      ("ROOM B" as NSString).draw(at:CGPoint(x:565,y:260),withAttributes:attributes)
    }
  }
}
#endif
#endif
