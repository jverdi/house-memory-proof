import Foundation
import simd

// Canonical coordinates: right handed, metres, X east, Y north, Z up.
struct V3: Codable, Hashable {
    var x: Double; var y: Double; var z: Double
    init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x=x; self.y=y; self.z=z }
    static func +(a: V3,b: V3)->V3 { V3(a.x+b.x,a.y+b.y,a.z+b.z) }
    static func -(a: V3,b: V3)->V3 { V3(a.x-b.x,a.y-b.y,a.z-b.z) }
    static func *(a: V3,b: Double)->V3 { V3(a.x*b,a.y*b,a.z*b) }
    var length: Double { sqrt(x*x+y*y+z*z) }
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var normalized: V3 { self * (1/max(length,1e-12)) }
    func dot(_ b: V3)->Double { x*b.x+y*b.y+z*b.z }
    func cross(_ b: V3)->V3 { V3(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x) }
    var render: SIMD3<Float> { SIMD3(Float(x),Float(z),Float(-y)) }
    init(ar: SIMD3<Float>) { self.init(Double(ar.x),Double(-ar.z),Double(ar.y)) }
}
struct Rigid: Codable, Equatable {
    var values: [Double] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    func apply(_ p: V3)->V3 { let m=values; return V3(m[0]*p.x+m[1]*p.y+m[2]*p.z+m[3],m[4]*p.x+m[5]*p.y+m[6]*p.z+m[7],m[8]*p.x+m[9]*p.y+m[10]*p.z+m[11]) }
    var valid: Bool {
        guard values.count == 16, values.allSatisfy({$0.isFinite}) else { return false }
        let a=V3(values[0],values[4],values[8]), b=V3(values[1],values[5],values[9]), c=V3(values[2],values[6],values[10])
        return abs(a.length-1)<0.001 && abs(b.length-1)<0.001 && abs(c.length-1)<0.001 && abs(a.dot(b))<0.001 && abs(a.cross(b).dot(c)-1)<0.001 && abs(values[12])+abs(values[13])+abs(values[14])+abs(values[15]-1)<0.001
    }
    static func register(source: [V3], target: [V3])->(Rigid,Double)? {
        guard source.count >= 3, source.count == target.count else { return nil }
        func basis(_ p:[V3])->(V3,V3,V3)? {
            let x=(p[1]-p[0]).normalized, n=x.cross(p[2]-p[0]); guard n.length>0.05 else {return nil}
            let z=n.normalized; return (x,z.cross(x),z)
        }
        guard let (sx,sy,sz)=basis(source),let (tx,ty,tz)=basis(target) else{return nil}
        let sc=[sx,sy,sz],tc=[tx,ty,tz]
        func component(_ p:V3,_ i:Int)->Double { i==0 ? p.x : i==1 ? p.y : p.z }
        var r=Rigid()
        for i in 0..<3 { for j in 0..<3 { r.values[i*4+j]=(0..<3).reduce(0){$0+component(tc[$1],i)*component(sc[$1],j)} } }
        let t=target[0]-r.apply(source[0]);r.values[3]=t.x;r.values[7]=t.y;r.values[11]=t.z
        let error=sqrt(zip(source,target).reduce(0){$0+pow((r.apply($1.0)-$1.1).length,2)}/Double(source.count))
        return r.valid ? (r,error) : nil
    }
}
enum Trade: String, Codable, CaseIterable, Identifiable {
    case structure="Structure", electrical="Electrical", lowVoltage="Low voltage", plumbing="Plumbing", hvac="HVAC", finish="Wall finish", ceiling="Ceiling", floor="Floor", unknown="Unclassified"
    var id:String {rawValue}
    var hex:UInt32 { switch self {case .structure:return 0xB58A60;case .electrical:return 0xFFBD4A;case .lowVoltage:return 0xB7A3FF;case .plumbing:return 0x56B9F2;case .hvac:return 0x7CDAC5;case .finish:return 0xD8DCD8;case .ceiling:return 0xCFD4DC;case .floor:return 0x83735C;case .unknown:return 0x92A6B7} }
}
enum EvidenceKind: String,Codable,CaseIterable { case synthetic, observed, planned, documentary }
struct Mesh: Codable, Equatable {
    var vertices:[V3]=[];var triangles:[Int32]=[]
    var valid:Bool { vertices.count<=500_000 && triangles.count<=3_000_000 && triangles.count%3==0 && vertices.allSatisfy{$0.finite && max(abs($0.x),abs($0.y),abs($0.z))<=100000} && triangles.allSatisfy{$0>=0 && Int($0)<vertices.count} }
    static func box(center c:V3,size s:V3)->Mesh {
        let v=[V3(-1,-1,-1),V3(1,-1,-1),V3(1,1,-1),V3(-1,1,-1),V3(-1,-1,1),V3(1,-1,1),V3(1,1,1),V3(-1,1,1)].map{c+V3($0.x*s.x/2,$0.y*s.y/2,$0.z*s.z/2)}
        return Mesh(vertices:v,triangles:[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7])
    }
    static func route(_ p:[V3],radius:Double)->Mesh {
        guard p.count>=2,radius.isFinite,radius>0,p.allSatisfy({$0.finite}) else{return Mesh()}
        var m=Mesh()
        for i in 1..<p.count {
            let direction=(p[i]-p[i-1]).normalized
            let u=direction.cross(abs(direction.z)<0.9 ? V3(0,0,1):V3(0,1,0)).normalized
            let v=direction.cross(u);let base=Int32(m.vertices.count)
            for end in [p[i-1],p[i]] {for j in 0..<8 {let a=Double(j)*Double.pi/4;m.vertices.append(end+(u*cos(a)+v*sin(a))*radius)}}
            for j in 0..<8 { let a=base+Int32(j), b=base+Int32((j+1)%8);m.triangles += [a,b,a+8,b,b+8,a+8] }
        }; return m
    }
}
struct Room:Codable,Identifiable,Equatable { var id=UUID();var name:String;var level:Int;var origin:V3;var size:V3;var isDesign:Bool=true }
enum ConstructionPhase:String,Codable,CaseIterable {case rough="Rough-in",finished="Finished",other="Other"}
struct Stage:Codable,Identifiable,Equatable {
    var id=UUID();var name:String;var date=Date();var kind:EvidenceKind;var phase:ConstructionPhase?=nil
    var category:ConstructionPhase {phase ?? (name.lowercased().contains("finish") ? .finished:.rough)}
}
struct AnnotationDependency:Codable,Equatable {
    var featureID:UUID;var revision:Int;var segmentID:UUID?;var registration:Rigid?
}
enum GeometrySource:String,Codable {case capturedMesh,depthPoints,depthFusion,photoTexture}
struct Feature:Codable,Identifiable,Equatable {
    var id=UUID();var name:String;var trade:Trade;var roomID:UUID;var stageID:UUID;var kind:EvidenceKind
    var mesh:Mesh;var route:[V3]=[];var sourceIDs:[UUID]=[];var notes="";var endpoint="";var reviewed=false
    var segmentID:UUID?=nil;var hidden=false;var revision=1;var texture:String?=nil;var uv:[UV]?=nil;var artifactValid:Bool?=nil;var sourceDrawingID:UUID?=nil;var sourceDrawingFingerprint:String?=nil;var sourceFingerprint:String?=nil;var photoControls:[PhotoControl]?=nil;var pointTracks:[PointTrack]?=nil;var annotationSources:[AnnotationDependency]?=nil;var captureClassification:String?=nil;var captureAnchorID:UUID?=nil;var geometrySource:GeometrySource?=nil
    var resolvedGeometrySource:GeometrySource? {
        if let geometrySource{return geometrySource}
        // Read-only compatibility for pre-role archives. Newly generated
        // geometry carries a role that survives user renaming.
        if name=="Observed LiDAR surface" {return .capturedMesh}
        if name.hasPrefix("Fused depth") {return .depthPoints}
        if name=="Reconstructed depth surface" {return .depthFusion}
        if name=="Photo-textured surface" || name=="Untextured surface · missing photo support" {return .photoTexture}
        if captureAnchorID != nil{return .capturedMesh}
        return nil
    }
}
struct Observation:Codable,Identifiable,Equatable {
    var id=UUID();var roomID:UUID;var stageID:UUID;var segmentID:UUID;var timestamp:Double;var date=Date()
    var image:String;var depth:String?;var confidence:String?;var depthWidth:Int=0;var depthHeight:Int=0
    var width:Int;var height:Int;var camera:[Double];var intrinsics:[Double]
    var tracking:String;var light:Double;var sharpness:Double;var note="";var documentary=false;var imageOrientation:Int?=nil;var referenceObservations:[ReferencePose]?=nil;var codedDetections:[CodedDetection]?=nil
    var captureMetadata:CaptureMetadata?=nil
    var resolvedKind:ObservationKind {documentary ? .imageUnregistered:depth==nil ? .rgbPosed:.rgbdPosed}
    var spatialPoseEligible:Bool {
        let state=tracking.lowercased()
        return !documentary && !state.contains("limited") && !state.contains("unavailable") && !state.contains("notavailable")
    }
    var depthTimingCompatible:Bool {
        // A known different acquisition time needs a calibrated motion/time
        // adapter, which this pipeline does not have. Retain the bytes but do
        // not attach them to this RGB camera pose. Nil remains explicitly
        // unknown for legacy records and ARKit's same-frame sceneDepth API.
        guard let metadata=captureMetadata,let time=metadata.depthTimestamp else{return true}
        return time.isFinite && time==timestamp && metadata.frameTimestamp==timestamp
    }
    var metricDepthEligible:Bool {spatialPoseEligible && depth != nil && confidence != nil && depthTimingCompatible}
    var spatialProcessingIssue:String? {
        if documentary {return nil}
        if !spatialPoseEligible {return "Tracking was limited or unavailable. Original photo retained; revisit this area for spatial processing."}
        if !depthTimingCompatible {return "Depth and photo timestamps differ. Original evidence retained; this depth is excluded from spatial processing."}
        return nil
    }
    var assets:Set<String> {Set([image,depth,confidence,captureMetadata?.exifAsset].compactMap{$0})}
    // Native camera transform is row-major, ARKit right/up/back. No pretend calibration.
}
// Coordinates refer to the EXIF-oriented image, top-left origin, normalized
// to [0,1]. These marks have no camera pose, metric scale or 3D anchor.
enum ImageAnnotationKind:String,Codable,CaseIterable {case point,box,polygon,curve}
struct ImageAnnotation:Codable,Identifiable,Equatable {
    var id=UUID();var kind:ImageAnnotationKind;var points:[UV];var label="";var reviewed=false
    var valid:Bool {
        guard label.utf8.count<=4096,points.count<=512,points.allSatisfy({$0.u.isFinite && $0.v.isFinite && (0...1).contains($0.u) && (0...1).contains($0.v)}) else{return false}
        switch kind {
        case .point:return points.count==1
        case .box:return points.count==2 && abs(points[0].u-points[1].u)>1e-6 && abs(points[0].v-points[1].v)>1e-6
        case .polygon:
            guard points.count>=3,distinctPoints==points.count else{return false}
            var area=0.0
            for i in points.indices {let next=points[(i+1)%points.count];area+=points[i].u*next.v-next.u*points[i].v}
            return abs(area)>1e-8
        case .curve:return points.count>=2 && zip(points,points.dropFirst()).allSatisfy({$0.0 != $0.1})
        }
    }
    private var distinctPoints:Int {Set(points.map{[$0.u,$0.v]}).count}
}
struct DocumentaryPhoto:Codable,Identifiable,Equatable {
    var id=UUID();var image:String;var date=Date();var note="";var roomID:UUID?;var stageID:UUID?
    var annotations:[ImageAnnotation]?=nil
}
struct Segment:Codable,Identifiable,Equatable {
    var id=UUID();var roomID:UUID;var stageID:UUID;var started=Date();var worldMap:String?;var registration:Rigid?;var registrationResidual:Double?;var registrationLink:RegistrationLink?=nil;var interrupted=false;var approved=false;var referencePoses:[ReferencePose]=[];var poseSolution:PoseGraphSolution?=nil
}
struct Dimension:Codable,Identifiable,Equatable {
    var id=UUID();var name:String;var a:V3;var b:V3;var roomID:UUID;var date=Date();var source="Approximate geometry";var sourceRevision:Int;var segmentID:UUID?=nil;var sourceGeometry:[AnnotationDependency]?=nil
    var metres:Double {(a-b).length}
}
struct Drawing:Codable,Identifiable,Equatable {
    var id=UUID();var name:String;var asset:String;var page:Int=0;var metresPerPoint:Double?;var roomID:UUID?;var notes="Design reference; not surveyed as-built geometry.";var alignment:DrawingAlignment?=nil
}
struct Bookmark:Codable,Identifiable,Equatable { var id=UUID();var name:String;var position:V3;var yaw:Double;var pitch:Double;var roomID:UUID;var segmentID:UUID?=nil }
struct House:Codable,Identifiable,Equatable {
    var schema=1;var id=UUID();var name:String;var created=Date();var revision=1;var rooms:[Room]=[];var stages:[Stage]=[]
    var features:[Feature]=[];var observations:[Observation]=[];var segments:[Segment]=[];var dimensions:[Dimension]=[];var drawings:[Drawing]=[];var bookmarks:[Bookmark]=[]
    var boundaries:[RevealBoundary]=[]
    var fieldChecks:[FieldCheck]=[]
    var processingReports:[CaptureProcessingReport]=[]
    var visualMaps:[VisualMapReference]=[]
    var connections:[ServiceConnection]=[]
    var documentaryPhotos:[DocumentaryPhoto]=[]
    var references:[ReferenceBoard]=[];var isDemo=false;var notes="";var closureNotes=""
    var assets:Set<String> {
        var keys=observations.flatMap{$0.assets}
        keys+=visualMaps.map{$0.asset}
        keys+=drawings.map{$0.asset};keys+=segments.compactMap{$0.worldMap};keys+=references.flatMap{[$0.image,$0.pdf]};keys+=features.compactMap{$0.texture};keys+=documentaryPhotos.map{$0.image}
        return Set(keys)
    }
    func validate() throws {
        guard schema==1 else {throw HouseError.message("This project uses an unsupported schema. Update the app; the original is preserved.")}
        guard rooms.count<=100,features.count<=10000,observations.count<=50000 else{throw HouseError.message("Project exceeds this build's supported metadata limits.")}
        guard processingReports.count<=1000,processingReports.allSatisfy({$0.valid}) else{throw HouseError.message("Invalid capture processing report.")}
        guard fieldChecks.count<=10000,Set(fieldChecks.map{$0.id}).count==fieldChecks.count,fieldChecks.allSatisfy({$0.valid}) else{throw HouseError.message("Invalid field evidence records.")}
        let roomIDs=Set(rooms.map{$0.id}),stageIDs=Set(stages.map{$0.id})
        guard documentaryPhotos.count<=50000,Set(documentaryPhotos.map{$0.id}).count==documentaryPhotos.count else{throw HouseError.message("Invalid documentary photograph inventory.")}
        var markIDs=Set<UUID>(),markCount=0,markPoints=0
        for photo in documentaryPhotos {
            guard photo.roomID.map({roomIDs.contains($0)}) ?? true,photo.stageID.map({stageIDs.contains($0)}) ?? true else{throw HouseError.message("Documentary photograph references a missing room or stage.")}
            let marks=photo.annotations ?? [];markCount+=marks.count
            guard marks.count<=1000,markCount<=50000 else{throw HouseError.message("Too many photograph annotations.")}
            for mark in marks {markPoints+=mark.points.count;guard mark.valid,markIDs.insert(mark.id).inserted,markPoints<=1_000_000 else{throw HouseError.message("Invalid or repeated two-dimensional photograph annotation.")}}
        }
        guard roomIDs.count==rooms.count,stageIDs.count==stages.count,Set(features.map{$0.id}).count==features.count else{throw HouseError.message("Duplicate identities in project.")}
        for r in rooms {guard r.origin.finite,r.size.finite,r.size.x>0,r.size.y>0,r.size.z>0 else{throw HouseError.message("Invalid room dimensions.")}}
        for f in features {guard f.mesh.valid,roomIDs.contains(f.roomID),stageIDs.contains(f.stageID),f.route.allSatisfy({$0.finite}) else{throw HouseError.message("Invalid geometry or source relationships.")}}
        guard Set(segments.map{$0.id}).count==segments.count,Set(observations.map{$0.id}).count==observations.count else{throw HouseError.message("Duplicate capture identities.")}
        let segmentIDs=Set(segments.map{$0.id})
        guard Set(processingReports.map{$0.segmentID}).count==processingReports.count,processingReports.allSatisfy({segmentIDs.contains($0.segmentID)}) else{throw HouseError.message("Processing report references an absent or repeated capture.")}
        guard boundaries.count<=1000,Set(boundaries.map{$0.id}).count==boundaries.count,boundaries.allSatisfy({$0.valid && segmentIDs.contains($0.segmentID)}) else{throw HouseError.message("Invalid wall or ceiling boundary.")}
        let segmentByID=Dictionary(uniqueKeysWithValues:segments.map{($0.id,$0)})
        for f in features {if let sid=f.segmentID,!segmentIDs.contains(sid){throw HouseError.message("Feature references an absent capture session.")};if let uv=f.uv {guard uv.count==f.mesh.vertices.count,uv.allSatisfy({$0.u.isFinite && $0.v.isFinite}) else{throw HouseError.message("Invalid texture coordinates.")}}}
        for s in segments {guard roomIDs.contains(s.roomID),stageIDs.contains(s.stageID) else{throw HouseError.message("Capture session references an absent space or stage.")};if let t=s.registration, !t.valid {throw HouseError.message("Invalid segment registration.")}}
        for s in segments {if let solution=s.poseSolution {guard solution.cameras.count>=3,solution.cameras.count<=120,solution.maximumEdgeResidual.isFinite,solution.maximumEdgeResidual>=0,solution.cameras.allSatisfy({ key,value in observations.contains(where:{$0.id.uuidString==key && $0.segmentID==s.id}) && Rigid(values:value).valid }) else{throw HouseError.message("Invalid optimized camera provenance.")}}}
        for segment in segments {if let solution=segment.poseSolution,let landmarks=solution.landmarks {
            guard landmarks.count<=2000,landmarks.count==solution.bundlePointCount,landmarks.allSatisfy({landmark in
                landmark.point.finite && max(abs(landmark.point.x),abs(landmark.point.y),abs(landmark.point.z))<=100000 && (3...12).contains(landmark.controls.count) && Set(landmark.controls.map{$0.observationID}).count==landmark.controls.count && landmark.controls.allSatisfy{control in control.u.isFinite && control.v.isFinite && (0...1).contains(control.u) && (0...1).contains(control.v) && solution.cameras[control.observationID.uuidString] != nil}
            }) else{throw HouseError.message("Invalid optimized landmark provenance.")}
        }}
        for o in observations {guard roomIDs.contains(o.roomID),stageIDs.contains(o.stageID),segmentByID[o.segmentID]?.roomID==o.roomID,segmentByID[o.segmentID]?.stageID==o.stageID,o.sharpness.isFinite,o.light.isFinite,o.camera.count==16,Rigid(values:o.camera).valid,o.intrinsics.count==9,o.intrinsics[0]>0,o.intrinsics[4]>0,o.timestamp.isFinite,o.camera.allSatisfy({$0.isFinite}),o.intrinsics.allSatisfy({$0.isFinite}),o.width>0,o.width<=20000,o.height>0,o.height<=20000,o.depthWidth>=0,o.depthWidth<=8192,o.depthHeight>=0,o.depthHeight<=8192 else{throw HouseError.message("Invalid observation metadata.")}}
        let featureIDs=Set(features.map{$0.id});for c in connections{guard featureIDs.contains(c.fromFeature),featureIDs.contains(c.toFeature),c.fromFeature != c.toFeature,[0,1].contains(c.fromEnd),[0,1].contains(c.toEnd) else{throw HouseError.message("Invalid service endpoint link.")}}
        for f in features {if let controls=f.photoControls {guard controls.count==3,Set(controls.map{$0.observationID}).count==3,controls.allSatisfy({c in c.u.isFinite && c.v.isFinite && (0...1).contains(c.u) && (0...1).contains(c.v) && observations.contains(where:{$0.id==c.observationID && $0.segmentID==f.segmentID})}) else{throw HouseError.message("Invalid image triangulation provenance.")}}}
        let observationByID=Dictionary(uniqueKeysWithValues:observations.map{($0.id,$0)})
        for f in features {if let tracks=f.pointTracks {
            let sourceIDs=Set(f.sourceIDs)
            guard tracks.count==f.mesh.vertices.count,tracks.allSatisfy({track in
                track.controls.count>=3 && track.controls.count<=12 && Set(track.controls.map{$0.observationID}).count==track.controls.count && track.controls.allSatisfy{c in
                    c.u.isFinite && c.v.isFinite && (0...1).contains(c.u) && (0...1).contains(c.v) && sourceIDs.contains(c.observationID)
                      && observationByID[c.observationID] != nil && observationByID[c.observationID]?.segmentID==f.segmentID
                }
            }) else{throw HouseError.message("Invalid photograph point provenance: every control must identify an original photograph in the feature's capture session.")}
        }}
        for f in features {if let sources=f.annotationSources {guard !sources.isEmpty,sources.count<=64,Set(sources.map{$0.featureID}).count==sources.count,sources.allSatisfy({$0.featureID != f.id && $0.revision>0 && ($0.registration==nil || $0.registration!.valid)}) else{throw HouseError.message("Invalid annotation source relationships.")}}}
        for d in dimensions {guard d.a.finite,d.b.finite,roomIDs.contains(d.roomID),(d.segmentID==nil || segmentIDs.contains(d.segmentID!)),d.sourceGeometry==nil || (!d.sourceGeometry!.isEmpty && d.sourceGeometry!.count<=64 && d.sourceGeometry!.allSatisfy{$0.revision>0 && ($0.registration==nil || $0.registration!.valid)}) else{throw HouseError.message("Invalid measurement reference.")}}
        for b in bookmarks {guard b.position.finite,b.yaw.isFinite,b.pitch.isFinite,roomIDs.contains(b.roomID),(b.segmentID==nil || segmentIDs.contains(b.segmentID!)) else{throw HouseError.message("Invalid viewpoint frame.")}}
        for b in references {guard b.width.isFinite,b.width>0.03,b.width<2 else{throw HouseError.message("Reference width must be between 3 cm and 2 m.")}}
        let codes=references.compactMap{$0.tagID}
        guard references.count<=1000,Set(references.map{$0.id}).count==references.count,Set(codes).count==codes.count,codes.allSatisfy({(0..<587).contains($0)}),references.allSatisfy({$0.roomID==nil || roomIDs.contains($0.roomID!)}) else{throw HouseError.message("Reference identities must be unique, within the supported dictionary and assigned to an existing room.")}
        let boardIDs=Set(references.map{$0.id})
        for poses in segments.map({$0.referencePoses})+observations.map({$0.referenceObservations ?? []}) {
          guard poses.count<=1000,Set(poses.map{$0.boardID}).count==poses.count,poses.allSatisfy({pose in
            boardIDs.contains(pose.boardID) && Rigid(values:pose.matrix).valid && (pose.method==nil || pose.method=="coded-corners") && (pose.imageFitRMS==nil || (pose.imageFitRMS!.isFinite && (0...0.8).contains(pose.imageFitRMS!))) && (pose.method != "coded-corners" || pose.imageFitRMS != nil)
          }) else{throw HouseError.message("Invalid recorded reference pose or pixel-fit provenance.")}
        }
        for observation in observations {
          if let metadata=observation.captureMetadata,!metadata.valid(for:observation) {throw HouseError.message("Invalid capture clock, calibration or source metadata.")}
          if let detections=observation.codedDetections {
          guard detections.count<=64,Set(detections.map{$0.tagID}).count==detections.count,detections.allSatisfy({detection in detection.valid && boardIDs.contains(detection.boardID) && references.first(where:{$0.id==detection.boardID})?.tagID==detection.tagID}) else{throw HouseError.message("Invalid coded-reference capture provenance.")}
        }}
        for map in visualMaps {guard segmentByID[map.segmentID]?.roomID==map.roomID,segmentByID[map.segmentID]?.stageID==map.stageID else{throw HouseError.message("Invalid visual reference provenance.")}}
        for d in drawings {if let a=d.alignment {guard a.transform.valid,a.metresPerPoint.isFinite,a.metresPerPoint>0,a.page>=0,a.sheetPoints.count>=4,a.sheetPoints.count==a.housePoints.count,a.sheetPoints.allSatisfy({$0.finite}),a.housePoints.allSatisfy({$0.finite}),a.fitMaximum.isFinite,a.checkMaximum.isFinite else{throw HouseError.message("Invalid drawing alignment.")}}}
        for a in assets {guard a.count<100,!a.contains("/"),!a.contains("\\"),!a.contains("..") else{throw HouseError.message("Unsafe asset reference.")}}
    }
    static func empty(_ name:String)->House {
        var h=House(name:name);h.rooms=[Room(name:"First room",level:0,origin:V3(),size:V3(5,4,2.74))]
        h.stages=[Stage(name:"Rough-in",kind:.observed),Stage(name:"Finished",kind:.observed)];return h
    }
}
enum HouseError:LocalizedError {case message(String);var errorDescription:String?{if case let .message(m)=self{return m};return nil}}

