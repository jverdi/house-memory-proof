#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/blender-evidence
if [ ! -x build/blender/blender ]; then
  curl --fail --location --retry 3 https://download.blender.org/release/Blender4.5/blender-4.5.3.sha256 --output build/blender.sha256
  curl --fail --location --retry 3 https://download.blender.org/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz --output build/blender-4.5.3-linux-x64.tar.xz
  python3 - <<'PY'
from pathlib import Path
import hashlib,json
name='blender-4.5.3-linux-x64.tar.xz'
entries=[line.split() for line in Path('build/blender.sha256').read_text().splitlines()]
expected=[line[0] for line in entries if line[-1].lstrip('*')==name]
assert len(expected)==1 and len(expected[0])==64
actual=hashlib.sha256(Path('build',name).read_bytes()).hexdigest()
assert actual==expected[0]=='975c58fcb244273838534bba771e64ad87739216b0f9b39a888531a49a72d845'
Path('build/blender-evidence/dependency.json').write_text(json.dumps({'version':'4.5.3','source':'https://download.blender.org/release/Blender4.5/','sha256':actual},indent=2))
PY
  mkdir -p build/blender
  tar -xJf build/blender-4.5.3-linux-x64.tar.xz --strip-components=1 -C build/blender
  cp build/blender-evidence/dependency.json build/blender/dependency.json
fi
cp build/blender/dependency.json build/blender-evidence/dependency.json
build/blender/blender --version
