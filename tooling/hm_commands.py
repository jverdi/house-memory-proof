"""Repository command adapters. No provisioning or dependency installation."""
import hashlib
from contextlib import contextmanager
import html
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid
import zipfile
from package_check import check_package, json_bytes, semantic_check, required_assets, MAX_METADATA, MAX_ARCHIVE

ROOT = Path(__file__).resolve().parents[1]


def write_report(report, output=None):
    text = json.dumps(report, indent=2, allow_nan=False)+'\n'
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text)
    print(text, end='')
    return 0 if report.get('passed', True) else 1


def doctor(live=False):
    names = ['c++','python3','node','xcodebuild','xcrun','git','gh','openssl']
    capabilities = {name:bool(shutil.which(name)) for name in names}
    source=None;dirty=None
    if capabilities['git']:
        try:
            checked=subprocess.run(['git','rev-parse','--verify','HEAD'],cwd=ROOT,capture_output=True,text=True,timeout=5)
            if checked.returncode==0 and re.fullmatch('[0-9a-f]{40}',checked.stdout.strip()):
                source=checked.stdout.strip()
                status=subprocess.run(['git','status','--porcelain','--untracked-files=no'],cwd=ROOT,capture_output=True,text=True,timeout=5)
                if status.returncode==0:dirty=bool(status.stdout.strip())
        except (OSError,subprocess.TimeoutExpired):pass
    expected=os.environ.get('GITHUB_SHA','')
    expected=expected if re.fullmatch('[0-9a-f]{40}',expected) else None
    report = dict(platform=platform.system(), tools=capabilities,
                repository=dict(requiredSourceFilesPresent=all((ROOT/p).is_file() for p in ['tooling/hm','HouseMemoryProof/Domain.swift','HouseMemoryProof.xcodeproj/project.pbxproj']),
                    gitSource=source,trackedFilesModified=dirty,runnerExpectedSource=expected,sourceMatchesRunner=source==expected if source and expected else None),
                runner=dict(provider='GitHub Actions' if os.environ.get('GITHUB_ACTIONS')=='true' else 'local',architecture=platform.machine(),
                    hostDiskFreeBytes=shutil.disk_usage(ROOT).free,physicalPhoneCapabilitiesVerified=False),
                portableCoreAvailable=capabilities['c++'],
                nativeSimulatorAvailable=platform.system()=='Darwin' and capabilities['xcrun'] and capabilities['xcodebuild'],
                githubCredentialPresent=any(bool(os.environ.get(k)) for k in ['GH_TOKEN','GITHUB_TOKEN']),
                appleCredentialNamesPresent=[k for k in ['ASC_KEY_ID','ASC_ISSUER_ID','ASC_PRIVATE_KEY_P8'] if os.environ.get(k)],
                networkChecked=False, accountAccessVerified=False, provisioningPerformed=False,
                note='Presence checks only. release-health --live verifies read access without provisioning.')
    if live:
        sys.path.insert(0,str(ROOT/'ci'))
        import release_health
        snapshot=release_health.collect_live()
        health=release_health.summarize(snapshot,json.loads((ROOT/'ci/release-policy.json').read_text()))
        verified=health['appleReadAccessVerified'] and health['githubReadAccessVerified']
        attempted=all(snapshot.get(service,{}).get('networkAttempted',snapshot.get(service,{}).get('readAccessVerified') is True) for service in ['apple','github'])
        report.update(passed=verified,networkChecked=attempted,networkChecksRequested=True,accountAccessVerified=verified,
            appleReadAccessVerified=health['appleReadAccessVerified'],githubReadAccessVerified=health['githubReadAccessVerified'],
            checkedUTC=health['checkedUTC'],readOnly=True,errors=health['errors'],
            note='Live read access only. Signing, agreements, physical installation and field qualification remain separate checks.')
    return report


