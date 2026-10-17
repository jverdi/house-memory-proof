import Foundation

struct UV:Codable,Equatable {var u:Double;var v:Double}
enum TextureBuilder {
    struct Camera {var observation:Observation;var depth:Data?}
    static func project(_ p:V3,through o:Observation)->(UV,Double)? {
        let m=o.camera,ar=V3(p.x,p.z,-p.y),d=ar-V3(m[3],m[7],m[11])
        // R transpose: map world into native ARKit camera, then CV camera.
        let x=m[0]*d.x+m[4]*d.y+m[8]*d.z,y = -(m[1]*d.x+m[5]*d.y+m[9]*d.z),z = -(m[2]*d.x+m[6]*d.y+m[10]*d.z)
        guard z>0.15,z<8 else{return nil}
        let u=(o.intrinsics[0]*x/z+o.intrinsics[2])/Double(o.width),v=(o.intrinsics[4]*y/z+o.intrinsics[5])/Double(o.height)
        guard u>=0,u<=1,v>=0,v<=1 else{return nil};return (UV(u:u,v:v),z)
    }
    static func visible(_ uv:UV,z:Double,camera:Camera)->Bool {
        let o=camera.observation
        guard let depth=camera.depth,o.depthWidth>0,o.depthHeight>0 else{return false}
        let x=min(o.depthWidth-1,Int(uv.u*Double(o.depthWidth))),y=min(o.depthHeight-1,Int(uv.v*Double(o.depthHeight))),i=(y*o.depthWidth+x)*4
        guard i+4<=depth.count else{return false}
        let measured=Double(Float(bitPattern:depth.uint32(i)));return measured.isFinite && measured>0 && abs(measured-z)<0.08
    }
    static func build(house:House,segment:Segment,repo:Repository) throws->[Feature] {
        let observations=house.observations.filter{$0.segmentID==segment.id && $0.depth != nil && !$0.documentary && $0.light>100}.sorted{$0.sharpness>$1.sharpness}
        let candidates=Array(observations.prefix(16));let cameras=try candidates.map{Camera(observation:$0,depth:try $0.depth.map{try repo.read($0)})}
        guard !cameras.isEmpty else{throw HouseError.message("No posed depth photographs are available for visibility-tested textures.")}
        let input=house.features.filter{$0.segmentID==segment.id && $0.name=="Observed LiDAR surface" && !$0.mesh.triangles.isEmpty}
        guard !input.isEmpty else{throw HouseError.message("This session has no original LiDAR triangle surfaces to texture.")}
        var output:[Feature]=[]
        for f in input {
            var patches:[Int:(Mesh,[UV])]=[:];var remainder=Mesh()
            for i in stride(from:0,to:f.mesh.triangles.count,by:3) {
                let vertices=(0..<3).map{f.mesh.vertices[Int(f.mesh.triangles[i+$0])]}
                var winner:Int?,coordinates:[UV]=[]
                for (j,c) in cameras.enumerated() {
                    let projections=vertices.compactMap{project($0,through:c.observation)}
                    if projections.count==3 && projections.allSatisfy({visible($0.0,z:$0.1,camera:c)}) {winner=j;coordinates=projections.map{$0.0};break}
                }
                if let winner {
                    var patch=patches[winner] ?? (Mesh(),[]);let base=Int32(patch.0.vertices.count);patch.0.vertices+=vertices;patch.0.triangles += [base,base+1,base+2];patch.1+=coordinates;patches[winner]=patch
                }else{let base=Int32(remainder.vertices.count);remainder.vertices+=vertices;remainder.triangles += [base,base+1,base+2]}
            }
            for (j,patch) in patches.sorted(by:{$0.key<$1.key}) {var copy=f;copy.id=UUID();copy.name="Photo-textured surface";copy.mesh=patch.0;copy.uv=patch.1;copy.texture=cameras[j].observation.image;copy.sourceIDs=[cameras[j].observation.id];copy.notes="Source photo selected from this session using camera projection and first-surface depth agreement within 8 cm. Display texture, not a precision refinement.";output.append(copy)}
            if !remainder.triangles.isEmpty{var copy=f;copy.id=UUID();copy.name="Untextured surface · missing photo support";copy.mesh=remainder;output.append(copy)}
        };return output
    }
}
