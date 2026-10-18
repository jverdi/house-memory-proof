import PDFKit
import SwiftUI

struct DrawingMarksPage:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dismiss) private var dismiss
  let drawing:Drawing
  let document:PDFDocument
  var didSave:([DrawingMark])->Void
  @State private var projectID:UUID?
  @State private var page=0
  @State private var image:UIImage?
  @State private var marks:[DrawingMark]=[]
  @State private var proposals:[DrawingMark]=[]
  @State private var draft:[UV]=[]
  @State private var kind:DrawingMarkKind = .roomName
  @State private var label=""
  @State private var editing:DrawingMark?
  @State private var undo:[[DrawingMark]]=[]
  @State private var running=false
  @State private var worker:Task<Void,Never>?
  @State private var status=""
  @State private var initialized=false
  @State private var proposalsExpanded=true
  private var visible:[DrawingMark] {marks.filter{$0.page==page && $0.current(for:drawing)}}
  private var candidate:DrawingMark {
    var value=editing ?? DrawingMark(sourceAsset:drawing.asset,page:page,kind:kind,points:[],label:"")
    value.points=draft;value.label=label;value.reviewed=false;return value
  }
  var body:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:14) {
        Text("Read room labels and propose rectangular outlines on this design sheet. Inspect every suggestion; titles, symbols and furniture may also be detected. These marks never create measured rooms or move captured geometry.").font(.footnote)
        Picker("Page",selection:$page){ForEach(0..<min(document.pageCount,10000),id:\.self){Text("Page \($0+1)").tag($0)}}
          .disabled(!draft.isEmpty || editing != nil || running)
        if let image {
          ImageAnnotationSurface(image:image,marks:visible.filter{$0.id != editing?.id}.map{$0.annotation}+(proposalsExpanded ? proposals.map{$0.annotation}:[]),draft:candidate.annotation){point in
            let maximum=kind == .roomName ? 2:128
            guard draft.count<maximum else{return};draft.append(point)
          }.frame(height:340).id("\(drawing.asset)-\(page)").accessibilityIdentifier("drawing-marks-image")
        }
        Text("Unrotated source page · pinch to zoom · marks use page coordinates").font(.caption)
        Button(running ? "Finding suggestions…":"Find labels and possible boundaries") {detect()}
          .disabled(running || image==nil || !draft.isEmpty || editing != nil)
          .accessibilityIdentifier("drawing-find-suggestions")
        Text("English OCR and rectangular outlines are available locally. Irregular or open boundaries need manual tracing. No high-confidence classification or room completeness is claimed.").font(.caption)
        if !status.isEmpty {Text(status).font(.footnote).accessibilityIdentifier("drawing-suggestion-status")}
        if !proposals.isEmpty {
          DisclosureGroup("Suggestions awaiting selection · \(proposals.count)",isExpanded:$proposalsExpanded) {
          ForEach(proposals){proposal in
            HStack {
              VStack(alignment:.leading){Text(proposal.label).lineLimit(3);Text(proposal.kind.rawValue+" · unreviewed").font(.caption)}
              Spacer()
              Button("Keep") {remember();marks.append(proposal);proposals.removeAll{$0.id==proposal.id};proposalsExpanded=false}
                .disabled(marks.count>=1000 || !draft.isEmpty || editing != nil)
                .accessibilityLabel("Keep \(proposal.label)")
              Button("Dismiss") {proposals.removeAll{$0.id==proposal.id}}
            }.buttonStyle(.bordered)
          }
          }
        }
        Divider()
        Text(editing==nil ? "Add a page mark":"Edit page mark").font(.headline)
        Picker("Mark type",selection:$kind){ForEach(DrawingMarkKind.allCases,id:\.self){Text($0.rawValue).tag($0)}}
          .disabled(editing != nil || !draft.isEmpty)
        Text(kind == .roomName ? "Tap two opposite corners around a room label, then enter its text.":"Tap the visible boundary corners in order. The outline closes automatically; do not bridge unknown regions.").font(.caption)
        TextField("Label",text:$label).textFieldStyle(.roundedBorder).accessibilityIdentifier("drawing-mark-label")
        HStack {
          Button("Undo point"){if !draft.isEmpty{draft.removeLast()}}.disabled(draft.isEmpty)
          Button("Clear draft"){clearDraft()}.disabled(draft.isEmpty && editing==nil)
        }.buttonStyle(.bordered)
        Button(editing==nil ? "Add page mark":"Update page mark") {
          guard candidate.valid else{return};remember()
          if let id=editing?.id,let index=marks.firstIndex(where:{$0.id==id}) {marks[index]=candidate}
          else {marks.append(candidate)}
          clearDraft()
        }.buttonStyle(.borderedProminent).disabled(!candidate.valid || (marks.count>=1000 && editing==nil))
          .accessibilityIdentifier("drawing-add-mark")
        Text("\(visible.count) page marks · \(visible.filter{$0.reviewed}.count) reviewed").font(.caption).accessibilityIdentifier("drawing-mark-count")
        ForEach(visible){mark in
          VStack(alignment:.leading,spacing:8){
            Text(mark.label.isEmpty ? mark.kind.rawValue:mark.label)
            Text(mark.kind.rawValue+" · "+(mark.reviewed ? "Reviewed":"Unreviewed")+" · "+(mark.method == .manual ? "Manual":"Suggestion retained")).font(.caption)
            if let original=mark.originalLabel,original != mark.label {Text("Original suggestion: "+original).font(.caption)}
            HStack {
              Button("Edit"){editing=mark;kind=mark.kind;label=mark.label;draft=mark.points}
              Button(mark.reviewed ? "Unreview":"Mark reviewed") {
                remember();if let index=marks.firstIndex(where:{$0.id==mark.id}) {marks[index].reviewed.toggle()}
              }.accessibilityIdentifier("drawing-review-"+mark.label)
              Button("Delete",role:.destructive){remember();marks.removeAll{$0.id==mark.id}}
            }.buttonStyle(.bordered).disabled(!draft.isEmpty || editing != nil)
          }.padding(.vertical,4)
        }
        if marks.contains(where:{!$0.current(for:drawing)}) {Text("Marks from an earlier source revision are retained but hidden. They must be rechecked against that original.").font(.footnote)}
        Button("Undo mark edit"){if let previous=undo.popLast(){marks=previous;clearDraft()}}.disabled(undo.isEmpty)
        Text("Keep stores a suggestion in this editing session. Save marks commits the session. Reviewing confirms your page annotation; it does not verify as-built dimensions.").font(.caption)
      }.padding()
    }.navigationTitle("Drawing marks").toolbar {
      ToolbarItem(placement:.confirmationAction){Button("Save marks") {save()}.disabled(!draft.isEmpty || editing != nil || running || !initialized).accessibilityIdentifier("drawing-save-marks")}
    }.task {
      guard !initialized else{return};projectID=model.house?.id;marks=drawing.marks ?? []
      page=min(max(0,drawing.page),max(0,document.pageCount-1));initialized=true;renderPage()
    }.onChange(of:page){_,_ in proposals=[];status="";clearDraft();renderPage()}
      .onDisappear{worker?.cancel();worker=nil}
      .onChange(of:scenePhase){_,phase in if phase != .active && running {worker?.cancel();status="Suggestion processing stopped. Restart it when this page is active."}}
  }
  private func renderPage(){
    do {guard let source=document.page(at:page) else{throw HouseError.message("The source page is unavailable.")};image=try DrawingTexture.normalizedThumbnail(source)}
    catch {image=nil;model.error=error.localizedDescription}
  }
  private func detect(){
    guard let cg=image?.cgImage else{return};worker?.cancel();running=true;status=""
    let sourceAsset=drawing.asset,page=page
    worker=Task {
      defer{running=false}
      do {
        let found=try await LocalWorker.run{try DrawingSuggestions.detect(cg,sourceAsset:sourceAsset,page:page)}
        try Task.checkCancellation()
        // Rerunning never modifies existing or reviewed marks.
        proposals=found.filter{candidate in !marks.contains(where:{$0.sourceAsset==candidate.sourceAsset && $0.page==candidate.page && $0.method==candidate.method && $0.originalLabel==candidate.originalLabel && $0.originalPoints==candidate.originalPoints})}
        proposalsExpanded=true
        status="\(proposals.count) suggestions to inspect. Detection is not an assertion that a room or boundary is present."
      }catch is CancellationError {}catch{if !Task.isCancelled {model.error=error.localizedDescription}}
    }
  }
  private func save(){
    do {
      guard let projectID,let house=model.houses.first(where:{$0.id==projectID}) else{throw HouseError.message("The project is no longer available.")}
      let updated=try DrawingMarkEdits.saving(marks,source:drawing,to:house)
      if model.commit(updated,select:false){didSave(marks);dismiss()}
    }catch{model.error=error.localizedDescription}
  }
  private func remember(){undo.append(marks);if undo.count>25{undo.removeFirst()}}
  private func clearDraft(){draft=[];label="";editing=nil}
}