def run_suite(name, output=None):
    suites = {
        'simulation':[sys.executable,'-m','unittest','discover','-s','tooling/simulation','-p','test_*.py'],
        'release':[sys.executable,'-m','unittest','discover','-s','ci','-p','test_*.py'],
        'commands':[sys.executable,'-m','unittest','discover','-s','tooling','-p','test_*.py'],
    }
    command = suites[name]
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    # Unittest diagnostics contain fixture failures, not credential values.
    if result.stdout:sys.stderr.write(result.stdout)
    if result.stderr:sys.stderr.write(result.stderr)
    count = re.search(r'Ran (\d+) tests?',result.stderr)
    return write_report(dict(suite=name,passed=result.returncode==0,tests=int(count[1]) if count else None,
                             seconds=time.monotonic()-started,exitCode=result.returncode),output)


def copy_bounded(source, destination, remaining):
    total = 0
    with destination.open('xb') as target:
        while chunk := source.read(1024*1024):
            total += len(chunk)
            if total > remaining:raise ValueError('Scene input exceeds 500 GB staging budget')
            target.write(chunk)
    return total


def stage_scene(scene, destination):
    destination.mkdir()
    (destination/'assets').mkdir()
    if scene.is_file() and zipfile.is_zipfile(scene):
        check_package(scene)
        with zipfile.ZipFile(scene) as archive:
            metadata = archive.read('house.json')
            house = json_bytes(metadata)
            (destination/'house.json').write_bytes(metadata)
            remaining = MAX_ARCHIVE-len(metadata)
            for key in sorted(required_assets(house)):
                with archive.open('assets/'+key) as source:
                    remaining -= copy_bounded(source,destination/'assets'/key,remaining)
    else:
        path = scene/'house.json' if scene.is_dir() else scene
        if path.is_symlink() or path.stat().st_size > MAX_METADATA:raise ValueError('Unsafe or oversized scene metadata')
        metadata = path.read_bytes();house = json_bytes(metadata);semantic_check(house)
        (destination/'house.json').write_bytes(metadata)
        remaining = MAX_ARCHIVE-len(metadata)
        assets = path.parent/'assets'
        for key in sorted(required_assets(house)):
            source_path = assets/key
            if source_path.is_symlink() or not source_path.is_file():raise ValueError('Original is missing or unsafe')
            with source_path.open('rb') as source:
                remaining -= copy_bounded(source,destination/'assets'/key,remaining)
    return hashlib.sha256(metadata).hexdigest()


@contextmanager
def native_request(scene, request, simulator, bundle, timeout):
    if platform.system() != 'Darwin' or not shutil.which('xcrun'):
        raise ValueError('This command uses the production app. Run on macOS with an explicitly selected booted simulator and installed Debug build.')
    container = subprocess.run(['xcrun','simctl','get_app_container',simulator,bundle,'data'],check=True,capture_output=True,text=True,timeout=20)
    data = Path(container.stdout.strip())
    legacy = data/'Library/Application Support/HouseXray'
    root = legacy if (legacy/'house.sqlite').exists() else data/'Documents/HouseXray'
    identifier = str(uuid.uuid4()).upper()
    request_dir = root/'developer-commands'/identifier
    request_dir.mkdir(parents=True)
    launched = False
    try:
        digest = stage_scene(scene,request_dir/'input')
        request = dict(request,schema=1,houseSHA256=digest)
        (request_dir/'request.json').write_text(json.dumps(request))
        subprocess.run(['xcrun','simctl','terminate',simulator,bundle],capture_output=True,timeout=20)
        launched = True
        subprocess.run(['xcrun','simctl','launch',simulator,bundle,'--developer-command',identifier],check=True,capture_output=True,timeout=20)
        deadline = time.monotonic()+timeout
        last_progress=None
        while not (request_dir/'result.json').exists() and time.monotonic()<deadline:
            progress=request_dir/'progress.json'
            if progress.exists() and progress.stat().st_size<4096:
                state=json_bytes(progress.read_bytes());current=(state.get('action'),state.get('completedSessions'))
                if current!=last_progress:
                    print(json.dumps(dict(nativeProgress=state)),file=sys.stderr);last_progress=current
            time.sleep(.25)
        if not (request_dir/'result.json').exists():raise ValueError('Native command timed out; verify the installed Debug source supports --developer-command')
        if (request_dir/'result.json').stat().st_size>4_000_000:raise ValueError('Native command result exceeds its budget')
        result = json_bytes((request_dir/'result.json').read_bytes())
        if result.get('passed') or result.get('completed'):
            if result.get('houseSHA256') != digest:raise ValueError('Native result does not identify the staged scene')
        yield result,request_dir/'output',digest
    finally:
        if launched:
            subprocess.run(['xcrun','simctl','terminate',simulator,bundle],capture_output=True,timeout=20)
        # Only this command's UUID-owned staging directory is removed.
        shutil.rmtree(request_dir)


