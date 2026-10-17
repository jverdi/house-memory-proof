import Foundation
import CoreVideo
import simd

// Metric code geometry and camera/board estimates remain separate evidence.
// Pixel fitting never promotes a board estimate to a physically surveyed reference.
enum CodedReferences {
  struct Board {var id:UUID;var code:UInt32;var corners:[V3]}
  struct Map {var boards:[Board];var known:[ReferenceBoard]}
  struct Result {var pose:Rigid?;var conflict:Bool}
  static func gray(_ buffer:CVPixelBuffer)throws->(Data,Int,Int,Int) {
    guard CVPixelBufferGetPlaneCount(buffer)>=1 else{throw HouseError.message("Camera luminance plane is unavailable.")}
    let w=CVPixelBufferGetWidthOfPlane(buffer,0),h=CVPixelBufferGetHeightOfPlane(buffer,0),stride=CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
    guard w>=64,h>=64,w<=4096,h<=4096,stride>=w,stride*h<=20_000_000 else{throw HouseError.message("Camera image exceeds the reference detector budget.")}
    CVPixelBufferLockBaseAddress(buffer,.readOnly);defer{CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
    guard let base=CVPixelBufferGetBaseAddressOfPlane(buffer,0) else{throw HouseError.message("Camera luminance bytes are unavailable.")}
    return(Data(bytes:base,count:stride*h),w,h,stride)
  }
  static func detect(gray:Data,width:Int,height:Int,stride:Int,boards:[ReferenceBoard],rejectUnknown:Bool=false)throws->[CodedDetection] {
    guard width>=64,height>=64,width<=4096,height<=4096,stride>=width,stride<=20000,gray.count<=20_000_000,gray.count>=stride*height else{throw HouseError.message("Invalid reference image dimensions.")}
    guard boards.contains(where:{$0.tagID != nil}) else{return []}
    let known=Dictionary(grouping:boards.filter{$0.valid && $0.tagID != nil},by:{$0.tagID!})
    guard known.values.allSatisfy({$0.count==1}) else{throw HouseError.message("Duplicate coded-reference identities are ambiguous.")}
    var ids=[UInt32](repeating:0,count:64),corners=[Double](repeating:0,count:512),margins=[Double](repeating:0,count:64)
    let count=gray.withUnsafeBytes{bytes in ids.withUnsafeMutableBufferPointer{codes in corners.withUnsafeMutableBufferPointer{points in margins.withUnsafeMutableBufferPointer{quality in
      hx_tag_detect(bytes.bindMemory(to:UInt8.self).baseAddress,UInt32(gray.count),UInt32(width),UInt32(height),UInt32(stride),codes.baseAddress,points.baseAddress,quality.baseAddress,64)
    }}}}
    guard count>=0 else{throw HouseError.message("Coded-reference image is invalid, over budget or contains duplicate identities; alignment remains hidden.")}
    var result:[CodedDetection]=[]
    for i in 0..<Int(count) {
      guard let board=known[Int(ids[i])]?.first else{
        if rejectUnknown {throw HouseError.message("A visible coded reference is not valid in this house; alignment remains hidden.")}
        continue
      }
      let points=(0..<4).map{UV(u:corners[i*8+$0*2]/Double(width),v:corners[i*8+$0*2+1]/Double(height))}
      result.append(CodedDetection(boardID:board.id,tagID:Int(ids[i]),corners:points,margin:margins[i]))
    }
    return result
  }
  static func corners(board:ReferenceBoard,pose:ReferencePose)->[V3] {
    guard board.tagID != nil,let matrix=PoseRefinement.matrix(pose.matrix) else{return []}
    // The generated image is ten cells wide; the black tag border spans eight.
    // Our stored board frame uses X/Z, with image-bottom along local +Z.
    let half=board.width*0.8/2
    return [SIMD4<Double>(-half,0,half,1),SIMD4(half,0,half,1),SIMD4(half,0,-half,1),SIMD4(-half,0,-half,1)].map {p in
      let world=matrix*p;return V3(world.x,-world.z,world.y)
    }
  }
  static func measure(_ detections:[CodedDetection],camera:[Double],intrinsics:[Double],width:Int,height:Int,boards:[ReferenceBoard])->[ReferencePose] {
    guard let worldFromCamera=PoseRefinement.matrix(camera),intrinsics.count==9,width>=64,height>=64,width<=4096,height<=4096 else{return []}
    var result:[ReferencePose]=[]
    for detection in detections where detection.valid {
      guard let board=boards.first(where:{$0.id==detection.boardID && $0.tagID==detection.tagID && $0.valid}) else{continue}
      let xy=detection.corners.flatMap{[$0.u*Double(width),$0.v*Double(height)]}
      var values=[Double](repeating:0,count:16),quality=HXTagPoseQuality()
      let accepted=xy.withUnsafeBufferPointer{pixels in values.withUnsafeMutableBufferPointer{matrix in
        hx_reference_measure_tag(pixels.baseAddress,board.width*0.8,intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),matrix.baseAddress,&quality)
      }}
      guard accepted==1,let cameraFromBoard=PoseRefinement.matrix(values) else{continue}
      result.append(ReferencePose(boardID:board.id,matrix:PoseRefinement.array(worldFromCamera*cameraFromBoard),method:"coded-corners",imageFitRMS:quality.rms_pixels))
    }
    return result
  }
  @discardableResult static func accumulate(_ poses:[ReferencePose],current:inout [UUID:ReferencePose],conflicted:inout Set<UUID>)->Bool {
    var rejected=false
    for pose in poses where pose.method=="coded-corners" && !conflicted.contains(pose.boardID) {
      if let old=current[pose.boardID],old.method=="coded-corners" {
        guard VisualMapping.agree(Rigid(values:old.matrix),Rigid(values:pose.matrix)) else {
          current.removeValue(forKey:pose.boardID);conflicted.insert(pose.boardID);rejected=true;continue
        }
        if (pose.imageFitRMS ?? .infinity)<(old.imageFitRMS ?? .infinity) {current[pose.boardID]=pose}
      }else{current[pose.boardID]=pose}
    }
    return rejected
  }
  static func build(house:House,segment:Segment)->Map {
    let known=house.references.filter{$0.valid && $0.tagID != nil}
    let captures=house.observations.filter{$0.segmentID==segment.id && !$0.documentary && $0.codedDetections?.isEmpty==false}
    var boards:[Board]=[]
    for board in known {
      guard let pose=segment.referencePoses.first(where:{$0.boardID==board.id && $0.method=="coded-corners"}) else{continue}
      let points=corners(board:board,pose:pose);guard points.count==4 else{continue}
      var supported:[V3]=[],conflicted=false
      for observation in captures {
        guard let detection=observation.codedDetections?.first(where:{$0.boardID==board.id && $0.tagID==board.tagID}),detection.valid else{continue}
        let projected=points.compactMap{CameraProjection.project($0,through:observation)?.0}
        guard projected.count==4 else{conflicted=true;break}
        let errors=zip(projected,detection.corners).map{a,b in hypot((a.u-b.u)*Double(observation.width),(a.v-b.v)*Double(observation.height))}
        guard errors.allSatisfy({$0<=4}) else{conflicted=true;break}
        supported.append(V3(observation.camera[3],-observation.camera[11],observation.camera[7]))
      }
      guard !conflicted,supported.count>=2,supported.contains(where:{a in supported.contains{($0-a).length>=0.15}}) else{continue}
      boards.append(Board(id:board.id,code:UInt32(board.tagID!),corners:points))
    }
    // A large reference inventory needs scoped capture; never search a prefix.
    return Map(boards:boards.count<=16 ? boards:[],known:known)
  }
  static func localize(gray:Data,width:Int,height:Int,stride:Int,intrinsics:[Double],map:Map)throws->Result {
    guard intrinsics.count==9 else{return Result(pose:nil,conflict:true)}
    let detections=try detect(gray:gray,width:width,height:height,stride:stride,boards:map.known,rejectUnknown:true)
    let byID=Dictionary(uniqueKeysWithValues:map.boards.map{($0.id,$0)})
    // Visible references belonging to another saved region cannot support the selected one.
    if detections.contains(where:{byID[$0.boardID]==nil}) {return Result(pose:nil,conflict:true)}
    guard detections.count>=4 else{return Result(pose:nil,conflict:false)}
    var xyz:[Double]=[],xy:[Double]=[],ids:[UInt32]=[]
    for detection in detections {
      let board=byID[detection.boardID]!;ids.append(board.code)
      xyz += board.corners.flatMap{[$0.x,$0.y,$0.z]}
      xy += detection.corners.flatMap{[$0.u*Double(width),$0.v*Double(height)]}
    }
    var values=[Double](repeating:0,count:16),quality=HXReferenceQuality()
    let accepted=xyz.withUnsafeBufferPointer{points in xy.withUnsafeBufferPointer{pixels in ids.withUnsafeBufferPointer{codes in values.withUnsafeMutableBufferPointer{matrix in
      hx_reference_pose(points.baseAddress,pixels.baseAddress,codes.baseAddress,UInt32(ids.count),intrinsics[0],intrinsics[4],intrinsics[2],intrinsics[5],UInt32(width),UInt32(height),matrix.baseAddress,&quality)
    }}}}
    let pose=Rigid(values:values)
    return accepted==1 && pose.valid ? Result(pose:pose,conflict:false):Result(pose:nil,conflict:true)
  }
}
