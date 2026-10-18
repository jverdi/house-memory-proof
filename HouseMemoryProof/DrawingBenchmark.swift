import Foundation
import UIKit
import CryptoKit

// Analytic development observations of the shipped Vision fallback. This is not
// a trained symbol detector, a protected benchmark or a real-plan qualification.
@MainActor enum DrawingBenchmark {
  struct Expected {var category:String;var size:String;var box:CGRect;var text:String?}
  static func run()throws->[String:Any] {
    let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
    var cases:[[String:Any]]=[]
    func normalize(_ text:String)->String {text.uppercased().split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")}
    func bounds(_ mark:DrawingMark)->CGRect {
      let xs=mark.points.map{$0.u},ys=mark.points.map{$0.v}
      return CGRect(x:(xs.min() ?? 0)*900,y:(ys.min() ?? 0)*650,width:((xs.max() ?? 0)-(xs.min() ?? 0))*900,height:((ys.max() ?? 0)-(ys.min() ?? 0))*650)
    }
    for index in 0..<11 {
      try Task.checkCancellation()
      let positive=index<8,small=index%2==0,gray=(index/2)%2==1,serif=(index/4)%2==1
      let textSize:CGFloat=small ? 18:36
      let font=serif ? (UIFont(name:"TimesNewRomanPSMT",size:textSize) ?? UIFont.systemFont(ofSize:textSize)):UIFont.systemFont(ofSize:textSize,weight:.medium)
      var truth:[Expected]=[]
      let renderer=UIGraphicsImageRenderer(size:CGSize(width:900,height:650),format:format)
      let image=renderer.image { context in
        UIColor.white.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:900,height:650))
        let color=UIColor(white:gray ? 0.6:0,alpha:1)
        let attributes:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color]
        if positive {
          context.cgContext.setStrokeColor(color.cgColor);context.cgContext.setLineWidth(small ? 3:6)
          for (number,x) in [CGFloat(70),CGFloat(490)].enumerated() {
            let rect=CGRect(x:x,y:70,width:small ? 200:330,height:small ? 280:480)
            context.cgContext.stroke(rect)
            truth.append(Expected(category:"rectangular-outline",size:small ? "small":"large",box:rect,text:nil))
            let label=number==0 ? "ROOM A":"ROOM B"
            let size=(label as NSString).size(withAttributes:attributes)
            let box=CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height)
            (label as NSString).draw(at:box.origin,withAttributes:attributes)
            truth.append(Expected(category:"room-name-text",size:small ? "18px":"36px",box:box.insetBy(dx:-4,dy:-4),text:label))
          }
          let text="CAT6 A12",point=CGPoint(x:70,y:590),size=(text as NSString).size(withAttributes:attributes)
          (text as NSString).draw(at:point,withAttributes:attributes)
          truth.append(Expected(category:"service-label-text",size:small ? "18px":"36px",box:CGRect(origin:point,size:size).insetBy(dx:-4,dy:-4),text:text))
        }else if index==9 {
          context.cgContext.setStrokeColor(UIColor.black.cgColor);context.cgContext.setLineWidth(3)
          for i in 0..<6 {context.cgContext.move(to:CGPoint(x:80,y:100+i*70));context.cgContext.addLine(to:CGPoint(x:700,y:110+i*70));context.cgContext.strokePath()}
        }else if index==10 {
          context.cgContext.setStrokeColor(UIColor.black.cgColor);context.cgContext.setLineWidth(5)
          for x in [CGFloat(150),CGFloat(450),CGFloat(700)] {context.cgContext.strokeEllipse(in:CGRect(x:x,y:200,width:100,height:100))}
        }
      }
      guard let cg=image.cgImage,let bytes=image.pngData() else{throw HouseError.message("Drawing benchmark raster unavailable.")}
      let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
      let start=ProcessInfo.processInfo.systemUptime
      let proposals=try DrawingSuggestions.detect(cg,sourceAsset:hash+".png",page:0)
      let seconds=ProcessInfo.processInfo.systemUptime-start
      guard proposals.allSatisfy({$0.valid && !$0.reviewed && $0.profileHash==DrawingMark.profileHash}) else{throw HouseError.message("A drawing benchmark proposal lost its review/provenance contract.")}
      var used=Set<Int>(),counts:[String:[String:Int]]=[:]
      for expected in truth {
        let key=expected.category+"/"+expected.size
        var row=counts[key] ?? ["truth":0,"matched":0,"falsePositive":0]
        row["truth",default:0] += 1
        let matched=proposals.indices.first { i in
          guard !used.contains(i) else{return false}
          let prediction=proposals[i],box=bounds(prediction)
          if let text=expected.text {
            return prediction.kind == .roomName && normalize(prediction.label)==text && expected.box.contains(CGPoint(x:box.midX,y:box.midY))
          }
          guard prediction.kind == .boundary else{return false}
          let intersection=box.intersection(expected.box),overlap=intersection.isNull ? 0:intersection.width*intersection.height
          let union=box.width*box.height+expected.box.width*expected.box.height-overlap
          return union>0 && overlap/union>=0.75
        }
        if let matched{used.insert(matched);row["matched",default:0] += 1}
        counts[key]=row
      }
      // Text has no semantic classifier. Unmatched text is reported in its own
      // size bin, not silently assigned to a known class or discarded.
      for i in proposals.indices where !used.contains(i) {
        let mark=proposals[i],box=bounds(mark)
        let category=mark.kind == .boundary ? "rectangular-outline":"unmatched-text"
        let size=mark.kind == .boundary ? (box.width<260 ? "small":"large"):(box.height<24 ? "18px":"36px")
        let key=category+"/"+size
        var row=counts[key] ?? ["truth":0,"matched":0,"falsePositive":0]
        row["falsePositive",default:0] += 1;counts[key]=row
      }
      func boxValues(_ box:CGRect)->[Double] {[Double(box.minX),Double(box.minY),Double(box.maxX),Double(box.maxY)]}
      let expectedRows:[[String:Any]]=truth.map{["category":$0.category,"size":$0.size,"box":boxValues($0.box),"text":$0.text.map{$0 as Any} ?? NSNull()]}
      let predictionRows:[[String:Any]]=proposals.map{["kind":$0.kind.rawValue,"box":boxValues(bounds($0)),"label":$0.label,"reviewed":$0.reviewed]}
      cases.append(["case":index,"kind":positive ? "analytic-plan":index==8 ? "blank":index==9 ? "open-lines":"circles",
        "font":font.fontName,"textPixels":Int(textSize),"inkGray":gray ? 0.6:0,"imageSHA256":hash,"seconds":seconds,
        "proposals":proposals.count,"truth":expectedRows,"predictions":predictionRows,"counts":counts,"allUnreviewed":true])
    }
    return ["schema":1,"executionPassed":true,"profileHash":DrawingMark.profileHash,"runtime":ProcessInfo.processInfo.operatingSystemVersionString,
      "cases":cases,"physicalQualification":false,"protectedBenchmark":false,"semanticClassifierAvailable":false,
      "accuracyQualified":false,"textMatching":"exact normalized text plus truth-box centroid; unmatched text pooled separately because OCR has no semantic class",
      "boundaryMatching":"one-to-one rectangle IoU >= 0.75","limitations":"Eleven analytic development rasters, two font families, two text sizes and two contrasts, plus blank/open-line/circle negatives. Reports the unmodified shipping OCR/rectangle fallback. No learned detector, real scanned plans, thermal or physical qualification."]
  }
}