def tour(scene, preset, duration, simulator, bundle, output, timeout=180):
    if not 5 <= duration <= 60:raise ValueError('Duration must be between 5 and 60 seconds')
    if output.exists():raise ValueError('Choose a new output directory; existing artifacts are preserved')
    request=dict(command='tour',preset=preset,duration=duration)
    with native_request(scene,request,simulator,bundle,timeout) as (result,source,digest):
        if not result.get('passed'):
            output.mkdir(parents=True)
            (output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
            plan_file=source/'tour.json'
            if plan_file.is_file() and result.get('houseSHA256')==digest:
                shutil.copyfile(plan_file,output/'tour.json')
            return result
        if result.get('houseSHA256') != digest:raise ValueError('Native result does not identify the staged scene')
        plan = json_bytes((source/'tour.json').read_bytes())
        previews = result.get('previews',[])
        if not 1 <= len(previews) <= 8 or not all(isinstance(n,str) and re.fullmatch(r'preview-\d+\.png',n) for n in previews):
            raise ValueError('Invalid native storyboard inventory')
        output.mkdir(parents=True)
        for name in ['tour.json',*previews]:shutil.copyfile(source/name,output/name)
        (output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        cards = []
        for name in previews:
            shot = plan['shots'][int(name[8:-4])]
            cards.append('<figure><img src="'+name+'" alt="'+html.escape(shot['caption'],quote=True)+'"><figcaption>'+html.escape(shot['caption'])+'</figcaption></figure>')
        exclusions=''.join('<li>'+html.escape(x)+'</li>' for x in plan['excluded'])
        notice='SYNTHETIC DEMONSTRATION. ' if plan.get('synthetic') else 'Approximate captured geometry. '
        if any(s.get('reveal') for s in plan['shots']):notice+='Recorded evidence only; uncaptured areas remain unknown. '
        page='<!doctype html><meta charset="utf-8"><title>House Xray tour storyboard</title><style>body{font:16px system-ui;margin:2rem;background:#101923;color:#eee}figure{display:inline-block;max-width:640px;margin:1rem}img{width:100%}</style><h1>Tour storyboard</h1><p>'+notice+str(len(previews))+' previews from '+str(len(plan['shots']))+' shots. The full timeline is in <a href="tour.json">tour.json</a>.</p>'+''.join(cards)+'<h2>Excluded regions</h2><ul>'+exclusions+'</ul>'
        (output/'index.html').write_text(page)
        return result


def reconstruct(scene,kind,segment,simulator,bundle,output,timeout=900):
    if output.exists():raise ValueError('Choose a new output directory; existing artifacts are preserved')
    if kind not in ['points','surface','complete']:raise ValueError('Unsupported native reconstruction kind')
    request=dict(command='reconstruct',kind=kind,segmentID=str(uuid.UUID(segment)) if segment else None)
    with native_request(scene,request,simulator,bundle,timeout) as (result,source,_):
        output.mkdir(parents=True)
        if result.get('completed'):
            if result.get('archive')!='reconstruction.hxray':raise ValueError('Unexpected native reconstruction output')
            shutil.copyfile(source/'reconstruction.hxray',output/'reconstruction.hxray')
            result['independentArchiveCheck']=check_package(output/'reconstruction.hxray')
        (output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
        return result


def check_export(package):
    extension=package.suffix.lower()
    if extension=='.glb':
        result=subprocess.run(['node',str(ROOT/'tooling/model_check.cjs'),str(package)],capture_output=True,text=True,timeout=120)
        report=json_bytes(result.stdout.encode())
        report['passed']=result.returncode==0 and report.get('passed') is True
        return report
    if extension in ['.ply','.obj','.usdz','.csv']:
        from interchange_check import mesh,usdz,semantic_csv
        return (usdz if extension=='.usdz' else semantic_csv if extension=='.csv' else mesh)(package)
    return check_package(package)
