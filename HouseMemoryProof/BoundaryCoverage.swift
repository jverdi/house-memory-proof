import Foundation
import simd
import SwiftUI

enum BoundaryCoverageAdvice:String,Codable {
  case visit,depth,illuminate,steady,closer,translate,aroundObstruction,verifyPlane,review
  var message:String {
    switch self {
    case .visit:return "This patch has no sampled view. Photograph it from an accessible viewpoint."
    case .depth:return "This patch lacks reliable, time-compatible depth. Revisit it with stable tracking and check depth support."
    case .illuminate:return "Add light to this patch, then capture overlapping views again."
    case .steady:return "Pause for a sharper image, then capture overlapping views again."
    case .closer:return "Capture more detail from a closer viewpoint. This test concerns the nominal plane, not small-service completeness."
    case .translate:return "Add sideways-separated views with a wider angle on this patch. Rotating in place does not add a baseline."
    case .aroundObstruction:return "A foreground surface blocks this plane. Look for another accessible viewing angle; blocked areas remain unverified."
    case .verifyPlane:return "Depth does not match the entered plane. Recheck its depth and source geometry before adding views."
    case .review:return "The nominal plane has sampled photo/depth support. Review labels, endpoints and hidden details separately."
    }
  }
}
struct BoundaryCoverageCell {
  var projectedViews=0,matchingDepthViews=0,occludedViews=0,unmatchedDepthViews=0
  var unavailableDepthViews=0,uncertainDepthViews=0,darkViews=0,blurredViews=0,lowSamplingViews=0,grazingViews=0
  var usefulViews=0,separatedViews=0,angularBaseline=false
  var supported:Bool {separatedViews>=3 && angularBaseline}
  // Same display states as before; evidence dimensions remain separate.
  var state:Int {supported ? 2:matchingDepthViews>0 ? 1:occludedViews>0 ? 3:0}
  var advice:BoundaryCoverageAdvice {
    if supported{return .review}
    if projectedViews==0{return .visit}
    if matchingDepthViews==0 {
      if occludedViews>0{return .aroundObstruction}
      if unavailableDepthViews>0 || uncertainDepthViews>0{return .depth}
      return .verifyPlane
    }
    if usefulViews<3 {
      if darkViews>0{return .illuminate}
      if blurredViews>0{return .steady}
      if lowSamplingViews>0{return .closer}
    }
    return .translate
  }
}
struct BoundaryCoverageReport {
  var boundary:RevealBoundary;var revision:Int;var columns:Int;var rows:Int;var cells:[BoundaryCoverageCell];var cameraCount:Int;var consideredCameraCount:Int
  var states:[Int] {cells.map{$0.state}}
  var supported:Int {cells.filter{$0.supported}.count}
}
enum BoundaryCoverage {
  static func analyze(house:House,boundary:RevealBoundary,repo:Repository)throws->BoundaryCoverageReport {
    guard RevealVolumes.current(boundary,house:house),let source=house.segments.first(where:{$0.id==boundary.segmentID}) else{throw HouseError.message("Boundary inputs changed. Define the wall volume again.")}
    let adapter=PoseRefinement.matrix([1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1])!
    var observations:[Observation]=[]
    for segment in house.segments where segment.roomID==source.roomID && segment.stageID==source.stageID {
      var conversion=matrix_identity_double4x4
      if segment.id != source.id {
        guard let a=source.registration.flatMap({PoseRefinement.matrix($0.values)}),let b=segment.registration.flatMap({PoseRefinement.matrix($0.values)}) else{continue}
        conversion=simd_inverse(adapter)*simd_inverse(a)*b*adapter
      }
      // Retain pose-eligible photographs for missing-depth diagnostics. They
      // never count as metric support without compatible depth/confidence.
      let raw=house.observations.filter{$0.segmentID==segment.id && $0.spatialPoseEligible}
      observations += PoseRefinement.selected(raw,segment:segment,house:house).0.map{o in var changed=o;changed.camera=PoseRefinement.array(conversion*PoseRefinement.matrix(o.camera)!);return changed}
    }
    let selected=VisualMapping.keyframes(observations,limit:120)
    let columns=min(64,max(1,Int(ceil(boundary.width/0.1)))),rows=min(64,max(1,Int(ceil(boundary.height/0.1))))
    let points=(0..<(columns*rows)).map{index->V3 in
      boundary.origin+boundary.horizontal*(boundary.width*(Double(index%columns)+0.5)/Double(columns))+boundary.vertical*(boundary.height*(Double(index/columns)+0.5)/Double(rows))+boundary.normal*boundary.depth
    }
    var cells=[BoundaryCoverageCell](repeating:BoundaryCoverageCell(),count:points.count),positions=[[V3]](repeating:[],count:points.count)
    // Stream one original depth/confidence pair at a time. Count all sampled
    // views even after support is reached, so occlusion/quality stay visible.
    for o in selected {
      try Task.checkCancellation()
      let dimensions=o.metricDepthEligible && o.depthWidth>0 && o.depthHeight>0 && o.depthWidth<=1_000_000/o.depthHeight
      let count=dimensions ? o.depthWidth*o.depthHeight:0
      let data:Data?,confidence:Data?
      if dimensions {data=try repo.read(o.depth!,limit:count*4);confidence=try o.confidence.map{try repo.read($0,limit:count)}}
      else {data=nil;confidence=nil}
      let m=o.camera,position=V3(m[3],-m[11],m[7])
      guard boundary.viewedFromFront(position) else{continue}
      for i in points.indices {
        if i%64==0 {try Task.checkCancellation()}
        let p=points[i]
        guard let (uv,z)=TextureBuilder.project(p,through:o) else{continue}
        cells[i].projectedViews+=1
        // Photo quality and nominal sampling are independent of whether a
        // usable depth sample exists. Count both faults when both are present.
        let dark = !o.light.isFinite || o.light<150,blurred = !o.sharpness.isFinite || o.sharpness<0.02
        let lowSampling = !(o.intrinsics[0]/z>=120),grazing = !(abs(boundary.normal.dot((position-p).normalized))>0.35)
        if dark{cells[i].darkViews+=1};if blurred{cells[i].blurredViews+=1};if lowSampling{cells[i].lowSamplingViews+=1};if grazing{cells[i].grazingViews+=1}
        guard dimensions,let data,data.count==count*4,let confidence,confidence.count==count else{cells[i].unavailableDepthViews+=1;continue}
        let ix=min(o.depthWidth-1,Int(uv.u*Double(o.depthWidth))),iy=min(o.depthHeight-1,Int(uv.v*Double(o.depthHeight))),index=iy*o.depthWidth+ix
        guard confidence[index]==2 else{cells[i].uncertainDepthViews+=1;continue}
        let measured=Double(Float(bitPattern:data.uint32(index*4)))
        guard measured.isFinite,measured>0 else{cells[i].unavailableDepthViews+=1;continue}
        if measured<z-0.03 {cells[i].occludedViews+=1;continue}
        guard abs(measured-z)<=0.03 else{cells[i].unmatchedDepthViews+=1;continue}
        cells[i].matchingDepthViews+=1
        guard !dark,!blurred,!lowSampling,!grazing else{continue}
        cells[i].usefulViews+=1
        guard !cells[i].supported,positions[i].allSatisfy({($0-position).length>=0.12}) else{continue}
        positions[i].append(position);cells[i].separatedViews=positions[i].count
        if positions[i].count>=3 {
          for a in positions[i].indices {for b in positions[i].indices where b>a {if (positions[i][a]-p).normalized.dot((positions[i][b]-p).normalized)<cos(15*Double.pi/180) {cells[i].angularBaseline=true}}}
          if cells[i].supported {positions[i]=[]}
        }
      }
    }
    return BoundaryCoverageReport(boundary:boundary,revision:house.revision,columns:columns,rows:rows,cells:cells,cameraCount:selected.filter{$0.metricDepthEligible}.count,consideredCameraCount:selected.count)
  }
}
struct BoundaryCoveragePanel:View {
  @EnvironmentObject var model:AppModel
  var house:House
  @State private var selection:UUID?
  @State private var report:BoundaryCoverageReport?
  @State private var selectedCell:Int?
  let colors:[Color]=[.gray,.orange,.mint,.red]
  var body:some View {
    Section("Wall and ceiling gap map") {
      Picker("Boundary",selection:$selection){Text("Choose").tag(Optional<UUID>.none);ForEach(house.boundaries){Text($0.name).tag(Optional($0.id))}}
      Button("Check nominal cavity back plane") {
        guard let repo=model.repository,let boundary=house.boundaries.first(where:{$0.id==selection}) else{return};let snapshot=house
        model.perform("Checking wall coverage and occlusion") {
          let result=try await LocalWorker.run{try BoundaryCoverage.analyze(house:snapshot,boundary:boundary,repo:repo)}
          guard selection==boundary.id else{return nil}
          guard model.house?.id==snapshot.id,model.house?.revision==snapshot.revision else{throw HouseError.message("Capture changed; run boundary coverage again.")};report=result;selectedCell=nil;return nil
        }
      }.disabled(model.busy || selection==nil)
      if let r=report {
        GeometryReader {proxy in
          Canvas {context,size in
            let w=size.width/Double(r.columns),h=size.height/Double(r.rows)
            for y in 0..<r.rows {for x in 0..<r.columns {let rect=CGRect(x:Double(x)*w,y:Double(r.rows-1-y)*h,width:max(1,w-1),height:max(1,h-1));context.fill(Path(rect),with:.color(colors[r.cells[y*r.columns+x].state]))}}
          }.gesture(SpatialTapGesture().onEnded{value in let x=min(r.columns-1,max(0,Int(value.location.x/proxy.size.width*Double(r.columns)))),y=min(r.rows-1,max(0,r.rows-1-Int(value.location.y/proxy.size.height*Double(r.rows))));selectedCell=y*r.columns+x})
        }.frame(height:220).accessibilityLabel("Coverage heat map: \(r.supported) of \(r.cells.count) nominal back-plane patches have support")
        Text("\(r.supported)/\(r.cells.count) patches supported · \(r.cameraCount)/\(r.consideredCameraCount) sampled views have compatible depth").font(.caption)
        Text("Mint: three good angles · orange: revisit · red: foreground obstruction · gray: unknown or depth mismatch. Height increases upward; width increases rightward.").font(.caption)
        Button("Show next gap") {
          let start=(selectedCell.map{$0+1} ?? 0)%r.cells.count
          selectedCell=(0..<r.cells.count).map{($0+start)%r.cells.count}.first{!r.cells[$0].supported}
        }.disabled(r.supported==r.cells.count)
        if let i=selectedCell {
          let cell=r.cells[i]
          Text("Selected patch: column \(i%r.columns+1), row \(i/r.columns+1). \(cell.advice.message)").font(.footnote)
          Text("\(cell.projectedViews) projected views · \(cell.matchingDepthViews) matching depth · \(cell.usefulViews) useful views · \(cell.separatedViews) separated views").font(.caption)
          Text("Foreground obstruction: \(cell.occludedViews) · depth unavailable: \(cell.unavailableDepthViews) · depth uncertain: \(cell.uncertainDepthViews) · depth mismatch: \(cell.unmatchedDepthViews)").font(.caption)
          Text("Dark: \(cell.darkViews) · blurred: \(cell.blurredViews) · low sampling: \(cell.lowSamplingViews) · grazing angle: \(cell.grazingViews)").font(.caption)
        }
        if r.revision != house.revision {Text("Project changed since this report; analyze again.").foregroundStyle(.orange)}
      }
      Text("The denominator is the selected rectangle at the entered cavity depth, including unseen areas. A 3 cm depth agreement is a coverage diagnostic, not accuracy qualification or proof that the cavity is empty. Incorrect depth or occluded services remain unknown.").font(.footnote)
    }.onChange(of:house.revision){_,_ in report=nil;selectedCell=nil}
      .onChange(of:house.id){_,_ in report=nil;selectedCell=nil;selection=nil}
      .onChange(of:selection){_,_ in report=nil;selectedCell=nil}
  }
}
