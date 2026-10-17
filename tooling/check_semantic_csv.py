#!/usr/bin/env python3
"""Independent Python csv reader for the actual native Swift semantic export."""
import csv
import hashlib
import json
from pathlib import Path
import sys
from collections import Counter


def original(text):
    # V1 writer prefixes dangerous/literal-apostrophe text with one apostrophe.
    return text[1:] if text.startswith("'") else text


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('build/evidence')
    path = root / 'semantic.csv'
    source = json.loads((root / 'semantic-source.json').read_text())
    with path.open(newline='', encoding='utf-8') as stream:
        reader = csv.DictReader(stream, strict=True)
        rows = list(reader)
        assert len(reader.fieldnames) == 39 and len(set(reader.fieldnames)) == 39
    assert len(rows) == 17
    assert Counter(row['record_type'] for row in rows) == {
        'feature': 3, 'route_point': 6, 'endpoint': 6, 'measurement': 1, 'connection': 1}
    assert all(None not in row and None not in row.values() for row in rows)
    assert all(row['house_id'] == source['id'] and row['schema_version'] == '1' for row in rows)
    assert len({row['id'] for row in rows}) == len(rows)
    segments = {segment['id']: segment for segment in source['segments']}
    for feature in source['features']:
        row = next(r for r in rows if r['record_type'] == 'feature' and r['id'] == feature['id'])
        for key in ['name', 'notes']:
            assert original(row[key]) == feature[key]
        assert original(row['endpoint_label']) == feature['endpoint']
        assert row['trade'] == feature['trade'] and row['evidence_kind'] == feature['kind']
        assert row['hidden'] == str(feature['hidden']).lower()
        assert row['reviewed'] == str(feature['reviewed']).lower()
        assert original(row['room_name']) == 'Kitchen, café\nNorth' and row['level'] == '-1'
        assert row['stage_date'] == '2023-11-14T22:13:20.000Z'
        assert json.loads(row['source_ids_json']) == feature['sourceIDs']
        provenance = json.loads(row['provenance_json'])
        assert provenance['id'] == feature['id'] and provenance['notes'] == feature['notes']
        sid = feature.get('segmentID')
        expected_frame = 'segment:' + sid if sid else 'house'
        assert row['coordinate_frame'] == expected_frame
        if sid:
            frame = json.loads(row['registration_json'])
            assert frame['segmentID'] == sid
            assert frame.get('transform') == segments[sid].get('registration')
            assert frame['approved'] == segments[sid]['approved']
        else:
            assert row['registration_json'] == ''
        for kind, points in [('route_point', feature['route']),
                             ('endpoint', [feature['route'][0], feature['route'][-1]])]:
            children = sorted((r for r in rows if r['record_type'] == kind and r['parent_id'] == feature['id']),
                              key=lambda r: int(r['index']))
            assert len(children) == len(points)
            for index, (child, point) in enumerate(zip(children, points)):
                assert child['index'] == str(index) and child['coordinate_frame'] == expected_frame
                assert [float(child[axis + '_m']) for axis in 'xyz'] == [point[axis] for axis in 'xyz']
    a = next(r for r in rows if r['record_type'] == 'feature')
    assert a['name'] == "'=1+1"  # Quoting alone does not neutralize spreadsheet formulas.
    assert rows[5]['name'] == "''literal"
    measurement = next(r for r in rows if r['record_type'] == 'measurement')
    assert float(measurement['length_m']) == 5.0
    assert [float(measurement[k]) for k in ['x_m','y_m','z_m','x2_m','y2_m','z2_m']] == [-1,2,3,2,6,3]
    assert measurement['coordinate_frame'] == 'segment:' + source['dimensions'][0]['segmentID']
    assert measurement['date'] == '2023-11-14T22:13:20.000Z'
    connection = next(r for r in rows if r['record_type'] == 'connection')
    expected = source['connections'][0]
    for column, key in [('from_feature_id','fromFeature'), ('to_feature_id','toFeature'),
                        ('from_end','fromEnd'), ('to_end','toEnd')]:
        assert connection[column] == str(expected[key])
    assert connection['confirmed'] == 'true' and connection['notes'] == "'\t=HYPERLINK()"
    report = {'passed': True, 'reader': 'Python standard-library csv', 'records': len(rows),
              'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'separateFramesPreserved': True, 'registrationNotAppliedToSourceCoordinates': True,
              'unicodeMultilineAndQuotedTextPreserved': True, 'formulaTextEscaped': True,
              'sourceRelationshipsPreserved': True, 'physicalPrecisionQualified': False}
    (root / 'semantic-csv-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
