#!/usr/bin/env python3
# Add source references deterministically to the existing signed project.
from pathlib import Path
import hashlib,re
p=Path('HouseMemoryProof.xcodeproj/project.pbxproj');s=p.read_text()
for f in sorted(Path('HouseMemoryProof').glob('*.swift')):
 if f.name=='HouseMemoryProofApp.swift':continue
 rid=hashlib.sha256(('file:'+f.name).encode()).hexdigest()[:24].upper()
 bid=hashlib.sha256(('build:'+f.name).encode()).hexdigest()[:24].upper()
 if rid in s:continue
 block=f'\t\t"{rid}" = {{ "isa" = "PBXFileReference"; "lastKnownFileType" = "sourcecode.swift"; "path" = "{f.name}"; "sourceTree" = "<group>"; }};\n\t\t"{bid}" = {{ "isa" = "PBXBuildFile"; "fileRef" = "{rid}"; }};\n'
 s=s.replace('\t"objects" = {','\t"objects" = {\n'+block)
 s=s.replace('"534A5F435ADDB25DA9F43232",','"534A5F435ADDB25DA9F43232",\n\t\t\t\t"'+bid+'",')
 s=s.replace('"A33603BF79F74B056172D43B",','"A33603BF79F74B056172D43B",\n\t\t\t\t"'+rid+'",')
s=s.replace('"IPHONEOS_DEPLOYMENT_TARGET" = "18.0"','"IPHONEOS_DEPLOYMENT_TARGET" = "26.0"')
p.write_text(s)
