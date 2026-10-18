import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum PhotoOrientation {
  static func ui(_ value: Int) -> UIImage.Orientation {
    switch value {
    case 3: return .down
    case 6: return .right
    case 8: return .left
    default: return .up
    }
  }
}
struct DocumentaryPhotosPage: View {
  @EnvironmentObject var model: AppModel
  var house: House
  @State private var selected: [PhotosPickerItem] = []
  @State private var photo: DocumentaryPhoto?
  var body: some View {
    List {
      Section {
        PhotosPicker(
          selection: $selected, maxSelectionCount: 100, matching: .images,
          preferredItemEncoding: .current
        ) { Label("Choose photographs", systemImage: "photo.badge.plus") }.disabled(model.busy)
        Text(
          "Existing photos preserve visual evidence without inventing camera poses, depth or scale. They remain available even when they cannot contribute to reconstruction."
        ).font(.footnote)
      }
      ForEach(house.documentaryPhotos.reversed()) { p in
        Button {
          photo = p
        } label: {
          HStack {
            PhotoThumbnail(asset: p.image, orientation: 1).frame(width: 72, height: 64).clipped()
            VStack(alignment: .leading) {
              Text(p.note.isEmpty ? "Unposed photograph" : p.note).lineLimit(2)
              Text(p.date.formatted()).font(.caption)
            }
          }
        }
      }
    }.navigationTitle("Documentary photos").sheet(item: $photo) {
      DocumentaryPhotoDetail(photo: $0)
    }.onChange(of: selected) { _, items in
      guard !items.isEmpty, let repo = model.repository else { return }
      let projectID = house.id
      model.perform("Preserving original photographs") {
        for (index, item) in items.enumerated() {
          guard let data = try await item.loadTransferable(type: Data.self),
            data.count <= 100_000_000,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source)
          else {
            throw HouseError.message(
              "An image was unreadable or exceeded 100 MB. Earlier imports remain saved.")
          }
          let ext = UTType(type as String)?.preferredFilenameExtension ?? "img"
          let key = try await Task.detached { try repo.put(data, ext: ext) }.value
          guard model.house?.id == projectID else {
            throw HouseError.message("Project changed. Imported original remains preserved.")
          }
          model.edit { $0.documentaryPhotos.append(DocumentaryPhoto(image: key)) }
          model.progress = Double(index + 1) / Double(items.count)
        }
        selected = []
        return nil
      }
    }
  }
}
struct DocumentaryPhotoDetail: View {
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  @State var photo: DocumentaryPhoto
  @State private var image: UIImage?
  @State private var reading = false
  @State private var projectID:UUID?
  @State private var original:DocumentaryPhoto?
  @State private var kind:ImageAnnotationKind = .point
  @State private var draft:[UV]=[]
  @State private var label=""
  @State private var editingID:UUID?
  @State private var undo:[[ImageAnnotation]]=[]
  private var marks:[ImageAnnotation] {photo.annotations ?? []}
  private var candidate:ImageAnnotation {ImageAnnotation(kind:kind,points:draft,label:label)}
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading) {
          if let image {
            ImageAnnotationSurface(image:image,marks:marks.filter{$0.id != editingID},draft:candidate){point in
              guard draft.count<512 else{return}
              let maximum=kind == .point ? 1:kind == .box ? 2:512
              if draft.count>=maximum {draft=[]}
              draft.append(point)
            }.frame(height:340).accessibilityIdentifier("documentary-annotation-image")
          }
          Text("Unposed original · no inferred dimensions or position").font(.caption)
          annotationControls
          TextField("Notes and visible labels", text: $photo.note, axis: .vertical)
          if let house = model.house {
            Picker("Room", selection: $photo.roomID) {
              Text("Unknown").tag(UUID?.none)
              ForEach(house.rooms) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Stage", selection: $photo.stageID) {
              Text("Unknown").tag(UUID?.none)
              ForEach(house.stages) { Text($0.name).tag(Optional($0.id)) }
            }
          }
          Button(reading ? "Reading…" : "Read labels on device") {
            guard let image, let cg = image.cgImage else { return }
            reading = true
            Task {
              defer { reading = false }
              do {
                let text = try await TextRecognition.read(cg, orientation: .up)
                photo.note += "\n" + text
              } catch { model.error = error.localizedDescription }
            }
          }.disabled(reading)
          Button("Share original") { model.shareURL = try? model.repository?.assetURL(photo.image) }
        }.padding()
      }.navigationTitle("Documentary evidence").toolbar {
        ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
        ToolbarItem(placement:.confirmationAction){
        Button("Save") {
          guard let projectID,let current=model.houses.first(where:{$0.id==projectID}),
            current.documentaryPhotos.first(where:{$0.id==photo.id})==original else {
            model.error="This photograph changed. Reopen it before saving your edits.";return
          }
          if model.edit(projectID:projectID,{
            if let i=$0.documentaryPhotos.firstIndex(where:{$0.id==photo.id}) {$0.documentaryPhotos[i]=photo}
          }) {dismiss()}
        }.disabled(!draft.isEmpty || projectID==nil).accessibilityIdentifier("documentary-save")
        }
      }.task {
        if original==nil {original=photo;projectID=model.house?.id}
        if let url = try? model.repository?.assetURL(photo.image),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 2500,
            ] as CFDictionary)
        {
          image = UIImage(cgImage: cg)
        }
      }
    }
  }
  private var annotationControls:some View {
    VStack(alignment:.leading,spacing:12){
      Text("2D annotations").font(.headline)
      Text("Pinch to zoom, then tap the image. A box uses two opposite corners; a curve follows your taps. Add the annotation, then Save the photo. These marks describe only what is visible.").font(.caption)
      Picker("Shape",selection:Binding(get:{kind},set:{kind=$0;clearDraft()})){ForEach(ImageAnnotationKind.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
        .pickerStyle(.segmented)
      TextField("Annotation label",text:$label).accessibilityIdentifier("documentary-annotation-label")
      HStack {
        Button("Undo point"){if !draft.isEmpty{draft.removeLast()}}.disabled(draft.isEmpty)
        Button("Clear draft"){clearDraft()}.disabled(draft.isEmpty && editingID==nil)
      }.buttonStyle(.bordered)
      Button(editingID==nil ? "Add annotation":"Update annotation"){
        guard candidate.valid,marks.count<1000 || editingID != nil else{return}
        remember();var updated=marks,varMark=candidate
        if let id=editingID,let index=updated.firstIndex(where:{$0.id==id}) {varMark.id=id;updated[index]=varMark}
        else {updated.append(varMark)}
        photo.annotations=updated;clearDraft()
      }.buttonStyle(.borderedProminent).disabled(!candidate.valid || (marks.count>=1000 && editingID==nil))
        .accessibilityIdentifier("documentary-add-annotation")
      Text("\(marks.count) 2D annotations").font(.caption).accessibilityIdentifier("documentary-annotation-count")
      ForEach(marks){mark in
        VStack(alignment:.leading){
          Text(mark.label.isEmpty ? mark.kind.rawValue.capitalized:mark.label)
          Text("\(mark.kind.rawValue.capitalized) · \(mark.points.count) points · \(mark.reviewed ? "Reviewed":"Unreviewed")").font(.caption)
          HStack {
            Button("Edit"){editingID=mark.id;kind=mark.kind;draft=mark.points;label=mark.label}
              .accessibilityLabel("Edit \(mark.label.isEmpty ? mark.kind.rawValue:mark.label)")
            Button(mark.reviewed ? "Unreview":"Mark reviewed"){
              remember();photo.annotations=marks.map{var m=$0;if m.id==mark.id{m.reviewed.toggle()};return m}
            }
            Button("Delete",role:.destructive){remember();photo.annotations=marks.filter{$0.id != mark.id};if editingID==mark.id{clearDraft()}}
          }.buttonStyle(.bordered).disabled(!draft.isEmpty)
        }.padding(.vertical,4)
      }
      Button("Undo annotation edit") {if let previous=undo.popLast(){photo.annotations=previous;clearDraft()}}.disabled(undo.isEmpty)
    }
  }
  private func remember(){undo.append(marks);if undo.count>25{undo.removeFirst()}}
  private func clearDraft(){draft=[];editingID=nil;label=""}
}

struct ImageAnnotationSurface:UIViewRepresentable {
  var image:UIImage;var marks:[ImageAnnotation];var draft:ImageAnnotation;var select:(UV)->Void
  func makeUIView(context:Context)->ImageAnnotationScrollView {let view=ImageAnnotationScrollView();view.imageView.image=image;return view}
  func updateUIView(_ view:ImageAnnotationScrollView,context:Context){view.select=select;view.marks=marks;view.draft=draft;view.setNeedsLayout()}
}
final class ImageAnnotationScrollView:UIScrollView,UIScrollViewDelegate {
  let imageView=UIImageView(),saved=CAShapeLayer(),pending=CAShapeLayer()
  var marks:[ImageAnnotation]=[];var draft:ImageAnnotation?;var select:((UV)->Void)?
  init(){
    super.init(frame:.zero);minimumZoomScale=1;maximumZoomScale=10;delegate=self;backgroundColor = .black
    imageView.contentMode = .scaleAspectFit;imageView.isUserInteractionEnabled=true;addSubview(imageView)
    for (layer,color) in [(saved,UIColor.systemMint),(pending,UIColor.systemYellow)]{
      imageView.layer.addSublayer(layer);layer.strokeColor=color.cgColor;layer.fillColor=UIColor.clear.cgColor;layer.lineWidth=2
    }
    imageView.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tap(_:))))
  }
  required init?(coder:NSCoder){fatalError("Not used")}
  func imageRect()->CGRect {
    guard let image=imageView.image else{return .zero}
    let scale=min(imageView.bounds.width/image.size.width,imageView.bounds.height/image.size.height)
    let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
    return CGRect(x:(imageView.bounds.width-size.width)/2,y:(imageView.bounds.height-size.height)/2,width:size.width,height:size.height)
  }
  override func layoutSubviews(){
    super.layoutSubviews();if zoomScale==1{imageView.frame=CGRect(origin:.zero,size:bounds.size);contentSize=bounds.size}
    saved.path=path(marks).cgPath;pending.path=path(draft.map{[$0]} ?? []).cgPath
  }
  private func path(_ annotations:[ImageAnnotation])->UIBezierPath {
    let result=UIBezierPath(),rect=imageRect()
    for mark in annotations {
      let points=mark.points.map{CGPoint(x:rect.minX+$0.u*rect.width,y:rect.minY+$0.v*rect.height)}
      guard let first=points.first else{continue}
      if mark.kind == .point || points.count==1 {result.append(UIBezierPath(ovalIn:CGRect(x:first.x-4,y:first.y-4,width:8,height:8)))}
      else if mark.kind == .box {let b=points[1];result.append(UIBezierPath(rect:CGRect(x:min(first.x,b.x),y:min(first.y,b.y),width:abs(first.x-b.x),height:abs(first.y-b.y))))}
      else {result.move(to:first);for point in points.dropFirst(){result.addLine(to:point)};if mark.kind == .polygon && points.count>=3{result.close()}}
    }
    return result
  }
  func viewForZooming(in scrollView:UIScrollView)->UIView?{imageView}
  @objc func tap(_ gesture:UITapGestureRecognizer){
    let p=gesture.location(in:imageView),r=imageRect();guard r.width>0,r.height>0,r.contains(p) else{return}
    select?(UV(u:Double((p.x-r.minX)/r.width),v:Double((p.y-r.minY)/r.height)))
  }
}
