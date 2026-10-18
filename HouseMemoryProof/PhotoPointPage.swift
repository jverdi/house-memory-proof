import SwiftUI
import ImageIO

struct PhotoPointPage:View {
  @EnvironmentObject var model:AppModel
  var house:House
  @State private var segmentID:UUID?
  @State private var selected:[UUID?]=[nil,nil,nil]
  @State private var controls:[PhotoControl?]=[nil,nil,nil]
  @State private var name="Photo-located point"
  @State private var trade:Trade = .unknown
  @State private var saved=""
  @State private var curveMode=false
  @State private var samples:[[PhotoControl]]=[]
  @State private var intervalsVisible=false
  var observations:[Observation]{house.observations.filter{$0.segmentID==segmentID && $0.spatialPoseEligible}}
  var body:some View {Form{
    Text("Locate a small visible feature without trusting background LiDAR depth. Select the same point in three translated photographs. The first two fit the point; the third independently checks it. Results remain approximate. Photographs use their original sensor orientation.").font(.footnote)
    Toggle("Trace a visible curve",isOn:$curveMode)
    Picker("Capture segment",selection:$segmentID){Text("Choose").tag(UUID?.none);ForEach(house.segments){s in Text(s.started.formatted()).accessibilityIdentifier("point-segment-choice").tag(Optional(s.id))}}
    .accessibilityIdentifier("point-segment-picker")
    ForEach(0..<3,id:\.self){index in
      Section(index==2 ? "3 · Independent check":"\(index+1) · Fitting view"){
        Picker("Photograph",selection:$selected[index]){Text("Choose").tag(UUID?.none);ForEach(Array(observations.enumerated()),id:\.element.id){index,o in Text("Photo \(index+1) · \(o.date.formatted(date:.omitted,time:.standard))").accessibilityIdentifier("point-photo-choice-\(index)").tag(Optional(o.id))}}
        .accessibilityIdentifier("point-photo-picker-\(index)")
        if let id=selected[index],let observation=observations.first(where:{$0.id==id}),let url=try? model.repository?.assetURL(observation.image){
          PhotoPointSurface(url:url,control:controls[index]){u,v in controls[index]=PhotoControl(observationID:id,u:u,v:v)}.frame(height:280).accessibilityIdentifier("point-image-\(index)").id(id)
          Text(controls[index]==nil ? "Tap the exact feature; pinch to zoom first.":"Point selected. Tap to adjust.").font(.caption)
        }
      }
    }
    TextField("Label",text:$name)
    Picker("System",selection:$trade){ForEach(Trade.allCases){Text($0.rawValue).tag($0)}}
    if curveMode {
      Button("Check and add curve point"){
        do {
          guard let segment=house.segments.first(where:{$0.id==segmentID}),samples.count<128 else{throw HouseError.message("Select a session; curves are limited to 128 checked points.")}
          let chosen=controls.compactMap{$0};_=try PhotoTriangulation.locate(chosen,house:house,segment:segment)
          samples.append(chosen);controls=[nil,nil,nil];intervalsVisible=false;saved=""
        }catch{model.error=error.localizedDescription}
      }.disabled(controls.contains(where:{$0==nil}) || samples.count>=128)
      Text("\(samples.count) checked curve points · diameter and uncertainty unknown").font(.caption)
      Button("Clear point selections"){controls=[nil,nil,nil]}.disabled(controls.allSatisfy{$0==nil})
      Button("Undo curve point"){if !samples.isEmpty{samples.removeLast();intervalsVisible=false}}.disabled(samples.isEmpty)
      Toggle("Every joining interval is visible in the source photos",isOn:$intervalsVisible)
      Text("Finish one visible section before starting another. A crossing never creates a connection.").font(.caption)
      if !saved.isEmpty {Text(saved).font(.footnote).foregroundStyle(.mint)}
      Button("Save photo-traced curve"){
        do {
          guard model.house?.id==house.id,model.house?.revision==house.revision,let segment=house.segments.first(where:{$0.id==segmentID}) else{throw HouseError.message("Project changed. Reopen this tool and repeat the selections.")}
          let feature=try PhotoTriangulation.curve(samples,house:house,segment:segment,name:name=="Photo-located point" ? "Photo-traced curve":name,trade:trade,visibleIntervalsConfirmed:intervalsVisible)
          if model.edit(projectID:house.id,{$0.features.append(feature)}) {saved="Saved \(feature.name) with \(samples.count) independently checked source tracks.";samples=[];intervalsVisible=false}
        }catch{model.error=error.localizedDescription}
      }.disabled(samples.count<2 || !intervalsVisible || controls.contains(where:{$0 != nil}))
    }else {
      if !saved.isEmpty {Text(saved).font(.footnote).foregroundStyle(.mint)}
      Button("Check and save point"){
      do {
        guard let segment=house.segments.first(where:{$0.id==segmentID}),controls.compactMap({$0}).count==3 else{throw HouseError.message("Select three photograph points first.")}
        guard model.house?.id==house.id,model.house?.revision==house.revision else{throw HouseError.message("Project changed. Reopen this tool and repeat the selections.")}
        let chosen=controls.compactMap{$0},point=try PhotoTriangulation.locate(chosen,house:house,segment:segment)
        let feature=Feature(name:name.isEmpty ? "Photo-located point":name,trade:trade,roomID:segment.roomID,stageID:segment.stageID,kind:house.isDemo ? .synthetic:.observed,mesh:Mesh(vertices:[point],triangles:[]),route:[point],sourceIDs:chosen.map{$0.observationID},notes:"Manually identified point; two fitting photos and one independent reprojection check. No validated physical accuracy or inferred service thickness.",segmentID:segment.id,sourceFingerprint:try VisualMapping.fingerprint(house:house,segment:segment),photoControls:chosen)
        if model.edit(projectID:house.id,{$0.features.append(feature)}) {saved="Saved \(feature.name) with three source photographs.";controls=[nil,nil,nil]}
      }catch{model.error=error.localizedDescription}
    }.disabled(controls.contains(where:{$0==nil}))}
  }.navigationTitle(curveMode ? "Photo curve":"Photo point")
    .toolbar {
      ToolbarItem(placement:.topBarTrailing) {
        Button(curveMode ? "Locate a point":"Trace a curve"){curveMode.toggle()}
          .accessibilityIdentifier("photo-mode-action")
      }
    }
    .onChange(of:curveMode){_,_ in
      samples=[];controls=[nil,nil,nil];intervalsVisible=false;saved=""
      if curveMode && name=="Photo-located point"{name="Photo-traced curve"}
      if !curveMode && name=="Photo-traced curve"{name="Photo-located point"}
    }
    .onChange(of:segmentID){_,_ in selected=[nil,nil,nil];controls=[nil,nil,nil];samples=[];intervalsVisible=false;saved=""}.onChange(of:selected){old,new in for i in 0..<3 where old[i] != new[i]{controls[i]=nil}}}
}
struct PhotoPointSurface:UIViewRepresentable {
  var url:URL
  var control:PhotoControl?
  var select:(Double,Double)->Void
  func makeUIView(context:Context)->PointScrollView{
    let view=PointScrollView();view.select=select
    if let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:false] as CFDictionary){view.imageView.image=UIImage(cgImage:cg)}
    return view
  }
  func updateUIView(_ view:PointScrollView,context:Context){view.select=select;view.point=control.map{CGPoint(x:$0.u,y:$0.v)};view.setNeedsLayout()}
}
final class PointScrollView:UIScrollView,UIScrollViewDelegate {
  let imageView=UIImageView();let marker=CAShapeLayer();var select:((Double,Double)->Void)?;var point:CGPoint?
  init(){super.init(frame:.zero);minimumZoomScale=1;maximumZoomScale=10;delegate=self;backgroundColor = .black;imageView.contentMode = .scaleAspectFit;imageView.isUserInteractionEnabled=true;addSubview(imageView);imageView.layer.addSublayer(marker);marker.strokeColor=UIColor.systemYellow.cgColor;marker.fillColor=UIColor.clear.cgColor;marker.lineWidth=2;imageView.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tap(_:))))}
  required init?(coder:NSCoder){fatalError("Not used")}
  func rect()->CGRect{guard let image=imageView.image else{return .zero};let scale=min(imageView.bounds.width/image.size.width,imageView.bounds.height/image.size.height);let size=CGSize(width:image.size.width*scale,height:image.size.height*scale);return CGRect(x:(imageView.bounds.width-size.width)/2,y:(imageView.bounds.height-size.height)/2,width:size.width,height:size.height)}
  override func layoutSubviews(){super.layoutSubviews();if zoomScale==1{imageView.frame=bounds;contentSize=bounds.size};let r=rect();if let p=point{let x=r.minX+p.x*r.width,y=r.minY+p.y*r.height;marker.path=UIBezierPath(ovalIn:CGRect(x:x-5,y:y-5,width:10,height:10)).cgPath}else{marker.path=nil}}
  func viewForZooming(in scrollView:UIScrollView)->UIView?{imageView}
  @objc func tap(_ gesture:UITapGestureRecognizer){let p=gesture.location(in:imageView),r=rect();guard r.width>0,r.contains(p) else{return};select?(Double((p.x-r.minX)/r.width),Double((p.y-r.minY)/r.height))}
}
