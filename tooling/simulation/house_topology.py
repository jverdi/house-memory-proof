"""Evaluator-only connected house geometry, independent of shipping algorithms.

This is an analytic topology/assembly generator, not a phone sensor model. No
polygon, service graph, doorway or ideal navigation path belongs in the capture
bundle presented to a reconstruction/localization candidate.
"""
import hashlib
import json
import math
import random
from collections import defaultdict


def stable(seed, label):
    return hashlib.sha256(f'{seed}:{label}'.encode()).hexdigest()[:24]


def adjacent(a, b):
    return abs(a[0]-b[0])+abs(a[1]-b[1]) == 1


def outline(cells):
    """Counterclockwise outer boundary of a simply connected cell union."""
    edges = set()
    for x, y in cells:
        corners = [(x,y),(x+1,y),(x+1,y+1),(x,y+1)]
        for a,b in zip(corners,corners[1:]+corners[:1]):
            if (b,a) in edges: edges.remove((b,a))
            else: edges.add((a,b))
    successors = dict(edges)
    if len(successors) != len(edges): raise ValueError('Pinched room polygon')
    start=min(successors);points=[start];current=successors[start]
    while current != start:
        if current in points or current not in successors: raise ValueError('Open room boundary')
        points.append(current);current=successors[current]
    if len(points) != len(edges): raise ValueError('Room holes are not represented')
    return points