// Public deterministic fixture, never represented as a reconstruction accuracy test.
enum DemoFactory {
    static func make(seed:Int=42)->House {
        var h=House(name:"The sample house");h.isDemo=true
        h.notes="Procedural demonstration. All framing, finishes and services are synthetic; this is not your house."
        let rough=Stage(name:"Rough-in",kind:.synthetic),finish=Stage(name:"Finished",kind:.synthetic);h.stages=[rough,finish]
        let rooms=[Room(name:"Living room",level:0,origin:V3(),size:V3(6,5,2.8)),Room(name:"Kitchen",level:0,origin:V3(6.2,0,0),size:V3(4.5,5,2.8)),Room(name:"Office",level:1,origin:V3(0,0,3.2),size:V3(4.5,4,2.7))];h.rooms=rooms
        for room in rooms {
            let o=room.origin,s=room.size
            func box(_ name:String,_ trade:Trade,_ c:V3,_ size:V3,_ stage:Stage) {h.features.append(Feature(name:name,trade:trade,roomID:room.id,stageID:stage.id,kind:.synthetic,mesh:.box(center:o+c,size:size)))}
            box("Subfloor",.floor,V3(s.x/2,s.y/2,-0.07),V3(s.x,s.y,0.14),rough)
            for wall in 0..<4 {
                let length=wall<2 ? s.x:s.y
                for i in 0...Int(length/0.406) {
                    let u=min(Double(i)*0.406,length-0.04)
                    let c=wall==0 ? V3(u,0,s.z/2):wall==1 ? V3(u,s.y,s.z/2):wall==2 ? V3(0,u,s.z/2):V3(s.x,u,s.z/2)
                    // Doorway in each west/east wall, shared for demo navigation.
                    if wall>=2 && u>1.7 && u<2.8 {continue}
                    box("Stud · wall \(wall+1)",.structure,c,wall<2 ? V3(0.038,0.14,s.z):V3(0.14,0.038,s.z),rough)
                }
                let c=wall==0 ? V3(s.x/2,0,s.z/2):wall==1 ? V3(s.x/2,s.y,s.z/2):wall==2 ? V3(0,s.y/2,s.z/2):V3(s.x,s.y/2,s.z/2)
                if wall<2 {box("Drywall · wall \(wall+1)",.finish,c, V3(s.x,0.02,s.z),finish)}
                else {
                    for (y,height,z) in [(0.85,s.z,s.z/2),(3.9,s.z,s.z/2),(2.25,s.z-2.15,2.15+(s.z-2.15)/2)] {
                        let width=y==0.85 ? 1.7:y==3.9 ? max(0.1,s.y-2.8):1.1
                        let centerY=y==3.9 ? (2.8+s.y)/2:y
                        box("Drywall with doorway",.finish,V3(c.x,centerY,z),V3(0.02,width,height),finish)
                    }
                }
            }
            for x in stride(from:0.2,to:s.x,by:0.406) {box("Ceiling joist",.structure,V3(x,s.y/2,s.z),V3(0.05,s.y,0.22),rough)}
            box("Finished ceiling",.ceiling,V3(s.x/2,s.y/2,s.z-0.13),V3(s.x,s.y,0.02),finish)
            let routes:[(String,Trade,[V3],Double,String)]=[
                ("Outlet circuit",.electrical,[V3(0.5,0.08,0.4),V3(0.5,0.08,1.2),V3(s.x-0.5,0.08,1.2),V3(s.x-0.5,0.08,0.4)],0.014,"Panel A · identity unverified"),
                ("Speaker prewire",.lowVoltage,[V3(0.25,0.12,0.2),V3(0.25,0.12,s.z-0.1),V3(s.x/2,s.y/2,s.z-0.1)],0.01,"AV rack → ceiling speaker"),
                ("Water supply",.plumbing,[V3(s.x-0.3,s.y-0.1,0.1),V3(s.x-0.3,s.y-0.1,2),V3(s.x/2,s.y-0.1,2)],0.025,"Supply · simulated"),
                ("Supply duct",.hvac,[V3(0.5,1,s.z-0.25),V3(s.x-0.7,1,s.z-0.25),V3(s.x-0.7,2,s.z-0.25)],0.16,"HVAC supply · simulated")]
            for (name,trade,pts,radius,endpoint) in routes {let p=pts.map{$0+o};var f=Feature(name:name,trade:trade,roomID:room.id,stageID:rough.id,kind:.synthetic,mesh:.route(p,radius:radius),route:p);f.endpoint=endpoint;h.features.append(f)}
        }
        return h
    }
}

