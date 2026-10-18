"""Instrument only the isolated host candidate; do not change shipping kernels.

Exports derived maps, native grayscale/features and input bytes after candidate
execution for development diagnosis. These files remain in the ephemeral CI working directory and are never
uploaded; a separate evaluator publishes only aggregate error measurements. Candidate oracle access remains denied throughout execution.
"""
from pathlib import Path

root=Path(__file__).resolve().parents[2]
p=root/'tooling/simulation/VisionReplay.swift';s=p.read_text()
old='["--refine","--bundle","--house","--coded"].contains($0)'
assert s.count(old)==1;s=s.replace(old,'["--refine","--bundle","--house","--coded","--audit"].contains($0)')
anchor='    let report:[String:Any]=["queries":output,"mapCount":maps.count,"mappingFailures":failures'
assert s.count(anchor)==1
instrument='''    if CommandLine.arguments.contains("--audit") {
      let audit=root.appendingPathComponent("temp/audit",isDirectory:true)
      try FileManager.default.createDirectory(at:audit,withIntermediateDirectories:true)
      let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
      for (identity,map) in maps {try encoder.encode(map).write(to:audit.appendingPathComponent("map-"+identity.uuidString+".json"))}
      var sources:[[String:Any]]=[]
      for observation in house.observations {
        let data=try DiskEvidence(root).read(observation.image)
        let (gray,w,h)=try VisualMapping.image(data)
        let raw=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
        let features=try VisualMapping.cameraFeatures(raw,imageWidth:w,imageHeight:h,cameraWidth:observation.width,cameraHeight:observation.height)
        let filename="source-"+observation.id.uuidString+".gray"
        try gray.write(to:audit.appendingPathComponent(filename))
        sources.append(["observationID":observation.id.uuidString,"gray":filename,"grayWidth":w,"grayHeight":h,"cameraWidth":observation.width,"cameraHeight":observation.height,"camera":cameras[observation.id.uuidString] ?? observation.camera,"intrinsics":observation.intrinsics,"xy":features.xy,"descriptors":features.descriptors.base64EncodedString(),"count":features.count])
      }
      var queryImages:[[String:Any]]=[]
      for query in queries.queries {
        let (gray,w,h)=try VisualMapping.image(Data(contentsOf:root.appendingPathComponent(query.image)))
        let raw=try VisualMapping.detect(gray:gray,width:w,height:h,stride:w)
        let features=try VisualMapping.cameraFeatures(raw,imageWidth:w,imageHeight:h,cameraWidth:query.width,cameraHeight:query.height)
        let filename="query-"+query.image+".gray"
        try gray.write(to:audit.appendingPathComponent(filename))
        queryImages.append(["image":query.image,"gray":filename,"grayWidth":w,"grayHeight":h,"cameraWidth":query.width,"cameraHeight":query.height,"intrinsics":query.intrinsics,"xy":features.xy,"descriptors":features.descriptors.base64EncodedString(),"count":features.count])
      }
      try JSONSerialization.data(withJSONObject:["sources":sources,"queries":queryImages],options:[.sortedKeys]).write(to:audit.appendingPathComponent("images.json"))
    }
'''
s=s.replace(anchor,instrument+anchor);p.write_text(s)
p=root/'tooling/simulation/replay_fixture.py';s=p.read_text()
old="p.add_argument('--coded',action='store_true');a=p.parse_args()"
assert s.count(old)==1;s=s.replace(old,"p.add_argument('--coded',action='store_true');p.add_argument('--audit',action='store_true');a=p.parse_args()")
old="+(['--coded'] if a.coded else []),capture_output=True"
assert s.count(old)==1;s=s.replace(old,"+(['--coded'] if a.coded else [])+(['--audit'] if a.audit else []),capture_output=True")
old=" a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))"
assert s.count(old)==1
new=''' if a.audit:
  audit=a.output.with_suffix('.audit');shutil.copytree(candidate/'temp/audit',audit,dirs_exist_ok=True)
  (audit/'query-names.json').write_text(json.dumps(original_names,sort_keys=True))
  (audit/'oracle.json').write_text(json.dumps(oracle))
  shutil.copy2(fixture/'vision-map.hxray',audit/'input.hxray')
  (audit/'sealed-candidate.json').write_text(json.dumps(dict(candidateBinarySHA256=report['candidateBinarySHA256'],oracleReadDenied=report['oracleReadDenied'],queryLabelsExcluded=report['queryLabelsExcluded'])))
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2))'''
s=s.replace(old,new);p.write_text(s)
print('Host-only diagnostics prepared; shipping map/query kernels unchanged')