def generate(seed):
    rng=random.Random(seed);levels=rng.randint(1,3);pitch=rng.uniform(5.0,5.7);rise=rng.uniform(2.8,3.1)
    rooms=[];cell_owners={};cells_by_level=[]
    for level in range(levels):
        count=rng.randint(5,8) if levels==1 else rng.randint(4,6)
        cells={(0,0)}
        while len(cells)<count:
            x,y=rng.choice(sorted(cells));dx,dy=rng.choice([(1,0),(-1,0),(0,1),(0,-1)])
            q=x+dx,y+dy
            if -2<=q[0]<=2 and -2<=q[1]<=2:cells.add(q)
        cells_by_level.append(cells)
        # Keep a common stair bay across levels. Merge other neighboring cells
        # into genuine rectangular/L-shaped open plans with no internal wall.
        groups=[{c} for c in sorted(cells)];attempts=0
        while len(groups)>max(3,count-2) and attempts<40:
            attempts+=1;a,b=rng.sample(range(len(groups)),2)
            if (0,0) in groups[a] or (0,0) in groups[b]:continue
            if len(groups[a]|groups[b])>3:continue
            if not any(adjacent(c,d) for c in groups[a] for d in groups[b]):continue
            merged=groups[a]|groups[b]
            try:outline(merged)
            except ValueError:continue
            groups[a]=merged;groups.pop(b)
        for group in sorted(groups,key=lambda g:sorted(g)):
            index=len(rooms);room=dict(id=stable(seed,f'room-{index}'),level=level,cells=sorted(group),
                polygon=[[x*pitch,y*pitch] for x,y in outline(group)],elevation=level*rise,
                height=rise-.25,name='Repeated room name' if index%3 else 'Utility',
                ceilingDrop=.25 if index%4==1 else 0.,openPlan=len(group)>1)
            rooms.append(room)
            for cell in group:cell_owners[(level,*cell)]=index
    walls={};contacts=defaultdict(list)
    for (level,x,y),owner in sorted(cell_owners.items()):
        for a,b,other in [((x,y),(x+1,y),(x,y-1)),((x+1,y),(x+1,y+1),(x+1,y)),((x+1,y+1),(x,y+1),(x,y+1)),((x,y+1),(x,y),(x-1,y))]:
            neighbor=cell_owners.get((level,*other))
            if neighbor==owner:continue
            edge=tuple(sorted([a,b]));key=(level,*edge)
            if key not in walls:
                walls[key]=dict(id=stable(seed,f'wall-{key}'),level=level,a=[v*pitch for v in edge[0]],b=[v*pitch for v in edge[1]],rooms=sorted({owner} if neighbor is None else {owner,neighbor}),thickness=.14)
            if neighbor is not None and owner<neighbor:contacts[(owner,neighbor)].append(key)
    # A spanning tree plus independently sampled loops; mere geometric contact
    # does not imply an opening or a navigable connection.
    doors=[];selected=set()
    for level in range(levels):
        nodes={i for i,r in enumerate(rooms) if r['level']==level};seen={min(nodes)}
        while seen!=nodes:
            choices=sorted(pair for pair in contacts if (pair[0] in seen) != (pair[1] in seen) and rooms[pair[0]]['level']==level)
            if not choices:raise ValueError('Disconnected generated floor')
            pair=rng.choice(choices);selected.add(pair);seen.update(pair)
        for pair in sorted(contacts):
            if rooms[pair[0]]['level']==level and rng.random()<.3:selected.add(pair)
    for pair in sorted(selected):
        key=rng.choice(contacts[pair]);wall=walls[key]
        width=rng.choice([.9,1.,1.2,2.4]);offset=rng.uniform(.35,.65)
        wall['opening']=dict(offset=offset,width=width,height=2.12)
        a,b=wall['a'],wall['b'];mid=[a[i]+(b[i]-a[i])*offset for i in range(2)]
        doors.append(dict(id=stable(seed,f'door-{key}'),rooms=list(pair),wall=wall['id'],center=mid+[wall['level']*rise],width=width,height=2.12))
    stairs=[]
    for level in range(levels-1):
        steps=math.ceil(rise/.18);run=steps*.24
        stairs.append(dict(id=stable(seed,f'stair-{level}'),rooms=[cell_owners[(level,0,0)],cell_owners[(level+1,0,0)]],
            lowerLevel=level,origin=[.5,.3,level*rise],width=1.2,run=run,rise=rise,steps=steps,
            void=[.4,.2,1.8,.3+run+.25],upperLandingY=.3+run+.3))
    services=[]
    for i,room in enumerate(rooms):
        z=room['elevation']
        # Select a solid wall interval; even a room with doors on every side
        # still has jamb-side cavities. Never route a service across a portal.
        options=[]
        for w in walls.values():
            if i not in w['rooms']:continue
            opening=w.get('opening');length=math.dist(w['a'],w['b'])
            intervals=[(0,length)] if not opening else [(0,opening['offset']*length-opening['width']/2),(opening['offset']*length+opening['width']/2,length)]
            for lo,hi in intervals:options.append((hi-lo,w,lo+.15,hi-.15))
        _,wall,service_lo,service_hi=max(options,key=lambda item:item[0])
        a,b=wall['a'],wall['b'];axis=0 if a[1]==b[1] else 1;cross=1-axis
        middle=[(a[j]+b[j])/2 for j in range(2)]
        positive=middle.copy();positive[cross]+=.2
        side=1 if (math.floor(positive[0]/pitch),math.floor(positive[1]/pitch)) in set(room['cells']) else -1
        # Centre lines live inside the framed cavity. The thin route crosses
        # the horizontal routes in the image, but never acquires a graph edge.
        for kind,diameter,height in [('electrical',.012,.8),('plumbing',.04,.85),('lowVoltage',.008,1.25)]:
            def point(along,vertical,offset=.035):
                p=[0.,0.,z+vertical];p[axis]=a[axis]+along;p[cross]=a[cross]+side*offset;return p
            end=service_lo+(service_hi-service_lo)*.7
            points=[point(service_lo,height),point(end,height),point(end,height+.65)]
            if kind=='lowVoltage':points=[point(service_lo+(end-service_lo)*.4,.45,.047),point(service_lo+(end-service_lo)*.4,1.7,.047)]
            services.append(dict(id=stable(seed,f'service-{i}-{kind}'),room=i,wall=wall['id'],kind=kind,diameter=diameter,points=points,connectedTo=[],stages=['rough','finished'],visibleStages=['rough']))
    house=dict(schema=1,seed=seed,units='metres',axes='Z-up',pitch=pitch,rise=rise,levels=levels,rooms=rooms,walls=list(walls.values()),doors=doors,stairs=stairs,services=services,
        stages=[dict(id='rough',observed=True),dict(id='finished',observed=True,finishThickness=.0125),dict(id='planned-renovation',observed=False)],
        limitations=['Analytic axis-aligned assemblies, not photorealistic materials or calibrated sensors','Door and stair truth is evaluator-only; candidate navigation must use observed reconstruction','Split levels, curved walls and full workmanship diversity remain separate fixtures'])
    validate(house)
    return house


