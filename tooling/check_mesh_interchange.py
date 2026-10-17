#!/usr/bin/env python3
"""Read native exports independently; expected geometry is deliberately asymmetric.

Reader API: https://trimesh.org/quick_start.html (process=False preserves data).
This fixture checks interchange, not reconstruction or physical accuracy.
"""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
import trimesh

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('build/evidence')
EXPECTED_VERTICES = np.array([
    [0, 0, 0], [1, 0, 0], [0, 2, 0], [0, 0, 3],
    [4, -3, 3], [2, -2, 3], [4, -2, 4],
], dtype=float)
EXPECTED_FACES = np.array([[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3], [4, 5, 6]])


def oriented_triangles(vertices, faces):
    # Readers may reorder vertices/faces or cycle a face, but must not reverse it.
    result = []
    for face in vertices[faces]:
        points = [tuple(float(x) for x in p) for p in face]
        result.append(min(tuple(points[i:] + points[:i]) for i in range(3)))
    return sorted(result)


def verify(path):
    mesh = trimesh.load_mesh(path, process=False, maintain_order=True)
    assert len(mesh.vertices) == 7 and len(mesh.faces) == 5, (path, mesh.vertices, mesh.faces)
    assert np.isfinite(mesh.vertices).all()
    assert sorted(map(tuple, mesh.vertices)) == sorted(map(tuple, EXPECTED_VERTICES)), path
    assert oriented_triangles(mesh.vertices, mesh.faces) == oriented_triangles(EXPECTED_VERTICES, EXPECTED_FACES), path
    assert np.array_equal(mesh.bounds, [[0, -3, 0], [4, 2, 4]]), (path, mesh.bounds)
    return {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'vertices': len(mesh.vertices), 'triangles': len(mesh.faces),
            'boundsMetres': mesh.bounds.tolist(), 'orientedGeometryMatches': True}


def main():
    assert trimesh.__version__ == '5.1.1', trimesh.__version__
    results = [verify(ROOT / ('interchange.' + ext)) for ext in ['ply', 'obj']]
    # OBJ groups are part of the handoff contract, separate from geometry parsing.
    groups = [line.split()[1] for line in (ROOT / 'interchange.obj').read_text().splitlines() if line.startswith('g ')]
    assert groups == ['feature_11111111_1111_4111_8111_111111111111',
                      'feature_22222222_2222_4222_8222_222222222222'], groups
    report = {'passed': True, 'reader': 'trimesh ' + trimesh.__version__,
              'units': 'metres', 'upAxis': 'Z', 'registrationAppliedExactlyOnce': True,
              'hiddenGeometryExcluded': True, 'physicalPrecisionQualified': False,
              'files': results, 'objGroups': groups}
    (ROOT / 'mesh-interchange-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
