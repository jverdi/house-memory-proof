"""Additional evaluator-only appearance/occlusion cases, never oracle inputs.

The baseline topology/geometry remains byte-for-byte reproducible. Open windows
have no glass: this AABB renderer cannot model transparent/refractive depth.
Materials are diffuse colour/texture families, not photorealistic sensor models.
"""
import copy
import math
import random
from house_topology import geometry, stable, validate


VARIANTS = ('baseline', 'windows-clutter')
PALETTES = (
    {'structure': [158, 113, 72], 'floor': [119, 83, 57], 'finish': [231, 225, 209], 'ceiling': [235, 230, 218]},
    {'structure': [188, 159, 119], 'floor': [154, 143, 126], 'finish': [173, 189, 196], 'ceiling': [211, 216, 221]},
    {'structure': [112, 84, 60], 'floor': [86, 75, 65], 'finish': [191, 182, 163], 'ceiling': [224, 218, 203]},
)


def overlaps(a, b, margin=0.):
    return all(a['low'][i] < b['high'][i]+margin and b['low'][i] < a['high'][i]+margin for i in range(3))


def vary(base, variant):
    if variant not in VARIANTS:
        raise ValueError('Unknown scene variant')
    house = copy.deepcopy(base)
    if variant == 'baseline':
        return house
    rng = random.Random(stable(base['seed'], 'appearance-v1'))
    house['sceneVariant'] = variant
    house['materialFamily'] = rng.randrange(len(PALETTES))
    house['windows'] = []
    house['clutter'] = []
    occupied_service_walls = {r['wall'] for r in house['services']}
    available = [w for w in house['walls'] if len(w['rooms']) == 1 and w['id'] not in occupied_service_walls]
    rng.shuffle(available)
    # Never cut an existing service or create a doorway/graph edge. Deliberate
    # penetrations/changed routes need their own dated scenario and truth.
    for wall in available[:max(1, len(available)//2)]:
        a, b = wall['a'], wall['b']; axis = 0 if a[1] == b[1] else 1; cross = 1-axis
        width = rng.uniform(.85, 1.65); height = rng.uniform(.65, 1.05)
        centre = (a[axis]+b[axis])/2; z = wall['level']*house['rise']
        low = [0., 0., z+.95]; high = [0., 0., z+.95+height]
        low[axis] = centre-width/2; high[axis] = centre+width/2
        low[cross] = a[cross]-.1; high[cross] = a[cross]+.1
        house['windows'].append(dict(id=stable(base['seed'], 'window-'+wall['id']), wall=wall['id'], room=wall['rooms'][0],
            low=low, high=high, axis=axis, stages=['rough', 'finished'], glazing='open'))
    # Reserve the full stair bay and a conservative strip around each portal.
    # Clutter can occlude a photographed wall, but cannot seal a generated door.
    reserved=[]
    for door in house['doors']:
        wall=next(w for w in house['walls'] if w['id']==door['wall'])
        axis=0 if wall['a'][1]==wall['b'][1] else 1; cross=1-axis
        low=list(door['center']); high=list(door['center'])
        low[axis]-=door['width']/2+.35; high[axis]+=door['width']/2+.35
        low[cross]-=1.1; high[cross]+=1.1; high[2]+=2.3
        reserved.append(dict(low=low,high=high))
    for index, room in enumerate(house['rooms']):
        placed=[]
        for cell in room['cells']:
            if tuple(cell)==(0,0) and house['levels']>1:
                continue
            for attempt in range(4):
                width=rng.uniform(.35,.85); depth=rng.uniform(.35,.85); height=rng.uniform(.45,1.35)
                x=(cell[0]+rng.choice([.28,.72]))*house['pitch']; y=(cell[1]+rng.choice([.28,.72]))*house['pitch']; z=room['elevation']
                item=dict(id=stable(base['seed'], f'clutter-{index}-{cell}-{attempt}'),room=index,
                    low=[x-width/2,y-depth/2,z],high=[x+width/2,y+depth/2,z+height],
                    color=rng.choice([[126,96,66],[84,99,105],[155,147,129]]),trade='clutter',
                    textureless=rng.choice([False,True]),stages=['rough','finished'])
                if any(overlaps(item,other,.15) for other in reserved+placed):
                    continue
                placed.append(item)
                if len(placed)>=2:
                    break
            if len(placed)>=2:
                break
        house['clutter'].extend(placed)
    validate_variant(house)
    return house


def subtract(item, cut):
    """Disjoint AABBs whose union is item minus its open-window intersection."""
    if not overlaps(item, cut):
        return [copy.deepcopy(item)]
    lo=[max(a,b) for a,b in zip(item['low'],cut['low'])]
    hi=[min(a,b) for a,b in zip(item['high'],cut['high'])]
    remaining_low=list(item['low']); remaining_high=list(item['high']); pieces=[]
    for axis in range(3):
        for side in (0,1):
            low=remaining_low.copy(); high=remaining_high.copy()
            if side==0: high[axis]=lo[axis]
            else: low[axis]=hi[axis]
            if all(b-a>1e-10 for a,b in zip(low,high)):
                changed=copy.deepcopy(item);changed.update(id=item['id']+f'-aperture-{axis}-{side}',low=low,high=high);pieces.append(changed)
        remaining_low[axis]=lo[axis];remaining_high[axis]=hi[axis]
    return pieces


def variant_geometry(house, stage):
    shapes=geometry(house,stage)
    if house.get('sceneVariant','baseline')=='baseline':
        return shapes
    validate_variant(house)
    palette=PALETTES[house['materialFamily']]
    result=[]
    for item in shapes:
        pieces=[item]
        for window in house['windows']:
            if item['id'].startswith(window['wall']+'-'):
                pieces=[piece for candidate in pieces for piece in subtract(candidate,window)]
        for piece in pieces:
            if piece['trade'] in palette:
                piece['color']=palette[piece['trade']].copy()
            result.append(piece)
    for window in house['windows']:
        lo=window['low'];hi=window['high'];axis=window['axis'];cross=1-axis
        for label,direction,side in [('jamb-left',axis,0),('jamb-right',axis,1),('sill',2,0),('header',2,1)]:
            low=lo.copy(); high=hi.copy();low[cross]+=.03;high[cross]-=.03
            if side==0:low[direction]-=.038;high[direction]=lo[direction]
            else:low[direction]=hi[direction];high[direction]+=.038
            result.append(dict(id=window['id']+'-'+label,low=low,high=high,color=palette['structure'].copy(),trade='structure'))
    for item in house['clutter']:
        if stage in item['stages']:
            result.append({k:copy.deepcopy(v) for k,v in item.items() if k not in ['room','stages']})
    return result


def validate_variant(house):
    counts=validate(house)
    if house.get('sceneVariant','baseline')=='baseline':
        return dict(**counts,windows=0,clutterObjects=0,materialFamily=None)
    if house['sceneVariant']!='windows-clutter' or type(house['materialFamily']) is not int or not 0<=house['materialFamily']<len(PALETTES):
        raise ValueError('Invalid appearance family')
    walls={w['id']:w for w in house['walls']};service_walls={s['wall'] for s in house['services']}
    identities={item['id'] for key in ['rooms','walls','doors','stairs','services'] for item in house[key]}
    for item in house['windows']+house['clutter']:
        if item['id'] in identities:raise ValueError('Repeated variation identity')
        identities.add(item['id'])
        if len(item['low'])!=3 or len(item['high'])!=3 or any(not math.isfinite(v) for v in item['low']+item['high']) or any(b<=a for a,b in zip(item['low'],item['high'])):
            raise ValueError('Invalid variation bounds')
        if item['stages']!=['rough','finished']:raise ValueError('Unexpected variation stage membership')
    for window in house['windows']:
        wall=walls.get(window['wall']);axis=window['axis'];cross=1-axis
        if axis not in [0,1] or wall is None or len(wall['rooms'])!=1 or wall['id'] in service_walls or window['room']!=wall['rooms'][0] or window['glazing']!='open':
            raise ValueError('Window conflicts with a service, room or material contract')
        z=wall['level']*house['rise']
        if not (wall['a'][axis]+.2<window['low'][axis]<window['high'][axis]<wall['b'][axis]-.2 and z+.2<window['low'][2]<window['high'][2]<z+house['rise']-.45 and window['low'][cross]<wall['a'][cross]-.0825 and window['high'][cross]>wall['a'][cross]+.0825):
            raise ValueError('Window does not fit or fully penetrate its wall')
    for item in house['clutter']:
        if type(item['room']) is not int or not 0<=item['room']<len(house['rooms']):raise ValueError('Missing clutter room')
        room=house['rooms'][item['room']];pitch=house['pitch']
        if item['low'][2]!=room['elevation'] or item['high'][2]>=room['elevation']+room['height']-room['ceilingDrop']:
            raise ValueError('Clutter does not stand on the room floor')
        for x in [item['low'][0]-.1,item['high'][0]+.1]:
            for y in [item['low'][1]-.1,item['high'][1]+.1]:
                cell=math.floor(x/pitch),math.floor(y/pitch)
                if cell not in set(map(tuple,room['cells'])) or cell==(0,0) and house['levels']>1:
                    raise ValueError('Clutter crosses a room wall or stair bay')
        for door in house['doors']:
            wall=walls[door['wall']];axis=0 if wall['a'][1]==wall['b'][1] else 1;cross=1-axis
            low=list(door['center']);high=list(door['center'])
            low[axis]-=door['width']/2+.35;high[axis]+=door['width']/2+.35
            low[cross]-=1.1;high[cross]+=1.1;high[2]+=2.3
            if overlaps(item,dict(low=low,high=high),.15):raise ValueError('Clutter blocks a reserved portal approach')
    for i,item in enumerate(house['clutter']):
        if any(overlaps(item,other) for other in house['clutter'][i+1:]):raise ValueError('Clutter objects intersect')
    return dict(**counts,windows=len(house['windows']),clutterObjects=len(house['clutter']),materialFamily=house['materialFamily'])