extension House {
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        schema=try c.decode(Int.self,forKey:.schema)
        id=try c.decode(UUID.self,forKey:.id)
        name=try c.decode(String.self,forKey:.name)
        created=try c.decode(Date.self,forKey:.created)
        revision=try c.decode(Int.self,forKey:.revision)
        rooms=try c.decodeIfPresent([Room].self,forKey:.rooms) ?? []
        stages=try c.decodeIfPresent([Stage].self,forKey:.stages) ?? []
        features=try c.decodeIfPresent([Feature].self,forKey:.features) ?? []
        observations=try c.decodeIfPresent([Observation].self,forKey:.observations) ?? []
        segments=try c.decodeIfPresent([Segment].self,forKey:.segments) ?? []
        dimensions=try c.decodeIfPresent([Dimension].self,forKey:.dimensions) ?? []
        drawings=try c.decodeIfPresent([Drawing].self,forKey:.drawings) ?? []
        bookmarks=try c.decodeIfPresent([Bookmark].self,forKey:.bookmarks) ?? []
        boundaries=try c.decodeIfPresent([RevealBoundary].self,forKey:.boundaries) ?? []
        fieldChecks=try c.decodeIfPresent([FieldCheck].self,forKey:.fieldChecks) ?? []
        processingReports=try c.decodeIfPresent([CaptureProcessingReport].self,forKey:.processingReports) ?? []
        visualMaps=try c.decodeIfPresent([VisualMapReference].self,forKey:.visualMaps) ?? []
        connections=try c.decodeIfPresent([ServiceConnection].self,forKey:.connections) ?? []
        documentaryPhotos=try c.decodeIfPresent([DocumentaryPhoto].self,forKey:.documentaryPhotos) ?? []
        references=try c.decodeIfPresent([ReferenceBoard].self,forKey:.references) ?? []
        isDemo=try c.decodeIfPresent(Bool.self,forKey:.isDemo) ?? false
        notes=try c.decodeIfPresent(String.self,forKey:.notes) ?? ""
        closureNotes=try c.decodeIfPresent(String.self,forKey:.closureNotes) ?? ""
        ReferenceRegistration.invalidateChangedInputs(&self)
    }
}

extension Segment {
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(UUID.self,forKey:.id)
        roomID=try c.decode(UUID.self,forKey:.roomID)
        stageID=try c.decode(UUID.self,forKey:.stageID)
        started=try c.decode(Date.self,forKey:.started)
        worldMap=try c.decodeIfPresent(String?.self,forKey:.worldMap) ?? nil
        registration=try c.decodeIfPresent(Rigid?.self,forKey:.registration) ?? nil
        registrationResidual=try c.decodeIfPresent(Double?.self,forKey:.registrationResidual) ?? nil
        interrupted=try c.decodeIfPresent(Bool.self,forKey:.interrupted) ?? false
        approved=try c.decodeIfPresent(Bool.self,forKey:.approved) ?? false
        referencePoses=try c.decodeIfPresent([ReferencePose].self,forKey:.referencePoses) ?? []
        registrationLink=try c.decodeIfPresent(RegistrationLink.self,forKey:.registrationLink)
        poseSolution=try c.decodeIfPresent(PoseGraphSolution.self,forKey:.poseSolution)
    }
}
