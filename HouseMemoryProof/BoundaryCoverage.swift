import Foundation
import simd
import SwiftUI

struct BoundaryCoverageReport {
  var boundary:RevealBoundary;var revision:Int;var columns:Int;var rows:Int;var states:[Int];var cameraCount:Int
  // 0 unknown / depth mismatch, 1 weak views, 2 supported, 3 foreground occlusion.
  var supported:Int {states.filter{$0==2}.count}
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
      let raw=house.observations.filter{$0.segmentID==segment.id && !$0.documentary && $0.depth != nil}
      observations += PoseRefinement.selected(raw,segment:segment,house:house).0.map{o in var changed=o;changed.camera=PoseRefinement.array(conversion*PoseRefinement.matrix(o.camera)!);return changed}
    }
    let selected=VisualMapping.keyframes(observations,limit:120)
    let columns=min(64,max(1,Int(ceil(boundary.width/0.1)))),rows=min(64,max(1,Int(ceil(boundary.height/0.1))))
    let points=(0..<(columns*rows)).map{index->V3 in
      boundary.origin+boundary.horizontal*(boundary.width*(Double(index%columns)+0.5)/Double(columns))+boundary.vertical*(boundary.height*(Double(index/columns)+0.5)/Double(rows))+boundary.normal*boundary.depth
    }
    var states=[Int](repeating:0,count:points.count),positions=[[V3]](repeating:[],count:points.count)
    var blocked=[Bool](repeating:false,count:points.count),weak=[Bool](repeating:false,count:points.count)
    // Stream one original depth/confidence pair at a time. A long capture must
    // not retain all camera buffers just to inspect the same wall rectangle.
    for o in selected {
      try Task.checkCancellation()
      guard o.depthWidth>0,o.depthHeight>0,o.depthWidth<=1_000_000/o.depthHeight else{continue}
      let data=try repo.read(o.depth!,limit:o.depthWidth*o.depthHeight*4)
      let confidence=try o.confidence.map{try repo.read($0,limit:o.depthWidth*o.depthHeight)},m=o.camera,position=V3(m[3],-m[11],m[7])
      guard data.count==o.depthWidth*o.depthHeight*4,let confidence,confidence.count==o.depthWidth*o.depthHeight,boundary.viewedFromFront(position) else{continue}
      for i in points.indices where states[i] != 2 {
        if i%64==0 {try Task.checkCancellation()}
        let p=points[i]
        guard let (uv,z)=TextureBuilder.project(p,through:o) else{continue}
        let ix=min(o.depthWidth-1,Int(uv.u*Double(o.depthWidth))),iy=min(o.depthHeight-1,Int(uv.v*Double(o.depthHeight))),index=iy*o.depthWidth+ix
        guard confidence[index]==2 else{continue}
        let measured=Double(Float(bitPattern:data.uint32(index*4)))
        guard measured.isFinite,measured>0 else{continue}
        if measured<z-0.03 {blocked[i]=true;continue}
        guard abs(measured-z)<=0.03 else{continue}
        weak[i]=true
        guard o.light>=150,o.sharpness>=0.02,o.intrinsics[0]/z>=120,abs(boundary.normal.dot((position-p).normalized))>0.35,positions[i].allSatisfy({($0-position).length>=0.12}) else{continue}
        positions[i].append(position)
        if positions[i].count>=3 {
          var angle=false
          for a in positions[i].indices {for b in positions[i].indices where b>a {if (positions[i][a]-p).normalized.dot((positions[i][b]-p).normalized)<cos(15*Double.pi/180) {angle=true}}}
          if angle {states[i]=2;positions[i]=[]}
        }
      }
    }
    for i in states.indices where states[i] != 2 {states[i]=weak[i] ? 1:blocked[i] ? 3:0}
    return BoundaryCoverageReport(boundary:boundary,revision:house.revision,columns:columns,rows:rows,states:states,cameraCount:selected.count)
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
          guard model.house?.id==snapshot.id,model.house?.revision==snapshot.revision else{throw HouseError.message("Capture changed; run boundary coverage again.")};report=result;selectedCell=nil;return nil
        }
      }.disabled(model.busy || selection==nil)
      if let r=report {
        GeometryReader {proxy in
          Canvas {context,size in
            let w=size.width/Double(r.columns),h=size.height/Double(r.rows)
            for y in 0..<r.rows {for x in 0..<r.columns {let rect=CGRect(x:Double(x)*w,y:Double(r.rows-1-y)*h,width:max(1,w-1),height:max(1,h-1));context.fill(Path(rect),with:.color(colors[r.states[y*r.columns+x]]))}}
          }.gesture(SpatialTapGesture().onEnded{value in let x=min(r.columns-1,max(0,Int(value.location.x/proxy.size.width*Double(r.columns)))),y=min(r.rows-1,max(0,r.rows-1-Int(value.location.y/proxy.size.height*Double(r.rows))));selectedCell=y*r.columns+x})
        }.frame(height:220).accessibilityLabel("Coverage heat map: \(r.supported) of \(r.states.count) nominal back-plane patches have support")
        Text("\(r.supported)/\(r.states.count) patches supported · \(r.cameraCount) sampled camera views").font(.caption)
        Text("Mint: three good angles · orange: revisit · red: foreground obstruction · gray: unknown or depth mismatch. Height increases upward; width increases rightward.").font(.caption)
        if let i=selectedCell {Text("Selected patch: column \(i%r.columns+1), row \(i/r.columns+1). \(["No matching depth evidence. Recheck the cavity depth and photograph this area.","Add light and wider translated views.","Nominal plane has sampled photo support; hidden details remain unverified.","A foreground surface blocks this plane. Capture around it from another angle."][r.states[i]])").font(.footnote)}
        if r.revision != house.revision {Text("Project changed since this report; analyze again.").foregroundStyle(.orange)}
      }
      Text("The denominator is the selected rectangle at the entered cavity depth, including unseen areas. A 3 cm depth agreement is a coverage diagnostic, not accuracy qualification or proof that the cavity is empty. Incorrect depth or occluded services remain unknown.").font(.footnote)
    }.onChange(of:house.revision){_,_ in report=nil;selectedCell=nil}
      .onChange(of:house.id){_,_ in report=nil;selectedCell=nil;selection=nil}
  }
}