def validate(house):
    rooms=house['rooms'];pitch=house['pitch'];owners={};links=[]
    if not 1<=house['levels']<=3 or not rooms:raise ValueError('Invalid layout extent')
    ids=[item['id'] for key in ['rooms','walls','doors','stairs','services'] for item in house[key]]
    if len(ids)!=len(set(ids)):raise ValueError('Duplicate physical identity')
    for i,r in enumerate(rooms):
        for x,y in r['cells']:
            key=r['level'],x,y
            if key in owners:raise ValueError('Overlapping rooms')
            owners[key]=i
        polygon=r['polygon']
        area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(polygon,polygon[1:]+polygon[:1]))/2
        if not math.isclose(area,len(r['cells'])*pitch*pitch,rel_tol=1e-10):raise ValueError('Room polygon area differs from cells')
        if len(outline(set(map(tuple,r['cells']))))!=len(polygon):raise ValueError('Invalid polygon topology')
    walls={w['id']:w for w in house['walls']}
    for door in house['doors']:
        wall=walls.get(door['wall']);a,b=door['rooms']
        if wall is None or wall['rooms']!=sorted([a,b]) or rooms[a]['level']!=rooms[b]['level']:raise ValueError('Door lacks a shared wall')
        length=math.dist(wall['a'],wall['b']);opening=wall.get('opening',{})
        if opening.get('width')!=door['width'] or not .7<=door['width']<length-.4:raise ValueError('Invalid portal width')
        offset=opening['offset']*length
        if offset-door['width']/2<.1 or offset+door['width']/2>length-.1:raise ValueError('Portal crosses a wall end')
        links.append((a,b))
    for stair in house['stairs']:
        a,b=stair['rooms'];level=stair['lowerLevel']
        if rooms[a]['level']!=level or rooms[b]['level']!=level+1:raise ValueError('Stair skips or reverses a floor')
        if stair['steps']<1 or stair['rise']/stair['steps']>.18 or not math.isclose(stair['run']/stair['steps'],.24):raise ValueError('Invalid stair dimensions')
        if not (stair['void'][2]<pitch and stair['void'][3]<pitch and stair['upperLandingY']<pitch):raise ValueError('Stair does not fit the bay')
        links.append((a,b))
    reachable={0}
    while True:
        updated=reachable|{b for a,b in links if a in reachable}|{a for a,b in links if b in reachable}
        if updated==reachable:break
        reachable=updated
    if len(reachable)!=len(rooms):raise ValueError('House contains an unreachable room')
    for route in house['services']:
        if route['connectedTo']:raise ValueError('This fixture has no measured inter-route connection')
        if not 0<route['diameter']<=.1 or len(route['points'])<2:raise ValueError('Invalid service dimensions')
        if any(not math.isfinite(v) for point in route['points'] for v in point):raise ValueError('Invalid service coordinate')
    return dict(rooms=len(rooms),levels=house['levels'],doors=len(house['doors']),stairs=len(house['stairs']),openPlans=sum(r['openPlan'] for r in rooms),serviceRoutes=len(house['services']),connected=True)


