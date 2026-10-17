import Foundation

struct ReferenceBoard: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var image: String
  var pdf: String
  var width: Double = 0.18
  var location = ""
  var valid = true
  var tagID:Int?=nil
  var roomID:UUID?=nil
}
struct CodedDetection:Codable,Equatable {
  // AprilTag edge-origin coordinates normalized by image dimensions; preserve
  // this convention in archives and convert only when applying intrinsics.
  var boardID:UUID;var tagID:Int;var corners:[UV];var margin:Double
  var valid:Bool {(0..<587).contains(tagID) && corners.count==4 && corners.allSatisfy{$0.u.isFinite && $0.v.isFinite && (0...1).contains($0.u) && (0...1).contains($0.v)} && margin.isFinite && margin>=30}
}
struct ReferencePose: Codable, Equatable {
  var boardID: UUID
  var matrix: [Double]
  var observed = Date()
  var method:String?=nil
  var imageFitRMS:Double?=nil
}

struct ServiceConnection: Codable, Identifiable, Equatable {
  var id = UUID()
  var fromFeature: UUID
  var fromEnd: Int
  var toFeature: UUID
  var toEnd: Int
  var confirmed = false
  var notes = ""
  var date = Date()
}

struct UV: Codable, Equatable {
  var u: Double
  var v: Double
}

enum CameraProjection {
  // Canonical metres/Z-up -> native AR camera -> unrotated image pixels.
  // Shared by texturing and coded references, including isolated host replay.
  static func project(_ p:V3,through o:Observation)->(UV,Double)? {
    let m=o.camera
    guard m.count==16,o.intrinsics.count==9,o.width>0,o.height>0,p.finite else{return nil}
    let ar=V3(p.x,p.z,-p.y),d=ar-V3(m[3],m[7],m[11])
    let x=m[0]*d.x+m[4]*d.y+m[8]*d.z
    let y = -(m[1]*d.x+m[5]*d.y+m[9]*d.z)
    let z = -(m[2]*d.x+m[6]*d.y+m[10]*d.z)
    guard z>0.15,z<8 else{return nil}
    let u=(o.intrinsics[0]*x/z+o.intrinsics[2])/Double(o.width)
    let v=(o.intrinsics[4]*y/z+o.intrinsics[5])/Double(o.height)
    guard u>=0,u<=1,v>=0,v<=1 else{return nil}
    return(UV(u:u,v:v),z)
  }
}

struct DrawingAlignment: Codable, Equatable {
    var page: Int
    var metresPerPoint: Double
    var sheetPoints: [V3]
    var housePoints: [V3]
    var transform: Rigid
    var fitMaximum: Double
    var checkMaximum: Double
    var sourceRevision: Int
    var date = Date()
}

enum CheckedRegistration {
    static func fit(source: [V3], target: [V3], tolerance: Double = 0.025) throws -> (Rigid, Double, Double) {
        guard source.count >= 4, source.count == target.count,
              source.allSatisfy({ $0.finite }), target.allSatisfy({ $0.finite }),
              tolerance.isFinite, tolerance > 0,
              let (transform, _) = Rigid.register(source: Array(source.prefix(3)), target: Array(target.prefix(3)))
        else { throw HouseError.message("Supply three non-collinear fitting pairs and at least one independent check pair.") }
        let errors = zip(source, target).map { (transform.apply($0.0) - $0.1).length }
        let fit = errors.prefix(3).max() ?? .infinity
        let check = errors.dropFirst(3).max() ?? .infinity
        guard fit <= tolerance, check <= tolerance else {
            throw HouseError.message("Alignment rejected: fitting error \((fit * 1000).formatted()) mm; independent check \((check * 1000).formatted()) mm. Both must be within \((tolerance * 1000).formatted()) mm.")
        }
        return (transform, fit, check)
    }
    static func coordinates(_ text: String) throws -> [V3] {
        try text.split(separator: "\n").map { line in
            let tokens = line.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            let values = tokens.compactMap { Double($0) }
            guard tokens.count == 3, values.count == 3, values.allSatisfy({ $0.isFinite && abs($0) < 100000 })
            else { throw HouseError.message("Each line must contain exactly three finite coordinates: x,y,z in metres.") }
            return V3(values[0], values[1], values[2])
        }
    }
}



