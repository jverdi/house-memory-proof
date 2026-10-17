import Foundation
import SwiftUI

struct CoverageReport:Codable {
    var segmentID:UUID;var revision:Int;var sampledPatches:Int;var supportedPatches:Int;var insufficientViews:Int;var poorQuality:Int;var missingDepth:Int;var observedArea:Double;var supportedArea:Double
    var fraction:Double{observedArea>0 ? supportedArea/observedArea:0}
}
enum CoverageAnalyzer {
    // Only observed mesh area is evaluated. No claim about unseen cavities or absent geometry.
    static func analyze(house:House,segment:Segment,repo:Repository)throws->CoverageReport {
        let observations=Array(house.observations.filter{$0.segmentID==segment.id && !$0.documentary}.suffix(120))
        let cameras=try observations.map{TextureBuilder.Camera(observation:$0,depth:try $0.depth.map{try repo.read($0)})}
        var report=CoverageReport(segmentID:segment.id,revision:house.revision,sampledPatches:0,supportedPatches:0,insufficientViews:0,poorQuality:0,missingDepth:0,observedArea:0,supportedArea:0)
        let surfaces=house.features.filter{$0.segmentID==segment.id && $0.name=="Observed LiDAR surface"}
        for f in surfaces {
            let strideCount=max(1,(f.mesh.triangles.count/3)/1000)
            for face in stride(from:0,to:f.mesh.triangles.count/3,by:strideCount) {
                let a=f.mesh.vertices[Int(f.mesh.triangles[face*3])],b=f.mesh.vertices[Int(f.mesh.triangles[face*3+1])],c=f.mesh.vertices[Int(f.mesh.triangles[face*3+2])]
                let cross=(b-a).cross(c-a),area=cross.length*0.5*Double(strideCount);guard area>1e-9 else{continue}
                let center=(a+b+c)*(1/3.0),normal=cross.normalized
                var positions:[V3]=[],lowQuality=false,noDepth=false
                for camera in cameras {
                    let o=camera.observation;guard let(uv,z)=TextureBuilder.project(center,through:o) else{continue}
                    if camera.depth==nil{noDepth=true;continue}
                    guard TextureBuilder.visible(uv,z:z,camera:camera) else{continue}
                    let m=o.camera,position=V3(m[3],-m[11],m[7]),ray=(position-center).normalized
                    guard abs(normal.dot(ray))>0.35,o.intrinsics[0]/z>120,o.light>=150,o.sharpness>=0.02 else{lowQuality=true;continue}
                    if positions.allSatisfy({($0-position).length>=0.12}){positions.append(position)}
                }
                var angularBaseline=false
                for i in positions.indices {for j in positions.indices where j>i {if (positions[i]-center).normalized.dot((positions[j]-center).normalized)<cos(15*Double.pi/180){angularBaseline=true}}}
                report.sampledPatches+=1;report.observedArea+=area
                if positions.count>=3 && angularBaseline{report.supportedPatches+=1;report.supportedArea+=area}
                else if lowQuality{report.poorQuality+=1}else if noDepth{report.missingDepth+=1}else{report.insufficientViews+=1}
            }
        };return report
    }
}
struct CoveragePage:View {
    @EnvironmentObject var model:AppModel;var house:House
    @State private var reports:[CoverageReport]=[]
    var body:some View{List{
        Section {Text("This checks photo support on surfaces already observed by LiDAR. It cannot certify unseen wall cavities, the far side of pipes, or completeness of an entire house.").font(.footnote);Button("Analyze saved capture coverage"){guard let repo=model.repository else{return};let snapshot=house;model.perform("Checking angles, lighting and depth support"){let result=try await Task.detached{try snapshot.segments.map{try CoverageAnalyzer.analyze(house:snapshot,segment:$0,repo:repo)}}.value;reports=result;return nil}}.disabled(model.busy)}
        ForEach(reports,id:\.segmentID){r in Section(house.segments.first(where:{$0.id==r.segmentID})?.started.formatted() ?? "Session"){
            if r.sampledPatches==0{Text("No observed triangle mesh to evaluate. Photo count alone cannot establish coverage.")}
            else{ProgressView(value:r.fraction);Text("\(Int(r.fraction*100))% of sampled observed surface has three separated, well-lit views");Text("Insufficient views or angles: \(r.insufficientViews)\nLow quality or grazing angle: \(r.poorQuality)\nMissing depth support: \(r.missingDepth)").font(.caption);Text("Estimated observed area: \(r.observedArea.formatted(.number.precision(.fractionLength(1)))) m² · source revision \(r.revision)").font(.caption)}
        }}
        Section("Before walls close"){Text("Revisit dark and occluded cavities from both sides. Photograph endpoints, junction boxes, wire labels and pipe transitions. Include a measured reference and keep an independent archive. Finish with a human review of each wall and ceiling.").font(.footnote)}
    }.navigationTitle("Capture coverage")}
}
