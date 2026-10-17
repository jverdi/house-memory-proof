from pathlib import Path
import hashlib
p=Path('HouseMemoryProof.xcodeproj/project.pbxproj');s=p.read_text()
def uid(x):return hashlib.sha256(('uitest:'+x).encode()).hexdigest()[:24].upper()
def obj(x,body):return '"'+uid(x)+'" = {'+body+'};\n'
if uid('target') not in s:
 blocks=obj('file','isa=PBXFileReference; lastKnownFileType=sourcecode.swift; path="HouseXrayUITests/Smoke.swift"; sourceTree=SOURCE_ROOT;')
 blocks+=obj('product','isa=PBXFileReference; explicitFileType="wrapper.cfbundle"; path=HouseXrayUITests.xctest; sourceTree=BUILT_PRODUCTS_DIR;')
 blocks+=obj('build','isa=PBXBuildFile; fileRef='+uid('file')+';')
 blocks+=obj('sources','isa=PBXSourcesBuildPhase; buildActionMask=2147483647; files=('+uid('build')+',); runOnlyForDeploymentPostprocessing=0;')
 for mode in ['Debug','Release']:
  blocks+=obj(mode,'isa=XCBuildConfiguration; name='+mode+'; buildSettings={PRODUCT_NAME="$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER=com.example.HouseXrayUITests; GENERATE_INFOPLIST_FILE=YES; TEST_TARGET_NAME=HouseMemoryProof; SWIFT_VERSION=5.0; SWIFT_OBJC_BRIDGING_HEADER=""; CODE_SIGNING_ALLOWED=NO; TARGETED_DEVICE_FAMILY=1; LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @loader_path/Frameworks";};')
 blocks+=obj('configs','isa=XCConfigurationList; buildConfigurations=('+uid('Debug')+','+uid('Release')+',); defaultConfigurationIsVisible=0; defaultConfigurationName=Release;')
 blocks+=obj('proxy','isa=PBXContainerItemProxy; containerPortal=244210E48437B6556980A702; proxyType=1; remoteGlobalIDString=C1E9827DB735CA9BAA54A540; remoteInfo=HouseMemoryProof;')
 blocks+=obj('dependency','isa=PBXTargetDependency; target=C1E9827DB735CA9BAA54A540; targetProxy='+uid('proxy')+';')
 blocks+=obj('target','isa=PBXNativeTarget; buildConfigurationList='+uid('configs')+'; buildPhases=('+uid('sources')+',); buildRules=(); dependencies=('+uid('dependency')+',); name=HouseXrayUITests; productName=HouseXrayUITests; productReference='+uid('product')+'; productType="com.apple.product-type.bundle.ui-testing";')
 s=s.replace('\t"objects" = {','\t"objects" = {\n'+blocks)
 s=s.replace('"targets" = (','"targets" = ("'+uid('target')+'",')
 p.write_text(s)
p=Path('HouseMemoryProof.xcodeproj/xcshareddata/xcschemes/HouseMemoryProof.xcscheme');s=p.read_text()
ref='<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+uid('target')+'" BuildableName="HouseXrayUITests.xctest" BlueprintName="HouseXrayUITests" ReferencedContainer="container:HouseMemoryProof.xcodeproj"/>'
s=s.replace('<Testables/>','<Testables><TestableReference skipped="NO">'+ref+'</TestableReference></Testables>');p.write_text(s)