struct PhotoControl: Codable, Equatable {
  var observationID:UUID
  var u:Double
  var v:Double
}

// Oriented wall/ceiling rectangle; positive normal points into the hidden cavity.
// Coordinates belong to one immutable capture frame, never a guessed room frame.
struct RevealBoundary: Codable, Identifiable, Equatable {
  var id=UUID();var name:String;var segmentID:UUID;var origin:V3;var horizontal:V3;var vertical:V3
  var width:Double;var height:Double;var depth:Double;var finishOffset:Double
  var sourceFingerprint:String;var date=Date()
  var normal:V3 {horizontal.cross(vertical)}
  var valid:Bool {origin.finite && horizontal.finite && vertical.finite && abs(horizontal.length-1)<0.001 && abs(vertical.length-1)<0.001 && abs(horizontal.dot(vertical))<0.001 && width.isFinite && height.isFinite && depth.isFinite && finishOffset.isFinite && width>0.05 && width<=30 && height>0.05 && height<=30 && depth>0 && depth<=1 && finishOffset>=0 && finishOffset<=0.2}
  func coordinates(_ p:V3)->V3 {let d=p-origin;return V3(d.dot(horizontal),d.dot(vertical),d.dot(normal))}
  func contains(_ p:V3)->Bool {let q=coordinates(p);return q.x>=0 && q.x<=width && q.y>=0 && q.y<=height && q.z>=(-finishOffset) && q.z<=depth}
  func viewedFromFront(_ camera:V3)->Bool {coordinates(camera).z < -finishOffset-0.05}
}

struct PointTrack:Codable,Equatable {var controls:[PhotoControl]}

// Field observations are immutable evidence records. They never silently turn
// on a precision claim or alter source coordinates/calibration parameters.
enum FieldSplit:String,Codable,CaseIterable {case calibration="Calibration",validation="Independent validation"}
enum FieldCheckKind:String,Codable,CaseIterable {case distance="Surface distance",placement="Point placement",rejection="Alignment rejection"}
struct FieldCheck:Codable,Identifiable,Equatable {
  var id=UUID();var date=Date();var split:FieldSplit;var kind:FieldCheckKind
  var fixture:String;var session:String;var conditions:String
  var device:String;var sourceBuild:String;var cameraMode:String
  var truthUncertainty:Double;var cameraDistance:Double
  var measurement:Dimension?;var referenceDistance:Double?;var referencePoint:V3?
  var abstained:Bool=false;var overlayWasVisible:Bool?=nil
  var originalIDs:[UUID]=[]
  var valid:Bool {
    guard !fixture.isEmpty,!session.isEmpty,fixture.count<=500,session.count<=500,conditions.count<=5000,device.count<=500,sourceBuild.count<=200,cameraMode.count<=500,originalIDs.count<=50000,truthUncertainty.isFinite,truthUncertainty>=0,truthUncertainty<=0.1,cameraDistance.isFinite,cameraDistance>=0,cameraDistance<=20 else{return false}
    if kind == .rejection{return overlayWasVisible != nil}
    if abstained{return true}
    guard let measurement,measurement.a.finite,measurement.b.finite else{return false}
    if kind == .distance{return referenceDistance.map{$0.isFinite && $0>0 && $0<=1000} ?? false}
    return referencePoint?.finite==true
  }
  var errorMetres:Double? {
    guard !abstained,let measurement else{return nil}
    if kind == .distance,let expected=referenceDistance{return abs(measurement.metres-expected)}
    if kind == .placement,let expected=referencePoint{return (measurement.a-expected).length}
    return nil
  }
}
struct FieldSummary:Codable {
  var attempts:Int;var accepted:Int;var p95Metres:Double?;var maximumMetres:Double?
  var criticalChallenges:Int;var visibleOnRejectionChallenges:Int
  var truthWithinTwoMillimetres:Int;var independentSessions:Int
  var precisionProfileEnabled=false
}
enum FieldEvidence {
  static func summary(_ checks:[FieldCheck],split:FieldSplit)->FieldSummary {
    let selected=checks.filter{$0.split==split && $0.valid},nominal=selected.filter{$0.kind != .rejection}
    let errors=nominal.compactMap{$0.errorMetres}.sorted()
    return FieldSummary(attempts:nominal.count,accepted:errors.count,p95Metres:errors.isEmpty ? nil:errors[max(0,Int(ceil(Double(errors.count)*0.95))-1)],maximumMetres:errors.last,criticalChallenges:selected.filter{$0.kind == .rejection}.count,visibleOnRejectionChallenges:selected.filter{$0.kind == .rejection && $0.overlayWasVisible==true}.count,truthWithinTwoMillimetres:nominal.filter{$0.truthUncertainty<=0.002}.count,independentSessions:Set(selected.map{$0.session}).count)
  }
}

