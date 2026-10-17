#!/bin/bash
set -euo pipefail
npm install --prefix build/ifc-runtime --ignore-scripts --no-audit --no-fund web-ifc@0.0.72
cp build/ifc-runtime/node_modules/web-ifc/web-ifc-api-iife.js HouseMemoryProof/IFC/
cp build/ifc-runtime/node_modules/web-ifc/web-ifc.wasm HouseMemoryProof/IFC/
cp build/ifc-runtime/node_modules/web-ifc/LICENSE.md HouseMemoryProof/IFC/
cp build/ifc-runtime/package-lock.json build/evidence/ifc-package-lock.json
cp fixtures/block.ifc HouseMemoryProof/IFC/test-block.ifc
