import Foundation

struct ReferenceBoard: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var image: String
  var pdf: String
  var width: Double = 0.18
  var location = ""
  var valid = true
}
struct ReferencePose: Codable, Equatable {
  var boardID: UUID
  var matrix: [Double]
  var observed = Date()
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
