"""Check the signed release identity and retain matching symbols, never profiles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

def validate(info,entitlements,bundle,team,build,revision,distribution=True):
    expected={'CFBundleIdentifier':bundle,'CFBundleVersion':build,'ProofSourceRevision':revision[:10]}
    if any(info.get(k)!=v for k,v in expected.items()):raise ValueError('Archived bundle, build or source differs from the requested release.')
    if entitlements.get('application-identifier')!=team+'.'+bundle or entitlements.get('com.apple.developer.team-identifier')!=team:
        raise ValueError('Signed application identity differs from the configured personal team.')
    if distribution and entitlements.get('get-task-allow',False):raise ValueError('A distributable build must not enable debugger attachment.')
    if set(info.get('UIBackgroundModes',[]))-{'processing'}:raise ValueError('Unexpected background execution mode in signed archive.')
    if entitlements.get('com.apple.developer.background-tasks.continued-processing.gpu',False):
        raise ValueError('Background GPU signing is outside the currently qualified CPU-only policy.')

def digest(path):
    sha=hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''):sha.update(block)
    return sha.hexdigest()

def command(arguments):
    result=subprocess.run(arguments,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
    if result.returncode:raise RuntimeError('Signed archive inspection failed: '+arguments[0])
    return result.stdout,result.stderr

def inspect(app,archive,distribution):
    info=plistlib.loads((app/'Info.plist').read_bytes())
    command(['codesign','--verify','--deep','--strict',str(app)])
    stdout,stderr=command(['codesign','-d','--entitlements',':-',str(app)])
    raw=stdout+stderr;start=raw.find(b'<?xml');end=raw.find(b'</plist>',start)
    if start<0 or end<0:raise RuntimeError('Could not inspect the signed application entitlements.')
    entitlements=plistlib.loads(raw[start:end+8])
    full=command(['git','rev-parse','HEAD'])[0].decode().strip()
    validate(info,entitlements,os.environ['APP_BUNDLE_ID'],os.environ['APPLE_TEAM_ID'],os.environ['HOUSE_RELEASE_BUILD'],full,distribution=distribution)
    executable=app/info['CFBundleExecutable'];symbols=archive/'dSYMs'
    def uuids(path):return set(re.findall(r'UUID: ([A-Fa-f0-9-]{36})',command(['dwarfdump','--uuid',str(path)])[0].decode()))
    binary_ids=uuids(executable);symbol_ids=set()
    for path in symbols.glob('*.dSYM'):symbol_ids.update(uuids(path))
    if not binary_ids or not binary_ids.issubset(symbol_ids):raise RuntimeError('Release symbols do not match the archived executable.')
    output=Path('build/evidence/release-symbols.zip')
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED,allowZip64=True) as target:
        for path in sorted(symbols.rglob('*')):
            if path.is_file():target.write(path,path.relative_to(symbols))
    report=dict(sourceRevision=full,embeddedSourceRevision=info['ProofSourceRevision'],build=info['CFBundleVersion'],
        bundleIdentifier=info['CFBundleIdentifier'],signatureVerified=True,archiveIdentityVerified=True,releaseIdentityVerified=distribution,
        phase='distribution' if distribution else 'archive',
        debuggerAttachmentAllowed=bool(entitlements.get('get-task-allow',False)),backgroundGPURequested=False,matchingSymbolUUIDs=sorted(binary_ids),
        executableSHA256=digest(executable),symbolsSHA256=digest(output),physicalDeviceQualified=False)
    return report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--export-directory',type=Path);args=parser.parse_args()
    archive=Path('build/HouseMemoryProof.xcarchive')
    if args.export_directory:
        packages=list(args.export_directory.glob('*.ipa'))
        if len(packages)!=1:raise RuntimeError('Expected exactly one exported distribution IPA.')
        package=packages[0]
        with zipfile.ZipFile(package) as source:
            names=[Path(item.filename) for item in source.infolist()]
            if any(p.is_absolute() or '..' in p.parts for p in names):raise RuntimeError('Export contains an unsafe path.')
        with tempfile.TemporaryDirectory(prefix='house-distribution-inspection-') as folder:
            # Preserve framework links and file modes from Xcode's own export.
            command(['ditto','-x','-k',str(package),folder])
            apps=list((Path(folder)/'Payload').glob('*.app'))
            if len(apps)!=1:raise RuntimeError('Expected exactly one exported application.')
            report=inspect(apps[0],archive,distribution=True)
        report.update(inspectedIPASHA256=digest(package),inspectedIPABytes=package.stat().st_size,uploaded=False)
        name='signed-release-manifest.json'
    else:
        apps=list((archive/'Products/Applications').glob('*.app'))
        if len(apps)!=1:raise RuntimeError('Expected exactly one archived application.')
        # Xcode can development-sign an archive before re-signing at export.
        # This phase verifies source/team/symbols but cannot qualify distribution.
        report=inspect(apps[0],archive,distribution=False)
        name='signed-archive-manifest.json'
    Path('build/evidence',name).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()
