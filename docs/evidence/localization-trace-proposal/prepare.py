"""Prepare a review-only host observer patch; never build or run an experiment.

Call prepare(source_root) from the preparation tests. It returns changed text
without writing to the source checkout. The CLI emits a unified diff only.
Applying or executing that diff is outside this preparation command.
"""
from pathlib import Path
import argparse
import ast
import difflib


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("Observer anchor is missing or ambiguous: " + old[:80])
    return text.replace(old, new)


def prepare(root):
    paths = ["packages/visual-core/hx_vision.h", "packages/visual-core/hx_vision.cpp",
             "HouseMemoryProof/VisualMapping.swift", "tooling/simulation/VisionReplay.swift",
             "tooling/simulation/replay_fixture.py"]
    originals = {name: (root / name).read_text() for name in paths}
    result = dict(originals)
    name = paths[0]
    result[name] = once(result[name], "// Output maps native AR camera", """// Host proposal only: copy the previous solve's observer state, never its decision.
// state[0] flags: 1 centroid, 2 RANSAC, 4 refinement. state[1...3] centroid;
// [4...9] raw r/t; [10...15] refined r/t, in OpenCV's local centroid frame.
// Returns the selected inlier count, or -1 for insufficient output capacity.
int32_t hx_vision_trace(double* state,uint32_t state_capacity,uint32_t* indices,uint32_t index_capacity);
// Output maps native AR camera""")
    name = paths[1]
    s = once(result[name], "bool hxFinite(double x){return std::isfinite(x);}", """bool hxFinite(double x){return std::isfinite(x);}
// Fixed storage, no allocation, no extra solver call, and no RNG access.
struct PoseTrace {std::array<double,16> state{};std::array<uint32_t,2400> indices{};uint32_t count=0;};
thread_local PoseTrace poseTrace;
void tracePose(const cv::Mat& r,const cv::Mat& t,int offset){for(int i=0;i<3;i++){poseTrace.state[offset+i]=r.at<double>(i);poseTrace.state[offset+3+i]=t.at<double>(i);}}""")
    anchor = 'extern "C" int32_t hx_vision_pose('
    s = once(s, anchor, """extern "C" int32_t hx_vision_trace(double* state,uint32_t capacity,uint32_t* indices,uint32_t indexCapacity){
 if(!state||!indices||capacity<16||indexCapacity<poseTrace.count)return -1;
 std::copy(poseTrace.state.begin(),poseTrace.state.end(),state);
 std::copy_n(poseTrace.indices.begin(),poseTrace.count,indices);return int32_t(poseTrace.count);
}
""" + anchor)
    s = once(s, " if(!xyz||!xy||!output||!quality||n<30", " poseTrace={};\n if(!xyz||!xy||!output||!quality||n<30")
    s = once(s, " cv::Mat K=(cv::Mat_<double>(3,3)<<fx,0,cx,0,fy,cy,0,0,1),r,t,inliers;", """ poseTrace.state[0]=1;poseTrace.state[1]=origin.x;poseTrace.state[2]=origin.y;poseTrace.state[3]=origin.z;
 cv::Mat K=(cv::Mat_<double>(3,3)<<fx,0,cx,0,fy,cy,0,0,1),r,t,inliers;""")
    s = once(s, " quality->inliers=uint32_t(inliers.rows);", """ poseTrace.state[0]=3;tracePose(r,t,4);poseTrace.count=uint32_t(inliers.rows);
 for(int i=0;i<inliers.rows;i++)poseTrace.indices[i]=uint32_t(inliers.at<int>(i));
 quality->inliers=uint32_t(inliers.rows);""")
    s = once(s, " cv::solvePnPRefineLM(selected,observations,K,cv::noArray(),r,t);", """ cv::solvePnPRefineLM(selected,observations,K,cv::noArray(),r,t);
 poseTrace.state[0]=7;tracePose(r,t,10);""")
    result[name] = s
    name = paths[2]
    s = once(result[name], "enum VisualMapping {", """enum VisualMapping {
  // Set only by the isolated, serial host replay. Shipping source is untouched.
  static var poseObserver:(([String:Any])->Void)?
  static func observePose(kind:String,sourceIDs:[UUID],queryIndices:[Int],xyz:[Double],xy:[Double],width:Int,height:Int,intrinsics:[Double],status:Int32,matrix:[Double],quality:HXPoseQuality) {
    guard let observer=poseObserver else{return}
    var state=[Double](repeating:0,count:16),indices=[UInt32](repeating:0,count:2400)
    let count=state.withUnsafeMutableBufferPointer{s in indices.withUnsafeMutableBufferPointer{i in hx_vision_trace(s.baseAddress,16,i.baseAddress,2400)}}
    observer(["type":"solve","kind":kind,"sourceIDs":sourceIDs.map{$0.uuidString},"queryIndices":queryIndices,"xyz":xyz,"xy":xy,"width":width,"height":height,"intrinsics":intrinsics,"status":Int(status),"matrix":status==1 ? matrix:[],"rejection":Int(quality.rejection),"inlierCount":Int(quality.inliers),"inlierIndices":count>=0 ? Array(indices.prefix(Int(count))):[],"observerReadSucceeded":count>=0,"state":state])
  }""")
    # Every production pose call is observed, including the later consensus solve.
    anchor = '    diagnostic?("Pooled source group: '
    s = once(s, anchor, '    observePose(kind:"pooled",sourceIDs:sources.map{$0.id},queryIndices:points.map{$0.0},xyz:xyz,xy:xy,width:width,height:height,intrinsics:intrinsics,status:accepted,matrix:matrix,quality:quality)\n' + anchor)
    anchor = '      diagnostic?("view \\(view.observationID): matches '
    s = once(s, anchor, '      observePose(kind:"individual",sourceIDs:[view.observationID],queryIndices:(0..<Int(count)).map{Int(pairs[$0*2+1])},xyz:xyz,xy:xy,width:width,height:height,intrinsics:intrinsics,status:accepted,matrix:matrix,quality:quality)\n' + anchor)
    anchor = "    var xyz:[Double]=[],xy:[Double]=[]\n    for query in repeated.keys.sorted()"
    s = once(s, anchor, "    var xyz:[Double]=[],xy:[Double]=[];var traceQueries:[Int]=[]\n    for query in repeated.keys.sorted()")
    anchor = "      xyz += [point.x,point.y,point.z];xy += [Double(features.xy[query*2])*Double(width),Double(features.xy[query*2+1])*Double(height)]"
    s = once(s, anchor, anchor + "\n      traceQueries.append(query)")
    anchor = "    let transform=Rigid(values:matrix)"
    s = once(s, anchor, '    observePose(kind:"consensus",sourceIDs:candidates.flatMap{$0.pose.sources},queryIndices:traceQueries,xyz:xyz,xy:xy,width:width,height:height,intrinsics:intrinsics,status:accepted,matrix:matrix,quality:quality)\n' + anchor)
    result[name] = s
    name = paths[3]
    s = once(result[name], "import Foundation\n", "import Foundation\nimport Darwin\n")
    s = once(s, "@main struct VisionReplay {", SWIFT_WRITER + "\n@main struct VisionReplay {")
    s = once(s, '"--house","--coded"].contains($0)', '"--house","--coded","--pose-trace"].contains($0)')
    # One additional argument may coexist with the prior --audit observer patch.
    s = once(s, "guard (3...7).contains(CommandLine.arguments.count)", "guard (3...9).contains(CommandLine.arguments.count)")
    anchor = "  static func runHouse(root:URL,queriesURL:URL)throws {"
    s = once(s, anchor, anchor + """
    let trace:PoseTraceWriter?
    if CommandLine.arguments.contains("--pose-trace") {trace=try PoseTraceWriter(root:root)}else{trace=nil}
    defer{VisualMapping.poseObserver=nil}
    if let trace{VisualMapping.poseObserver={record in trace.record(record)}}""")
    s = once(s, 'if CommandLine.arguments.contains("--house"){try runHouse(root:root,queriesURL:queriesURL);return}',
      'if CommandLine.arguments.contains("--house"){do{try runHouse(root:root,queriesURL:queriesURL)}catch{if CommandLine.arguments.contains("--pose-trace"){PoseTraceFailure.emit(error)};throw error};return}')
    # Scope the remaining edits to runHouse, avoiding the coded/non-house loops.
    start = s.index(anchor)
    prefix, body = s[:start], s[start:]
    body = once(body, "    for index in house.segments.indices {", '    PoseTraceFailure.phase="mapping"\n    for index in house.segments.indices {')
    body = once(body, "    for q in queries.queries {", """    for q in queries.queries {
      PoseTraceFailure.phase="queries";trace?.begin(q.image)""")
    anchor = 'output.append(["image":q.image,"accepted":false,"reason":"Selected capture has no admitted map"]);continue'
    body = once(body, anchor, 'output.append(["image":q.image,"accepted":false,"reason":"Selected capture has no admitted map"]);trace?.end(accepted:false,reason:"no-map");continue')
    body = once(body, "      output.append(result)", '      output.append(result);trace?.end(accepted:pose != nil,reason:ambiguous ? "ambiguous":"evaluated")')
    anchor = '    let report:[String:Any]=["queries":output,"mapCount":maps.count'
    # Reuse the retained private source/map export after all candidate decisions.
    # Read its literal only; never execute the old mutating preparation script.
    prior = ast.parse((root / "experiments/localization-depth-audit/prepare.py").read_text())
    exports = [ast.literal_eval(node.value) for node in prior.body if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == "instrument" for target in node.targets)]
    if len(exports) != 1:
        raise ValueError("Retained private audit exporter changed")
    exports = exports[0].replace('contains("--audit")', 'contains("--pose-trace")')
    body = once(body, anchor, '    PoseTraceFailure.phase="trace-finalization"\n    try trace?.finish(expectedQueries:queries.queries.count)\n    PoseTraceFailure.phase="private-export"\n' + exports + '    PoseTraceFailure.phase="report"\n' + anchor)
    result[name] = prefix + body
    name = paths[4]
    s = once(result[name], "p.add_argument('--coded',action='store_true');a=p.parse_args()",
             "p.add_argument('--coded',action='store_true');p.add_argument('--pose-trace',action='store_true');a=p.parse_args()")
    s = once(s, "+(['--coded'] if a.coded else []),capture_output=True",
             "+(['--coded'] if a.coded else [])+(['--pose-trace'] if a.pose_trace else []),capture_output=True")
    s = once(s, " report=json.loads(result.stdout)", """ if a.pose_trace:
  with (candidate/'temp/pose-trace/trace.jsonl').open('rb') as trace_stream:
   candidate_trace_sha256=hashlib.file_digest(trace_stream,'sha256').hexdigest()
 report=json.loads(result.stdout)""")
    anchor = " a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))"
    s = once(s, anchor, """ if a.pose_trace:
  audit=a.output.with_suffix('.audit')
  shutil.copytree(candidate/'temp/audit',audit,dirs_exist_ok=True)
  shutil.copytree(candidate/'temp/pose-trace',audit/'pose-trace',dirs_exist_ok=True)
  (audit/'query-names.json').write_text(json.dumps(original_names,sort_keys=True))
  (audit/'oracle.json').write_text(json.dumps(oracle))
  shutil.copy2(fixture/'vision-map.hxray',audit/'input.hxray')
  (audit/'sealed-candidate.json').write_text(json.dumps(dict(candidateBinarySHA256=report['candidateBinarySHA256'],traceSHA256=candidate_trace_sha256,oracleReadDenied=report['oracleReadDenied'],queryLabelsExcluded=report['queryLabelsExcluded'])))
""" + anchor)
    s = once(s, "candidateRejected=True,error=result.stderr[-5000:]", "candidateRejected=True,observerFailure=read_failure(result.stderr),error=result.stderr[-5000:]")
    anchor = " result=subprocess.run(sandbox+[str(exe),str(candidate),str(candidate/'queries.json')]"
    s = once(s, anchor, """ if a.pose_trace:
  # Check the existing policy without granting another writable path. Failure
  # stops this diagnostic; the policy and oracle exclusion stay unchanged.
  writable=candidate/'temp/observer-write-control'
  forbidden=root/'observer-denied-write-control'
  allowed_write=subprocess.run(sandbox+['/usr/bin/touch',str(writable)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd=candidate)
  denied_write=subprocess.run(sandbox+['/usr/bin/touch',str(forbidden)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd=candidate)
  assert allowed_write.returncode==0 and writable.is_file() and denied_write.returncode!=0 and not forbidden.exists(), 'Observer write-isolation control failed'
  writable.unlink()
""" + anchor)
    # The harness parses only a fixed marker before private stderr is truncated.
    # This does not grant the native process access to any evaluator records.
    result[name] = (Path(__file__).with_name("failure_contract.py").read_text()+"\n"+s)
    return originals, result


