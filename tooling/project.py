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

s=p.read_text()
if 'HXCORECPP0000000000000001' not in s:
 s=s.replace('\t"objects" = {','\t"objects" = {\n"HXCORECPP0000000000000001" = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.cpp; path = "../packages/spatial-core/hx_core.cpp"; sourceTree = "<group>"; };\n"HXCOREBUILD00000000000001" = {isa = PBXBuildFile; fileRef = HXCORECPP0000000000000001; };')
 s=s.replace('"534A5F435ADDB25DA9F43232",','"534A5F435ADDB25DA9F43232", "HXCOREBUILD00000000000001",')
 s=s.replace('"A33603BF79F74B056172D43B",','"A33603BF79F74B056172D43B", "HXCORECPP0000000000000001",')
 s=s.replace('"SWIFT_VERSION" = "5.0";', '"SWIFT_VERSION" = "5.0"; "SWIFT_OBJC_BRIDGING_HEADER" = "HouseMemoryProof/SpatialBridge.h"; "CLANG_CXX_LANGUAGE_STANDARD" = "c++17"; "CLANG_CXX_LIBRARY" = "libc++";')
p.write_text(s)

s=p.read_text()
if 'IFCFOLDER0000000000000001' not in s:
 s=s.replace('\t"objects" = {','\t"objects" = {\n"IFCFOLDER0000000000000001" = {isa = PBXFileReference; lastKnownFileType = folder; path = IFC; sourceTree = "<group>"; };\n"IFCRESOURCE00000000000001" = {isa = PBXBuildFile; fileRef = IFCFOLDER0000000000000001; };')
 s=s.replace('"6D3E1FE7B9D4981A01FED2ED",','"6D3E1FE7B9D4981A01FED2ED", "IFCRESOURCE00000000000001",')
 s=s.replace('"A33603BF79F74B056172D43B",','"A33603BF79F74B056172D43B", "IFCFOLDER0000000000000001",')
p.write_text(s)

# Native visual feature / pose core and official platform-specific static SDK.
s=p.read_text()
for name in ['hx_vision.cpp','hx_vision_test.cpp']:
 rid=hashlib.sha256(('vision-file:'+name).encode()).hexdigest()[:24].upper()
 bid=hashlib.sha256(('vision-build:'+name).encode()).hexdigest()[:24].upper()
 if rid not in s:
  s=s.replace('\t"objects" = {','\t"objects" = {\n'+f'"{rid}" = {{isa=PBXFileReference; lastKnownFileType=sourcecode.cpp.cpp; path="../packages/visual-core/{name}"; sourceTree="<group>";}};\n"{bid}" = {{isa=PBXBuildFile; fileRef="{rid}";}};')
  s=s.replace('"534A5F435ADDB25DA9F43232",','"534A5F435ADDB25DA9F43232", "'+bid+'",')
  s=s.replace('"A33603BF79F74B056172D43B",','"A33603BF79F74B056172D43B", "'+rid+'",')
if 'HXOPENCVFRAMEWORKFILE001' not in s:
 s=s.replace('\t"objects" = {','\t"objects" = {\n"HXOPENCVFRAMEWORKFILE001"={isa=PBXFileReference;lastKnownFileType=wrapper.xcframework;path="build/opencv/opencv2.xcframework";sourceTree=SOURCE_ROOT;};\n"HXOPENCVFRAMEWORKBUILD01"={isa=PBXBuildFile;fileRef=HXOPENCVFRAMEWORKFILE001;};')
 s=s.replace('"A33603BF79F74B056172D43B",','"A33603BF79F74B056172D43B", "HXOPENCVFRAMEWORKFILE001",')
 s=s.replace('"isa" = "PBXFrameworksBuildPhase";\n\t\t\t"buildActionMask" = 2147483647;\n\t\t\t"files" = (','"isa" = "PBXFrameworksBuildPhase";\n\t\t\t"buildActionMask" = 2147483647;\n\t\t\t"files" = ("HXOPENCVFRAMEWORKBUILD01",')
 s=s.replace('"CLANG_CXX_LIBRARY" = "libc++";', '"CLANG_CXX_LIBRARY" = "libc++"; "OTHER_LDFLAGS" = ("$(inherited)", "-framework", "Accelerate", "-lz");')
p.write_text(s)
