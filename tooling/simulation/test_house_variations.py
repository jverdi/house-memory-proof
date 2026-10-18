"""Independent aperture/occlusion invariants; not application qualification."""
import copy
import itertools
import math
import unittest
import numpy as np
from house import render
from house_topology import generate, geometry, topology_signature
from house_variations import vary, variant_geometry, subtract, validate_variant


def inside(point, item):
    return all(a<q<b for q,a,b in zip(point,item['low'],item['high']))


class AppearanceContract(unittest.TestCase):
    def test_baseline_is_unchanged_and_variants_are_deterministic(self):
        base=generate(70000);original=copy.deepcopy(base)
        self.assertEqual(vary(base,'baseline'),base)
        for stage in ['rough','finished']:
            self.assertEqual(variant_geometry(vary(base,'baseline'),stage),geometry(base,stage))
        self.assertEqual(vary(base,'windows-clutter'),vary(base,'windows-clutter'))
        self.assertEqual(base,original)
        self.assertEqual(topology_signature(base),topology_signature(vary(base,'windows-clutter')))

    def test_fifty_houses_include_windows_clutter_and_three_material_families(self):
        houses=[vary(generate(70000+i*7919),'windows-clutter') for i in range(50)]
        self.assertEqual({h['materialFamily'] for h in houses},{0,1,2})
        for h in houses:
            self.assertGreater(len(h['windows']),0);self.assertGreater(len(h['clutter']),0)
            validate_variant(h)
            for item in h['clutter']:
                for door in h['doors']:
                    # Independently probe the full portal volume. A clutter box
                    # must not block even an edge of a known door opening.
                    wall=next(w for w in h['walls'] if w['id']==door['wall']);axis=0 if wall['a'][1]==wall['b'][1] else 1
                    for offset in np.linspace(-door['width']/2,door['width']/2,7):
                        point=door['center'].copy();point[axis]+=offset;point[2]+=.5
                        self.assertFalse(inside(point,item))

    def test_box_subtraction_conserves_volume_and_has_no_overlapping_pieces(self):
        item=dict(id='wall',low=[0.,0.,0.],high=[4.,.2,3.],color=[1,2,3],trade='structure')
        cut=dict(low=[1.,-.1,1.],high=[2.,.3,2.])
        pieces=subtract(item,cut)
        volume=lambda x:math.prod(b-a for a,b in zip(x['low'],x['high']))
        self.assertAlmostEqual(sum(volume(p) for p in pieces),volume(item)-.2)
        for a,b in itertools.combinations(pieces,2):
            intersection=math.prod(max(0,min(a['high'][i],b['high'][i])-max(a['low'][i],b['low'][i])) for i in range(3))
            self.assertEqual(intersection,0)
        self.assertTrue(all(not inside([1.5,.1,1.5],p) for p in pieces))
        self.assertEqual(subtract(item,dict(low=[5.,0.,0.],high=[6.,1.,1.])),[item])

    def test_apertures_are_clear_but_jambs_sills_and_headers_are_solid(self):
        for seed in [70000,77919,85838]:
            h=vary(generate(seed),'windows-clutter')
            for stage in ['rough','finished']:
                shapes=variant_geometry(h,stage)
                self.assertEqual(len({g['id'] for g in shapes}),len(shapes))
                for w in h['windows']:
                    centre=[(a+b)/2 for a,b in zip(w['low'],w['high'])]
                    local=[g for g in shapes if g['id'].startswith(w['wall']+'-') or g['id'].startswith(w['id']+'-')]
                    self.assertFalse(any(inside(centre,g) for g in local))
                    for axis in [w['axis'],2]:
                        for side in [0,1]:
                            p=centre.copy();p[axis]=(w['low'][axis]-.019) if side==0 else (w['high'][axis]+.019)
                            self.assertTrue(any(inside(p,g) for g in local))

    def test_renderer_sees_through_open_window_without_invented_glass_depth(self):
        h=vary(generate(70000),'windows-clutter');w=h['windows'][0]
        centre=np.mean([w['low'],w['high']],axis=0);axis=w['axis'];cross=1-axis
        local=[g for g in variant_geometry(h,'finished') if g['id'].startswith(w['wall']+'-') or g['id'].startswith(w['id']+'-')]
        position=centre.copy();position[cross]+=1.
        forward=np.zeros(3);forward[cross]=-1;yaw=math.atan2(forward[0],forward[1])
        _,depth,valid,_,_,ids=render(local,position,yaw,128,96,visibility=True)
        self.assertFalse(valid[48,64]);self.assertEqual(depth[48,64],0);self.assertEqual(ids[48,64],-1)
        self.assertTrue(valid.any(),'The opening fixture must retain visible framing')

    def test_clutter_occludes_with_independent_foreground_depth(self):
        h=vary(generate(70000),'windows-clutter');item=h['clutter'][0]
        centre=np.mean([item['low'],item['high']],axis=0);position=centre+np.array([0.,-1.5,0.])
        wall=dict(id='background',low=(centre+[-2.,1.,-2.]).tolist(),high=(centre+[2.,1.1,2.]).tolist(),color=[200,200,200],trade='finish')
        _,depth,valid,_,_,ids=render([wall,item],position,0,128,96,visibility=True)
        self.assertTrue(valid[48,64]);self.assertEqual(ids[48,64],1)
        self.assertAlmostEqual(float(depth[48,64]),item['low'][1]-position[1],places=6)

    def test_historical_geometry_service_identity_and_unknown_connections_survive(self):
        base=generate(77919);h=vary(base,'windows-clutter')
        self.assertEqual(h['services'],base['services']);self.assertEqual(h['doors'],base['doors']);self.assertEqual(h['stairs'],base['stairs'])
        rough={g['id']:g for g in variant_geometry(h,'rough')};finished={g['id']:g for g in variant_geometry(h,'finished')}
        self.assertTrue(set(rough)<=set(finished))
        for key,value in rough.items():self.assertEqual(value,finished[key])
        with self.assertRaises(ValueError):variant_geometry(h,'planned-renovation')

    def test_invalid_material_window_service_and_clutter_contracts_refuse(self):
        h=vary(generate(70000),'windows-clutter');bad=[]
        x=copy.deepcopy(h);x['materialFamily']=99;bad.append(x)
        x=copy.deepcopy(h);x['windows'][0]['glazing']='transparent-glass';bad.append(x)
        x=copy.deepcopy(h);x['windows'][0]['high'][2]=999;bad.append(x)
        x=copy.deepcopy(h);x['windows'][0]['wall']=x['services'][0]['wall'];bad.append(x)
        x=copy.deepcopy(h);x['clutter'][0]['low'][2]+=.1;bad.append(x)
        x=copy.deepcopy(h);x['clutter'][0]['id']=x['windows'][0]['id'];bad.append(x)
        for x in bad:
            with self.assertRaises(ValueError):validate_variant(x)


if __name__=='__main__':unittest.main()
