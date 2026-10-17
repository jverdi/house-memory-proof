#!/bin/bash
set -euo pipefail
python3 -m venv build/simulation-env
build/simulation-env/bin/pip install --disable-pip-version-check numpy==2.3.5 pillow==11.3.0
build/simulation-env/bin/python tooling/simulation/house.py --seed 42 --output build/synthetic-house --rooms 3 --frames 24 --width 128
cp build/synthetic-house/candidate.hxray HouseMemoryProof/IFC/synthetic-house.hxray
cp build/synthetic-house/generator.json build/evidence/synthetic-house-generator.json

build/simulation-env/bin/python tooling/simulation/vision_fixture.py build/vision-fixture
cp build/vision-fixture/vision-map.hxray build/vision-fixture/vision-queries.json build/vision-fixture/vision-query-*.jpg HouseMemoryProof/IFC/
