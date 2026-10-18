import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import zipfile
from interchange_check import COLUMNS,semantic_csv,mesh,usdz
from package_check import InvalidPackage


class InterchangeContracts(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)/'semantic.csv'
        house,room,feature=[str(uuid.uuid4()) for _ in range(3)]
        origin=dict(schema_version='1',house_id=house,house_revision='3',room_id=room,coordinate_frame='house')
        provenance=dict(id=feature,roomID=room,name='Valve, café\nEast',notes='=text',trade='plumbing',kind='observed',hidden=False,reviewed=True,sourceIDs=[])
        self.rows=[dict(origin,record_type='feature',id=feature,name=provenance['name'],notes="'=text",trade='plumbing',evidence_kind='observed',hidden='false',reviewed='true',source_ids_json='[]',provenance_json=json.dumps(provenance))]
        for kind in ['route_point','endpoint']:
            for i,x in enumerate([0,2]):
                self.rows.append(dict(origin,record_type=kind,id=feature+':'+kind+':'+str(i),parent_id=feature,index=str(i),x_m=str(x),y_m='0',z_m='1'))

    def write(self):
        with self.path.open('w',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=COLUMNS);writer.writeheader();writer.writerows(self.rows)

    def test_csv_unicode_relationships_provenance_and_independent_roundtrip(self):
        self.write();before=self.path.read_bytes();result=semantic_csv(self.path)
        self.assertTrue(result['passed']);self.assertTrue(result['csvRoundTripPassed'])
        self.assertEqual(result['records'],5);self.assertEqual(self.path.read_bytes(),before)

    def test_csv_refuses_dangling_scope_false_endpoints_and_changed_provenance(self):
        from copy import deepcopy
        baseline=deepcopy(self.rows)
        for change in [lambda r:r[1].update(parent_id=str(uuid.uuid4())),
                       lambda r:r[2].update(coordinate_frame='segment:'+str(uuid.uuid4())),
                       lambda r:r[-1].update(x_m='3'),lambda r:r[0].update(name='Changed'),
                       lambda r:r[0].update(notes='=text'),lambda r:r[1].update(x_m='NaN'),
                       lambda r:r[2].update(index='0'),lambda r:r[0].update(room_id=str(uuid.uuid4()))]:
            self.rows=deepcopy(baseline);change(self.rows);self.write()
            with self.assertRaises(InvalidPackage):semantic_csv(self.path)

    def test_csv_preserves_whitespace_only_text(self):
        self.rows[0]['notes']='   '
        source=json.loads(self.rows[0]['provenance_json']);source['notes']='   '
        self.rows[0]['provenance_json']=json.dumps(source);self.write()
        self.assertTrue(semantic_csv(self.path)['passed'])

    def test_csv_validates_typed_service_provenance_without_inventing_unknowns(self):
        source=json.loads(self.rows[0]['provenance_json'])
        source['service']=dict(port='P-24',installationDate='2024-02-29')
        self.rows[0]['provenance_json']=json.dumps(source);self.write()
        self.assertTrue(semantic_csv(self.path)['passed'])
        source['service']['installationDate']='2025-02-29'
        self.rows[0]['provenance_json']=json.dumps(source);self.write()
        with self.assertRaisesRegex(InvalidPackage,'date'):semantic_csv(self.path)

    def test_obj_external_material_refused_without_loading_a_reader(self):
        path=self.path.with_suffix('.obj');path.write_text('mtllib ../private.mtl\nv 0 0 0\n')
        with self.assertRaisesRegex(InvalidPackage,'External OBJ'):mesh(path)

    def test_csv_envelope_dates_use_iso8601_without_weakening_archive_dates(self):
        from package_check import envelope_check
        source=json.loads(self.rows[0]['provenance_json'])
        envelope=dict(version=1,sourceFeatureID=str(uuid.uuid4()),sourceRevision=1,sourceInterval=0,
            section='Round',widthMetres=.05,evidence='Synthetic outer size',recorded='2024-02-29T12:34:56Z')
        source['envelope']=envelope
        self.rows[0]['provenance_json']=json.dumps(source);self.write()
        self.assertTrue(semantic_csv(self.path)['passed'])
        with self.assertRaisesRegex(InvalidPackage,'date'):envelope_check(envelope)
        for bad in [0,None,'2025-02-29T12:34:56Z','2024-02-29T12:34:56','not a date']:
            envelope['recorded']=bad;self.rows[0]['provenance_json']=json.dumps(source);self.write()
            with self.assertRaisesRegex(InvalidPackage,'date'):semantic_csv(self.path)

    def test_usdz_compression_and_alignment_fail_before_openusd(self):
        path=self.path.with_suffix('.usdz')
        for compression in [zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED]:
            with zipfile.ZipFile(path,'w',compression=compression) as archive:archive.writestr('house.usda','#usda 1.0\n')
            with self.assertRaisesRegex(InvalidPackage,'aligned|compression'):usdz(path)


if __name__=='__main__':unittest.main()