struct CaptureProcessingStep:Codable,Equatable {var name:String;var passed:Bool;var detail:String}
struct CaptureProcessingReport:Codable,Identifiable,Equatable {
  var id=UUID();var segmentID:UUID;var sourceRevision:Int;var sourceFingerprint:String;var date=Date();var seconds:Double;var steps:[CaptureProcessingStep]
  var jobID:UUID?=nil
  var complete:Bool {steps.allSatisfy{$0.passed}}
  var valid:Bool {sourceRevision>=0 && seconds.isFinite && seconds>=0 && steps.count<=12 && steps.allSatisfy{$0.name.count<=200 && $0.detail.count<=10000}}
}


// Search immutable metadata off the UI thread. Raster assets are never loaded.
enum EvidenceSearch {
  struct Result {
    var observations:[Observation]=[];var features:[Feature]=[]
    var observationCount=0;var featureCount=0
  }
  struct Index {
    struct Photo {var value:Observation;var text:String}
    struct Object {var value:Feature;var text:String}
    let id=UUID();var houseID:UUID;var revision:Int
    private var photos:[Photo]=[],objects:[Object]=[]
    init(house:House)throws {
      houseID=house.id;revision=house.revision
      let rooms=Dictionary(house.rooms.map{($0.id,EvidenceSearch.normalized($0.name))},uniquingKeysWith:{a,_ in a})
      let stages=Dictionary(house.stages.map{($0.id,EvidenceSearch.normalized($0.name))},uniquingKeysWith:{a,_ in a})
      for (index,o) in house.observations.reversed().enumerated() {
        if index%256==0 {try Task.checkCancellation()}
        photos.append(Photo(value:o,text:EvidenceSearch.normalized(o.note)+" "+(rooms[o.roomID] ?? "")+" "+(stages[o.stageID] ?? "")))
      }
      for (index,f) in house.features.enumerated() {
        if index%256==0 {try Task.checkCancellation()}
        objects.append(Object(value:f,text:EvidenceSearch.normalized(f.name+" "+f.notes+" "+f.endpoint+" "+f.trade.rawValue+" "+f.kind.rawValue)+" "+(rooms[f.roomID] ?? "")+" "+(stages[f.stageID] ?? "")))
      }
    }
    func find(_ query:String,limit:Int=200)throws->Result {
      guard (1...50000).contains(limit) else{throw HouseError.message("Search result limit is outside the supported range.")}
      let terms=EvidenceSearch.normalized(String(query.prefix(500))).split(whereSeparator:{$0.isWhitespace}).map(String.init)
      var result=Result()
      for (index,row) in photos.enumerated() {
        if index%256==0 {try Task.checkCancellation()}
        if terms.allSatisfy({row.text.contains($0)}) {
          result.observationCount+=1
          if result.observations.count<limit {result.observations.append(row.value)}
        }
      }
      for (index,row) in objects.enumerated() {
        if index%256==0 {try Task.checkCancellation()}
        if terms.allSatisfy({row.text.contains($0)}) {
          result.featureCount+=1
          if result.features.count<limit {result.features.append(row.value)}
        }
      }
      return result
    }
  }
  static func normalized(_ text:String)->String {
    text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
  }
}
