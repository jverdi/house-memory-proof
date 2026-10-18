import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import warnings
import zipfile
from package_check import check_package, InvalidPackage


def fixture():
    room, stage, segment, feature, observation = [str(uuid.uuid4()) for _ in range(5)]
    raw = b'original image bytes'
    key = hashlib.sha256(raw).hexdigest()+'.jpg'
    pose = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    house = dict(schema=1,id=str(uuid.uuid4()),revision=4,
        rooms=[dict(id=room,origin=dict(x=0,y=0,z=0),size=dict(x=3,y=4,z=2.5))],
        stages=[dict(id=stage)],segments=[dict(id=segment,roomID=room,stageID=stage,registration=dict(values=pose))],
        features=[dict(id=feature,roomID=room,stageID=stage,segmentID=segment,
                      mesh=dict(vertices=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0),dict(x=0,y=1,z=0)],triangles=[0,1,2]))],
        observations=[dict(id=observation,roomID=room,stageID=stage,segmentID=segment,image=key,camera=pose,
                           intrinsics=[100,0,60,0,100,40,0,0,1],width=120,height=80,timestamp=1)])
    return house, {'assets/'+key:raw}


def archive(path, house, payload, modify=None):
    parts = {'house.json':json.dumps(house).encode(), 'index.html':b'index', 'viewer.html':b'viewer', **payload}
    manifest = dict(format='HouseXray',version=1,sha256={k:hashlib.sha256(v).hexdigest() for k,v in parts.items()})
    parts['manifest.json'] = json.dumps(manifest).encode()
    if modify:
        modify(parts)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as out:
        for name,data in parts.items():
            out.writestr(name,data)


class PortablePackageContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)/'house.hxray'
        self.house, self.parts = fixture()

    def test_actual_inventory_hashes_and_semantics_without_extraction(self):
        archive(self.path,self.house,self.parts)
        before = self.path.read_bytes()
        report = check_package(self.path)
        self.assertTrue(report['passed'])
        self.assertEqual(report['verifiedOriginals'],1)
        self.assertEqual(report['semanticCounts']['triangles'],1)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(list(Path(self.temp.name).iterdir()),[self.path])

    def test_project_reader_versions_are_explicit_and_sources_remain_unchanged(self):
        for schema in [1,2,3,4,5,0,6,999]:
            self.house['schema']=schema;archive(self.path,self.house,self.parts);before=self.path.read_bytes()
            if schema in [1,2,3,4,5]:self.assertTrue(check_package(self.path)['passed'])
            else:
                with self.assertRaisesRegex(InvalidPackage,'schema'):check_package(self.path)
            self.assertEqual(self.path.read_bytes(),before)

    def test_ifc_origin_and_crs_roundtrip_and_malformed_refusal(self):
        reference=dict(version=1,converter='web-ifc-0.0.72',sourceSchema='IFC4',sourceLengthUnit='MILLI METRE',originMetres=dict(x=1000000,y=0,z=0),mapConversions=[dict(expressID=32,values=dict(Scale=.001,Eastings=500000.25),targetCRS=dict(Name='EPSG:32632'))])
        raw=b'original IFC';key=hashlib.sha256(raw).hexdigest()+'.ifc';self.parts['assets/'+key]=raw
        self.house['drawings']=[dict(id=str(uuid.uuid4()),asset=key,ifcCoordinates=reference)]
        archive(self.path,self.house,self.parts);before=self.path.read_bytes();self.assertTrue(check_package(self.path)['passed']);self.assertEqual(self.path.read_bytes(),before)
        mutations=[lambda r:r.update(version=2),lambda r:r['originMetres'].update(x=1e10),lambda r:r['mapConversions'][0]['values'].update(Unknown=1),lambda r:r['mapConversions'][0]['values'].update(Scale=True),lambda r:r['mapConversions'][0]['targetCRS'].update(Name='bad\0CRS'),lambda r:r['mapConversions'].append(copy.deepcopy(r['mapConversions'][0]))]
        for mutate in mutations:
            bad=copy.deepcopy(self.house);mutate(bad['drawings'][0]['ifcCoordinates']);archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_ifc_property_graph_archive_links_raw_units_and_forgery_refusal(self):
        raw=b'Original IFC retained verbatim';source_hash=hashlib.sha256(raw).hexdigest();source_key=source_hash+'.ifc'
        summary=dict(products=2,representedProducts=1,convertedProducts=1,unconvertedRepresentedProducts=0,storeys=1,records=4,malformedGUIDs=0,missingGUIDs=0,duplicateGUIDs=0)
        obj=dict(expressID=22,typeName='IFCBUILDINGELEMENTPROXY',guid='1J$yPqHBD2TuLf$X2etp$1',guidStatus='valid')
        storey=dict(expressID=40,typeName='IFCBUILDINGSTOREY',guid='2J$yPqHBD2TuLf$X2etp$2',guidStatus='valid')
        value=lambda text:dict(type=1,value=text)
        ref=lambda key:dict(type=5,value=key)
        graph=dict(version=1,converter='web-ifc-0.0.72',sourceSchema='IFC4',sourceSHA256=source_hash,rawSourceValues=True,excludedForwardFields=['OwnerHistory','Representation','RepresentationMaps'],summary=summary,
            products=[dict(**obj,represented=True,converted=True),dict(**storey,represented=False,converted=False)],
            storeys=[dict(expressID=40,name='Upper floor',elevation=3000)],records=[
                dict(expressID=22,typeName=obj['typeName'],fields=dict(GlobalId=value(obj['guid']),Representation=ref(21),OwnerHistory=ref(5),Unit=ref(12))),
                dict(expressID=40,typeName=storey['typeName'],fields=dict(GlobalId=value(storey['guid']),Name=value('Upper floor'),Elevation=dict(type=4,value=3000))),
                dict(expressID=41,typeName='IFCRELCONTAINEDINSPATIALSTRUCTURE',fields=dict(RelatedElements=[ref(22)],RelatingStructure=ref(40))),
                dict(expressID=12,typeName='IfcSIUnit',fields=dict(Dimensions=ref(0)),derivedFields=['Dimensions'])])
        self.parts['assets/'+source_key]=raw;drawing_id=str(uuid.uuid4())
        self.house['schema']=4
        self.house['drawings']=[dict(id=drawing_id,asset=source_key,ifcCoordinates=dict(version=1,converter='web-ifc-0.0.72',sourceSchema='IFC4',sourceLengthUnit='MILLI METRE',originMetres=dict(x=0,y=0,z=0),mapConversions=[]))]
        self.house['features'][0].update(kind='planned',sourceDrawingID=drawing_id,ifcObject=obj)
        def write(candidate):
            data=json.dumps(candidate).encode();key=hashlib.sha256(data).hexdigest()+'.json'
            house=copy.deepcopy(self.house);house['drawings'][0]['ifcProperties']=dict(asset=key,sourceSHA256=source_hash,summary=candidate['summary'])
            archive(self.path,house,{**self.parts,'assets/'+key:data});return house
        write(graph);before=self.path.read_bytes();self.assertTrue(check_package(self.path)['passed']);self.assertEqual(self.path.read_bytes(),before)
        mutations=[lambda g:g['summary'].update(convertedProducts=2),
            lambda g:g['records'][2]['fields'].update(RelatingStructure=ref(999)),
            lambda g:g['products'].append(copy.deepcopy(g['products'][0])),
            lambda g:g['products'][0].update(guidStatus='missing'),
            lambda g:g.update(sourceSHA256='0'*64),lambda g:g.update(version=True),
            lambda g:g['records'][0]['fields'].update(Text='é'*2049),
            lambda g:g['storeys'][0].update(elevation=3),lambda g:g['records'][3].update(derivedFields=[]),lambda g:g['records'][3].update(typeName='IfcOtherType'),lambda g:g['records'][3]['fields'].update(Dimensions=ref(999))]
        for mutate in mutations:
            candidate=copy.deepcopy(graph);mutate(candidate);write(candidate)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        self.house['features'][0]['ifcObject']=storey;write(graph)
        with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_measured_envelope_mesh_and_provenance_are_checked_independently(self):
        source=self.house['features'][0];source['route']=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0)]
        envelope=copy.deepcopy(source);envelope.update(id=str(uuid.uuid4()),kind='synthetic',annotationSources=[dict(featureID=source['id'],revision=1,segmentID=source['segmentID'])])
        envelope['envelope']=dict(version=1,sourceFeatureID=source['id'],sourceRevision=1,sourceInterval=0,section='Rectangular',widthMetres=.2,heightMetres=.1,widthAxis=dict(x=0,y=1,z=0),evidence='Synthetic measured size',recorded=0)
        vertices=[dict(x=x,y=y,z=z) for x in [0,1] for y,z in [(-.1,-.05),(.1,-.05),(.1,.05),(-.1,.05)]]+source['route']
        triangles=[]
        for i in range(4):j=(i+1)%4;triangles += [i,j,i+4,j,j+4,i+4,8,j,i,9,i+4,j+4]
        envelope['mesh']=dict(vertices=vertices,triangles=triangles);self.house['features'].append(envelope);self.house['schema']=5
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])
        for field,value in [('widthMetres',0),('heightMetres',True),('widthAxis',dict(x=1,y=0,z=0)),('dimensionToleranceMetres',.2),('evidence',''),('sourceRevision',2),('version',True),('recorded','2024-02-29T12:34:56Z')]:
            bad=copy.deepcopy(self.house);bad['features'][1]['envelope'][field]=value;archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        for field in ['vertices','triangles']:
            bad=copy.deepcopy(self.house)
            if field=='vertices':bad['features'][1]['mesh'][field][0]['y']+=.01
            else:bad['features'][1]['mesh'][field][0]=3
            archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_drawing_marks_keep_original_proposals_and_old_sources_without_geometry(self):
        raw=b'%PDF synthetic source';old=hashlib.sha256(raw).hexdigest()+'.pdf'
        self.parts['assets/'+old]=raw
        points=[dict(u=.1,v=.2),dict(u=.6,v=.4)]
        mark=dict(id=str(uuid.uuid4()),sourceAsset=old,page=0,kind='Room name',points=points,label='Owner correction',reviewed=True,method='visionText',originalPoints=points,originalLabel='ROOM A',profileHash='9f858468f850556e2d7799d6389e839e53bf6c16ef58e5af5d3c92e85893dc36',runtime='Synthetic contract',rawScore=.7)
        current=b'%PDF revised';key=hashlib.sha256(current).hexdigest()+'.pdf';self.parts['assets/'+key]=current
        self.house.update(schema=5,drawings=[dict(id=str(uuid.uuid4()),asset=key,marks=[mark])])
        archive(self.path,self.house,self.parts);before=self.path.read_bytes()
        self.assertTrue(check_package(self.path)['passed']);self.assertEqual(self.path.read_bytes(),before)
        for field,value in [('page',True),('page',-1),('reviewed',1),('profileHash','0'*64),('rawScore',True),('originalPoints',None),('method','manual'),('label','bad\0label')]:
            bad=copy.deepcopy(self.house);bad['drawings'][0]['marks'][0][field]=value;archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        bad=copy.deepcopy(self.house);bad['drawings'][0]['marks']*=2;archive(self.path,bad,self.parts)
        with self.assertRaises(InvalidPackage):check_package(self.path)
        parts=dict(self.parts);parts.pop('assets/'+old);archive(self.path,self.house,parts)
        with self.assertRaises(InvalidPackage):check_package(self.path)
        polygon=dict(id=str(uuid.uuid4()),sourceAsset=key,page=1,kind='Possible boundary',points=[dict(u=0,v=0),dict(u=1,v=1),dict(u=0,v=1),dict(u=.8,v=0)],label='Crossed boundary',reviewed=False,method='manual')
        self.house['drawings'][0]['marks']=[polygon];archive(self.path,self.house,self.parts)
        with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_changed_original_and_incomplete_manifest_fail(self):
        for mutate in [lambda p:p.__setitem__(next(iter(self.parts)),b'changed'),
                       lambda p:p.__setitem__('unlisted.txt',b'forgotten'),
                       lambda p:p.pop(next(iter(self.parts)))]:
            archive(self.path,self.house,self.parts,mutate)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_service_details_dates_boundary_scope_and_confirmation_evidence(self):
        boundary=str(uuid.uuid4())
        self.house['boundaries']=[dict(id=boundary,segmentID=self.house['segments'][0]['id'])]
        details=dict(classification='Low voltage',observedLabel='Café cable',port='P-24',installationDate='2024-02-29',boundaryID=boundary,confidence='Owner confirmed',identityEvidence='Synthetic continuity test')
        self.house['features'][0]['service']=details
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])

        for key,value in [('installationDate','2025-02-29'),('installationDate','2024-2-29'),('installationDate','0000-01-01'),('observedLabel','é'*2049),('port','bad\0port'),('classification','invented'),('identityEvidence',' \n'),('boundaryID',str(uuid.uuid4()))]:
            bad=copy.deepcopy(self.house);bad['features'][0]['service'][key]=value
            archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        other=str(uuid.uuid4());self.house['stages'].append(dict(id=other));self.house['features'][0]['stageID']=other
        archive(self.path,self.house,self.parts)
        with self.assertRaisesRegex(InvalidPackage,'scope'):check_package(self.path)
        self.house['features'][0]['service']={}
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])

    def test_declared_point_cloud_requires_original_source_and_known_coordinates(self):
        raw=b'original synthetic PLY';key=hashlib.sha256(raw).hexdigest()+'.ply';drawing=str(uuid.uuid4())
        self.parts['assets/'+key]=raw
        self.house['drawings']=[dict(id=drawing,asset=key)]
        feature=self.house['features'][0];feature['sourceDrawingID']=drawing;feature['importedCoordinates']=dict(unit='Millimetres',upright='Y up')
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])
        for change in [lambda f:f['importedCoordinates'].update(unit='Unknown'),lambda f:f['importedCoordinates'].update(upright='Z down'),lambda f:f.update(sourceDrawingID=str(uuid.uuid4())),lambda f:f.pop('segmentID')]:
            bad=copy.deepcopy(self.house);change(bad['features'][0]);archive(self.path,bad,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_point_provenance_requires_existing_same_session_originals(self):
        source=self.house['observations'][0]
        self.house['observations']=[dict(source,id=str(uuid.uuid4())) for _ in range(3)]
        controls=[dict(observationID=o['id'],u=.5,v=.4) for o in self.house['observations']]
        feature=self.house['features'][0];feature['sourceIDs']=[c['observationID'] for c in controls]
        feature['pointTracks']=[dict(controls=copy.deepcopy(controls)) for _ in feature['mesh']['vertices']]
        feature['photoControls']=copy.deepcopy(controls)
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])
        for mode in ['missing','different-session','unlisted','bad-coordinate','missing-track','duplicate']:
            house=copy.deepcopy(self.house);item=house['features'][0]
            if mode=='missing':
                identifier=str(uuid.uuid4());item['sourceIDs'].append(identifier);item['pointTracks'][0]['controls'][0]['observationID']=identifier
            elif mode=='different-session':
                other=dict(house['segments'][0],id=str(uuid.uuid4()));house['segments'].append(other);house['observations'][0]['segmentID']=other['id']
            elif mode=='unlisted':item['sourceIDs']=[]
            elif mode=='bad-coordinate':item['photoControls'][0]['u']=1.1
            elif mode=='missing-track':item['pointTracks'].pop()
            else:item['pointTracks'][0]['controls'][1]=item['pointTracks'][0]['controls'][0]
            archive(self.path,house,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_single_photo_annotations_keep_2d_coordinates_and_refuse_malformed_marks(self):
        points=[dict(u=.1,v=.2),dict(u=.8,v=.7),dict(u=.3,v=.9)]
        marks=[dict(id=str(uuid.uuid4()),kind=kind,points=points[:count],label='Visible only',reviewed=False)
               for kind,count in [('point',1),('box',2),('polygon',3),('curve',3)]]
        photo=dict(id=str(uuid.uuid4()),image=self.house['observations'][0]['image'],annotations=marks)
        self.house['documentaryPhotos']=[photo]
        archive(self.path,self.house,self.parts)
        self.assertEqual(check_package(self.path)['semanticCounts']['imageAnnotations'],4)
        for mode in ['bounds','count','duplicate','unknown','zero-box','repeated-curve','collinear','room','label']:
            house=copy.deepcopy(self.house);photo=house['documentaryPhotos'][0];marks=photo['annotations']
            if mode=='bounds':marks[0]['points'][0]['u']=-.1
            elif mode=='count':marks[2]['points'].pop()
            elif mode=='duplicate':marks.append(marks[0])
            elif mode=='unknown':marks[0]['kind']='3d-point'
            elif mode=='zero-box':marks[1]['points'][1]=marks[1]['points'][0]
            elif mode=='repeated-curve':marks[3]['points'][1]=marks[3]['points'][0]
            elif mode=='collinear':marks[2]['points']=[dict(u=x,v=x) for x in [.1,.2,.3]]
            elif mode=='room':photo['roomID']=str(uuid.uuid4())
            else:marks[0]['label']='x'*4097
            archive(self.path,house,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)
        self.house['documentaryPhotos'][0].pop('annotations')
        archive(self.path,self.house,self.parts);self.assertTrue(check_package(self.path)['passed'])

    def test_rehashed_metadata_cannot_hide_semantic_corruption(self):
        faults = [lambda h:h['observations'][0].__setitem__('segmentID',str(uuid.uuid4())),
                  lambda h:h['features'][0]['mesh'].__setitem__('triangles',[0,1,10]),
                  lambda h:h['observations'][0]['camera'].__setitem__(0,2),
                  lambda h:h['rooms'].append(copy.deepcopy(h['rooms'][0])),
                  lambda h:h['observations'][0].__setitem__('image',hashlib.sha256(b'missing').hexdigest()+'.jpg'),
                  lambda h:h['features'][0]['mesh']['vertices'][0].__setitem__('x',float('nan'))]
        for mutate in faults:
            h=copy.deepcopy(self.house);mutate(h);archive(self.path,h,self.parts)
            with self.assertRaises(InvalidPackage):check_package(self.path)

    def test_duplicate_zip_and_unsafe_member_fail_before_extraction(self):
        archive(self.path,self.house,self.parts)
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(self.path,'a') as out:out.writestr('house.json',b'{}')
        with self.assertRaisesRegex(InvalidPackage,'Duplicate ZIP'):check_package(self.path)
        for name in ['../escape','/absolute','a/../b','a\\b']:
            archive(self.path,self.house,{**self.parts,name:b'payload'})
            with self.assertRaisesRegex(InvalidPackage,'Unsafe'):check_package(self.path)

    def test_duplicate_json_and_unreferenced_original_fail(self):
        archive(self.path,self.house,self.parts,lambda p:p.__setitem__('manifest.json',b'{"version":1,"version":2}'))
        with self.assertRaisesRegex(InvalidPackage,'Duplicate JSON'):check_package(self.path)
        extra=b'unreferenced';key='assets/'+hashlib.sha256(extra).hexdigest()+'.jpg'
        archive(self.path,self.house,{**self.parts,key:extra})
        with self.assertRaisesRegex(InvalidPackage,'inventory mismatch'):check_package(self.path)


if __name__=='__main__':unittest.main()
