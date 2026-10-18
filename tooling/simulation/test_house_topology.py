"""Independent dimensional/topological checks; not candidate qualification."""
import copy
import math
import unittest
import numpy as np
from house import render
from house_topology import generate,geometry,topology_signature,validate


class WholeHouseContract(unittest.TestCase):
    def test_fifty_distinct_connected_development_topologies(self):
        houses=[generate(70000+i*7919) for i in range(50)]
        self.assertEqual(len({topology_signature(h) for h in houses}),50)
        self.assertEqual({h['levels'] for h in houses},{1,2,3})
        self.assertTrue(any(r['openPlan'] for h in houses for r in h['rooms']))
        self.assertTrue(any(r['ceilingDrop'] for h in houses for r in h['rooms']))
        for h in houses:
            graph={i:set() for i in range(len(h['rooms']))}
            for edge in h['doors']+h['stairs']:
                a,b=edge['rooms'];graph[a].add(b);graph[b].add(a)
            seen=set();queue=[0]
            while queue:
                n=queue.pop()
                if n in seen:continue
                seen.add(n);queue.extend(graph[n]-seen)
            self.assertEqual(len(seen),len(h['rooms']))
            occupied=[(r['level'],x,y) for r in h['rooms'] for x,y in r['cells']]
            self.assertEqual(len(occupied),len(set(occupied)))
            for r in h['rooms']:
                p=r['polygon'];area=abs(sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2)
                self.assertAlmostEqual(area,len(r['cells'])*h['pitch']**2,places=7)

    def test_stage_additions_preserve_original_assemblies_and_service_graphs(self):
        for seed in range(8):
            h=generate(seed);rough={g['id']:g for g in geometry(h,'rough')};finished={g['id']:g for g in geometry(h,'finished')}
            self.assertEqual(len(rough),len(geometry(h,'rough')))
            self.assertTrue(set(rough)<=set(finished))
            for identity in rough:self.assertEqual(rough[identity],finished[identity])
            self.assertTrue(all(not s['connectedTo'] for s in h['services']))
            self.assertTrue(all(s['stages']==['rough','finished'] for s in h['services']))
            self.assertFalse(h['stages'][-1]['observed'])
            with self.assertRaises(ValueError):geometry(h,'planned-renovation')

    def test_portal_centres_are_open_in_both_stages(self):
        for seed in range(8):
            h=generate(seed)
            for stage in ['rough','finished']:
                shapes=geometry(h,stage)
                for door in h['doors']:
                    x,y,z=door['center'];probe=np.array([x,y,z+1.])
                    wall_shapes=[g for g in shapes if g['id'].startswith(door['wall']+'-')]
                    self.assertTrue(wall_shapes)
                    self.assertFalse(any(np.all(probe>=g['low']) and np.all(probe<=g['high']) for g in wall_shapes))
                    jamb=np.array(probe);wall=next(w for w in h['walls'] if w['id']==door['wall']);axis=0 if wall['a'][1]==wall['b'][1] else 1
                    jamb[axis]+=door['width']/2+.1
                    self.assertTrue(any(np.all(jamb>=g['low']) and np.all(jamb<=g['high']) for g in wall_shapes))

    def test_stairs_have_contiguous_treads_and_an_open_upper_floor(self):
        for seed in range(12):
            h=generate(seed);shapes=geometry(h,'finished')
            for stair in h['stairs']:
                x,y,z=stair['origin'];treads=[g for g in shapes if g['id'].startswith(stair['id']+'-step-')]
                self.assertEqual(len(treads),stair['steps'])
                for i,tread in enumerate(treads):
                    self.assertAlmostEqual(tread['high'][2],z+(i+1)*stair['rise']/stair['steps'])
                    if i:self.assertAlmostEqual(treads[i-1]['high'][1],tread['low'][1])
                    px=x+stair['width']/2;py=(tread['low'][1]+tread['high'][1])/2
                    blockers=[g for g in shapes if g['trade'] in ['floor','ceiling'] and g['low'][0]<px<g['high'][0] and g['low'][1]<py<g['high'][1] and tread['high'][2]+.01<g['low'][2]<tread['high'][2]+2.]
                    self.assertFalse(blockers,'Floor/ceiling blocks the generated stair headroom')
                self.assertLess(stair['upperLandingY'],h['pitch'])

    def test_finished_layers_occlude_cavity_services(self):
        h=generate(0);route=next(r for r in h['services'] if r['kind']=='electrical');wall=next(w for w in h['walls'] if w['id']==route['wall'])
        point=np.array(route['points'][0],float);axis=0 if wall['a'][1]==wall['b'][1] else 1;cross=1-axis
        point[axis]+=.08;side=1 if point[cross]>wall['a'][cross] else -1
        position=point.copy();position[cross]=wall['a'][cross]+side
        forward=np.zeros(3);forward[cross]=-side;yaw=math.atan2(forward[0],forward[1])
        rgb,rough,valid,_,_=render(geometry(h,'rough'),position,yaw,128,96)
        finished_rgb,finished,finished_valid,_,_=render(geometry(h,'finished'),position,yaw,128,96)
        self.assertTrue(valid[48,64] and finished_valid[48,64]);self.assertLess(finished[48,64],rough[48,64]-.02)
        self.assertGreater(int(rgb[48,64,0]),int(rgb[48,64,2])*2)
        self.assertLess(abs(int(finished_rgb[48,64,0])-int(finished_rgb[48,64,2])),10)

    def test_invalid_layouts_are_refused(self):
        h=next(generate(i) for i in range(20) if generate(i)['stairs'])
        variants=[]
        bad=copy.deepcopy(h);bad['rooms'][1]['id']=bad['rooms'][0]['id'];variants.append(bad)
        bad=copy.deepcopy(h);bad['doors'][0]['width']=99;variants.append(bad)
        bad=copy.deepcopy(h);bad['stairs']=[];variants.append(bad)
        bad=copy.deepcopy(h);bad['rooms'][0]['polygon'][0][0]+=.1;variants.append(bad)
        bad=copy.deepcopy(h);bad['services'][0]['connectedTo']=[bad['services'][1]['id']];variants.append(bad)
        for bad in variants:
            with self.assertRaises(ValueError):validate(bad)


if __name__=='__main__':unittest.main()