def topology_signature(house):
    """Ignores textures, dimensions, seed and IDs: require structural variation."""
    value=dict(rooms=[dict(level=r['level'],cells=r['cells']) for r in house['rooms']],doors=sorted(sorted(d['rooms']) for d in house['doors']),stairs=sorted(s['rooms'] for s in house['stairs']))
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def geometry(house,stage):
    """Return stable-ID AABB assemblies for the existing ray/Blender adapters."""
    if stage not in ['rough','finished']:raise ValueError('Planned state is not observed geometry')
    result=[];pitch=house['pitch'];rise=house['rise']
    def add(identity,low,high,color,trade,**extra):
        if any(b<=a for a,b in zip(low,high)):return
        result.append(dict(id=identity,low=low,high=high,color=color,trade=trade,**extra))
    def slab(identity,rect,z0,z1,trade,void=None):
        x0,y0,x1,y1=rect;pieces=[rect]
        if void:
            a,b,c,d=void
            pieces=[[x0,y0,a,y1],[c,y0,x1,y1],[a,y0,c,b],[a,d,c,y1]]
        for i,(a,b,c,d) in enumerate(pieces):add(f'{identity}-{i}',[a,b,z0],[c,d,z1],[115,95,75] if trade=='floor' else [220,220,220],trade)
    for room in house['rooms']:
        z=room['elevation'];level=room['level']
        for x,y in room['cells']:
            incoming=next((s for s in house['stairs'] if s['lowerLevel']==level-1),None) if (x,y)==(0,0) else None
            outgoing=next((s for s in house['stairs'] if s['lowerLevel']==level),None) if (x,y)==(0,0) else None
            rect=[x*pitch,y*pitch,(x+1)*pitch,(y+1)*pitch]
            slab(f'{room["id"]}-floor-{x}-{y}',rect,z-.14,z,'floor',incoming['void'] if incoming else None)
            if stage=='finished':slab(f'{room["id"]}-ceiling-{x}-{y}',rect,z+room['height']-room['ceilingDrop'],z+room['height']-room['ceilingDrop']+.025,'ceiling',outgoing['void'] if outgoing else None)
    for wall in house['walls']:
        a,b=wall['a'],wall['b'];axis=0 if a[1]==b[1] else 1;cross=1-axis;length=math.dist(a,b);z=wall['level']*rise;height=rise-.25
        opening=wall.get('opening');pieces=[(0,length,0,height)]
        if opening:
            center=opening['offset']*length;left=center-opening['width']/2;right=center+opening['width']/2
            pieces=[(0,left,0,height),(right,length,0,height),(left,right,opening['height'],height)]
        def part(label,lo,hi,bottom,top,offset,thickness,color,trade):
            lower=[0.,0.,z+bottom];upper=[0.,0.,z+top]
            lower[axis]=a[axis]+lo;upper[axis]=a[axis]+hi;lower[cross]=a[cross]+offset-thickness/2;upper[cross]=a[cross]+offset+thickness/2
            add(f'{wall["id"]}-{label}',lower,upper,color,trade,textureless=trade=='finish')
        for index,(lo,hi,bottom,top) in enumerate(pieces):
            # The sheathing and framing stay the same physical assemblies after
            # closure; finish layers are added on both sides with real thickness.
            part(f'sheathing-{index}',lo,hi,bottom,top,0,.012,[120,90,65],'structure')
            part(f'plate-low-{index}',lo,hi,bottom,bottom+.038,0,.14,[175,130,85],'structure')
            part(f'plate-high-{index}',lo,hi,top-.038,top,0,.14,[175,130,85],'structure')
            count=math.ceil((hi-lo)/.406)
            for n in range(count+1):
                start=min(lo+n*.406,hi-.038)
                part(f'stud-{index}-{n}',max(lo,start),min(hi,start+.038),bottom,top,0,.14,[180,135,88],'structure')
            if stage=='finished':
                for side in [-1,1]:part(f'finish-{index}-{side}',lo,hi,bottom,top,side*(.07+.00625),.0125,[211,215,211],'finish')
    for stair in house['stairs']:
        x,y,z=stair['origin'];height=stair['rise']/stair['steps']
        for step in range(stair['steps']):
            add(f'{stair["id"]}-step-{step}',[x,y+step*.24,z+step*height],[x+stair['width'],y+(step+1)*.24,z+(step+1)*height],[120,95,65],'stairs')
        # Top landing spans the remaining opening and meets the upper slab.
        add(stair['id']+'-landing',[.4,y+stair['run'],z+stair['rise']-.14],[1.8,stair['void'][3],z+stair['rise']],[115,95,75],'floor')
    colors={'electrical':[230,170,40],'plumbing':[65,160,220],'lowVoltage':[170,125,245]}
    for route in house['services']:
        radius=route['diameter']/2
        for i,(a,b) in enumerate(zip(route['points'],route['points'][1:])):
            low=[min(x,y)-radius for x,y in zip(a,b)];high=[max(x,y)+radius for x,y in zip(a,b)]
            add(route['id']+f'-part-{i}',low,high,colors[route['kind']],route['kind'])
    return result