SWIFT_WRITER = r'''enum PoseTraceFailure {
  static var phase="initialization",kind="unknown"
  static func emit(_ error:Error) {
    let native=error as NSError
    let domain=["NSCocoaErrorDomain","NSPOSIXErrorDomain"].contains(native.domain) ? native.domain:"other"
    let value:[String:Any]=["schema":1,"phase":phase,"kind":kind,"domain":domain,"code":native.code]
    if let data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) {
      try? FileHandle.standardError.write(contentsOf:Data("HX_POSE_OBSERVER_FAILURE ".utf8)+data+Data([10]))
    }
  }
}
// Private bounded JSONL trace. Failure marks the diagnostic incomplete after
// candidate decisions, never changes acceptance, and cannot be published as pass.
final class PoseTraceWriter {
  let file:FileHandle
  var failure:String?,failureKind="unknown",query="",queries=0,solves=0,bytes=0,sequence=0
  init(root:URL)throws {
    let folder=root.appendingPathComponent("temp/pose-trace",isDirectory:true)
    PoseTraceFailure.kind="directory"
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let path=folder.appendingPathComponent("trace.jsonl")
    PoseTraceFailure.kind="create"
    // Create only this new file in the already permitted private directory.
    // Preserve a real errno if creation fails; do not change sandbox policy.
    let descriptor=Darwin.open(path.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode_t(0o600))
    guard descriptor>=0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    file=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);PoseTraceFailure.kind="unknown"
    record(["type":"header","schema":1,"coordinateFrame":"centroid-local-opencv","limitBytes":1_073_741_824,"limitSolves":8192])
  }
  func record(_ value:[String:Any]) {
    guard failure==nil else{return}
    var operation="record-serialization"
    do {
      var row=value;row["sequence"]=sequence
      if value["type"] as? String == "solve" {solves+=1;row["query"]=query}
      let data=try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys])+Data([10])
      operation="record-bounds"
      guard data.count<=8_388_608,bytes<=1_073_741_824-data.count,solves<=8192 else{throw HouseError.message("Private trace budget exceeded.")}
      operation="record-write"
      try file.write(contentsOf:data);bytes+=data.count;sequence+=1
    }catch{failure=error.localizedDescription;failureKind=operation}
  }
  func begin(_ image:String){query=image;queries+=1;if queries>512{failure="Private query bound exceeded.";failureKind="query-bound"};record(["type":"begin","query":image])}
  func end(accepted:Bool,reason:String){record(["type":"end","query":query,"accepted":accepted,"reason":reason]);query=""}
  func finish(expectedQueries:Int)throws {
    if queries != expectedQueries || !query.isEmpty {failure="Trace query denominator mismatch.";failureKind="query-denominator"}
    record(["type":"footer","queries":queries,"solves":solves,"complete":failure==nil])
    PoseTraceFailure.kind="synchronize";try file.synchronize()
    PoseTraceFailure.kind="close";try file.close();PoseTraceFailure.kind="unknown"
    if let failure{PoseTraceFailure.kind=failureKind;throw HouseError.message(failure)}
  }
}'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("diff_output", type=Path)
    args = parser.parse_args()
    before, after = prepare(args.source_root)
    diff = "".join("".join(difflib.unified_diff(before[name].splitlines(True), after[name].splitlines(True),
                      fromfile="a/"+name, tofile="b/"+name)) for name in before)
    args.diff_output.write_text(diff)
    print("Review diff written; source files unchanged; no build or experiment executed.")
