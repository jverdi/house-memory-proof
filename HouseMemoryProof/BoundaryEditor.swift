import SwiftUI
import simd

struct BoundaryEditor:View {
  @EnvironmentObject var model:AppModel
  @Environment(\.dismiss) var dismiss
  var house:House;var segment:Segment;var points:[V3];var cameraPosition:V3
  @State private var name="Wall section"
  @State private var depth=0.20
  @State private var finish=0.0125
  @State private var flip=false
  @State private var error=""
  var body:some View {
    NavigationStack {
      Form {
        Section("Selected rectangle") {
          Text("The first point is a corner, the second sets the horizontal edge, and the third sets the other edge. The cavity points away from your current viewpoint by default. Reverse it only if you selected the opposite side.").font(.footnote)
          TextField("Name",text:$name)
          if let boundary=try? make() {
            Text("\(boundary.width.formatted(.number.precision(.fractionLength(2)))) × \(boundary.height.formatted(.number.precision(.fractionLength(2)))) m")
            Text("Into-cavity direction: \(boundary.normal.x.formatted(.number.precision(.fractionLength(2)))), \(boundary.normal.y.formatted(.number.precision(.fractionLength(2)))), \(boundary.normal.z.formatted(.number.precision(.fractionLength(2))))").font(.caption)
          }
          Toggle("Reverse cavity direction",isOn:$flip)
        }
        Section("Measured construction depth") {
          Stepper("Cavity depth: \(Int((depth*1000).rounded())) mm",value:$depth,in:0.01...1,step:0.01)
          Stepper("Finish offset toward camera: \(Int((finish*1000).rounded())) mm",value:$finish,in:0...0.2,step:0.0025)
          Text("These values define a display volume. They do not measure or validate hidden services. Use the actual wall or ceiling assembly dimensions.").font(.footnote)
        }
        if !error.isEmpty {Text(error).foregroundStyle(.red)}
        Button("Save reveal boundary") {
          do {let b=try make();if model.edit(projectID:house.id,{$0.boundaries.append(b)}) {dismiss()}}
          catch {self.error=error.localizedDescription}
        }
      }.navigationTitle("Wall or ceiling").toolbar {Button("Cancel"){dismiss()}}
    }
  }
  private func make()throws->RevealBoundary {
    guard points.count==3 else{throw HouseError.message("Select exactly three corners.")}
    let inverse=segment.registration.flatMap{PoseRefinement.matrix($0.values)}.map{Rigid(values:PoseRefinement.array(simd_inverse($0)))} ?? Rigid()
    let p=points.map{inverse.apply($0)};let x=(p[1]-p[0]).normalized;var y=(p[2]-p[0])-x*x.dot(p[2]-p[0]);let height=y.length;y=y.normalized
    let towardCamera=x.cross(y).dot(inverse.apply(cameraPosition)-p[0])>0
    var origin=p[0];if towardCamera != flip {origin=origin+y*height;y=y * -1}
    let b=RevealBoundary(name:name.isEmpty ? "Wall section":name,segmentID:segment.id,origin:origin,horizontal:x,vertical:y,width:(p[1]-p[0]).length,height:height,depth:depth,finishOffset:finish,sourceFingerprint:try VisualMapping.fingerprint(house:house,segment:segment))
    guard b.valid else{throw HouseError.message("Choose three separated, non-collinear corners on the same wall or ceiling plane.")};return b
  }
}
