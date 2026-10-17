import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

enum PhotoOrientation {static func ui(_ value:Int)->UIImage.Orientation {switch value{case 3:return .down;case 6:return .right;case 8:return .left;default:return .up}}}
struct DocumentaryPhotosPage:View {
    @EnvironmentObject var model:AppModel;var house:House
    @State private var selected:[PhotosPickerItem]=[];@State private var photo:DocumentaryPhoto?
    var body:some View{List{
        Section{PhotosPicker(selection:$selected,maxSelectionCount:100,matching:.images,preferredItemEncoding:.current){Label("Choose photographs",systemImage:"photo.badge.plus")}.disabled(model.busy);Text("Existing photos preserve visual evidence without inventing camera poses, depth or scale. They remain available even when they cannot contribute to reconstruction.").font(.footnote)}
        ForEach(house.documentaryPhotos.reversed()){p in Button{photo=p}label:{HStack{PhotoThumbnail(asset:p.image,orientation:1).frame(width:72,height:64).clipped();VStack(alignment:.leading){Text(p.note.isEmpty ? "Unposed photograph":p.note).lineLimit(2);Text(p.date.formatted()).font(.caption)}}}}
    }.navigationTitle("Documentary photos").sheet(item:$photo){DocumentaryPhotoDetail(photo:$0)}.onChange(of:selected){_,items in
        guard !items.isEmpty,let repo=model.repository else{return};let projectID=house.id
        model.perform("Preserving original photographs"){
            for (index,item) in items.enumerated(){guard let data=try await item.loadTransferable(type:Data.self),data.count<=100_000_000,let source=CGImageSourceCreateWithData(data as CFData,nil),let type=CGImageSourceGetType(source) else{throw HouseError.message("An image was unreadable or exceeded 100 MB. Earlier imports remain saved.")}
                let ext=UTType(type as String)?.preferredFilenameExtension ?? "img";let key=try await Task.detached{try repo.put(data,ext:ext)}.value
                guard model.house?.id==projectID else{throw HouseError.message("Project changed. Imported original remains preserved.")}
                model.edit{$0.documentaryPhotos.append(DocumentaryPhoto(image:key))};model.progress=Double(index+1)/Double(items.count)
            };selected=[];return nil
        }
    }}
}
struct DocumentaryPhotoDetail:View {
    @EnvironmentObject var model:AppModel;@Environment(\.dismiss) var dismiss
    @State var photo:DocumentaryPhoto;@State private var image:UIImage?;@State private var reading=false
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading){if let image{Image(uiImage:image).resizable().scaledToFit()};Text("Unposed original · no inferred dimensions or position").font(.caption);TextField("Notes and visible labels",text:$photo.note,axis:.vertical);if let house=model.house {Picker("Room",selection:$photo.roomID){Text("Unknown").tag(UUID?.none);ForEach(house.rooms){Text($0.name).tag(Optional($0.id))}};Picker("Stage",selection:$photo.stageID){Text("Unknown").tag(UUID?.none);ForEach(house.stages){Text($0.name).tag(Optional($0.id))}}};Button(reading ? "Reading…":"Read labels on device"){guard let image,let cg=image.cgImage else{return};reading=true;Task{defer{reading=false};do{let text=try await TextRecognition.read(cg,orientation:.up);photo.note += "\n"+text}catch{model.error=error.localizedDescription}}}.disabled(reading);Button("Share original"){model.shareURL=try? model.repository?.assetURL(photo.image)}}.padding()}.navigationTitle("Documentary evidence").toolbar{Button("Save"){model.edit{if let i=$0.documentaryPhotos.firstIndex(where:{$0.id==photo.id}){$0.documentaryPhotos[i]=photo}};dismiss()}}.task{if let url=try? model.repository?.assetURL(photo.image),let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2500] as CFDictionary){image=UIImage(cgImage:cg)}}}
}
