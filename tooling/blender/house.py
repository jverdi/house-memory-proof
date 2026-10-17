"""Blender Cycles construction camera fixture. Run with Blender's Python.

Candidate receives rendered JPEG, noisy depth and imperfect camera priors only.
True meshes, camera poses and materials remain evaluator-side. This is not an
empirically calibrated iPhone sensor simulator.
"""
import bpy, math, json, hashlib, uuid, zipfile, sys, random
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np
args=sys.argv[sys.argv.index('--')+1:];dest=Path(args[0]).resolve();dest.mkdir(parents=True,exist_ok=True)
seed=803219;rng=np.random.default_rng(seed);random.seed(seed)
def identity(name):return str(uuid.uuid5(uuid.NAMESPACE_URL,f'house-xray/blender/{seed}/{name}')).upper()
def v(p):return dict(zip(('x','y','z'),map(float,p)))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.resolution_x=640;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=95
scene.view_settings.view_transform='Standard';scene.world.color=(.12,.12,.12)
scene.render.film_transparent=False

def material(name,color,grain=False,metal=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.65;p.inputs['Metallic'].default_value=metal
 if grain:
  tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=12;tex.inputs['Detail'].default_value=3
  coords=n.new('ShaderNodeTexCoord');mapping=n.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(5,5,.12);l.new(coords.outputs['Generated'],mapping.inputs[0]);l.new(mapping.outputs[0],tex.inputs['Vector'])
  ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(*[x*.35 for x in color],1);ramp.color_ramp.elements[1].color=(*color,1);l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],p.inputs['Base Color'])
 return m
wood=material('Framing timber',(.58,.34,.15),True);osb=material('Wood sheathing',(.43,.31,.17),True);paint=material('Painted gypsum',(.76,.78,.74));floor=material('Wood floor',(.33,.18,.07),True)
yellow=material('Electrical cable',(.75,.42,.02));blue=material('Low voltage cable',(.08,.16,.65));steel=material('Galvanized duct',(.40,.46,.48),metal=.8);plastic=material('Outlet plate',(.76,.75,.70));black=material('Receptacle openings',(.015,.015,.015))
rough=[];finished=[]
def box(name,center,size,mat,group=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=center);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
 if group is not None:group.append(o)
 return o
def cable(name,points,radius,mat):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=3;s=curve.splines.new('POLY');s.points.add(len(points)-1)
 for p,xyz in zip(s.points,points):p.co=(*xyz,1)
 o=bpy.data.objects.new(name,curve);scene.collection.objects.link(o);curve.materials.append(mat);rough.append(o)
box('Floor',(0,0,-.07),(5,4,.14),floor)
for side in [-1,1]:
 box('Sheathing Y',(0,side*2,1.45),(5,.03,2.9),osb,rough)
 box('Sheathing X',(side*2.5,0,1.45),(.03,4,2.9),osb,rough)
 for x in np.arange(-2.4,2.5,.406):box('Stud Y',(float(x),side*1.92,1.45),(.038,.14,2.9),wood,rough)
 for y in np.arange(-1.9,2,.406):box('Stud X',(side*2.42,float(y),1.45),(.14,.038,2.9),wood,rough)
 box('Finished Y',(0,side*1.83,1.45),(5,.025,2.9),paint,finished)
 box('Finished X',(side*2.33,0,1.45),(.025,4,2.9),paint,finished)
box('Ceiling',(0,0,2.92),(5,4,.04),paint)
cable('Electrical cable through studs',[(-2,1.80,1.05),(-1,1.79,1.03),(0,1.80,1.06),(1,1.80,1.04),(2,1.80,1.06)],.006,yellow)
cable('Data drop',[(.42,1.79,2.65),(.42,1.79,.45)],.004,blue)
cable('Water supply',[(2.25,-1,1.05),(2.25,.5,1.05),(2.25,.5,2.7)],.015,blue)
box('Ceiling HVAC duct',(.3,0,2.65),(3.7,.30,.23),steel,rough)
for x in [-1.5,.5,1.7]:
 box('Rough electrical box',(x,1.79,.45),(.09,.07,.12),blue,rough)
 box('Finished outlet plate',(x,1.805,.45),(.085,.008,.125),plastic,finished)
 for dx in [-.012,.012]:
  for dz in [-.023,.023]:box('Outlet slot',(x+dx,1.797,.45+dz),(.006,.003,.014),black,finished)
# Distinct fixed wall art provides realistic visual structure on otherwise blank walls.
for axis,center in [('Y',(-.8,1.79,1.7)),('X',(2.29,.6,1.65))]:
 for i in range(7):
  color=tuple(float(x) for x in rng.uniform(.05,.75,3));m=material('Artwork pigment',color)
  if axis=='Y':pos=(center[0]+(i-3)*.065,center[1],center[2]+math.sin(i)*.16);size=(.055,.012,.5)
  else:pos=(center[0],center[1]+(i-3)*.065,center[2]+math.cos(i)*.16);size=(.012,.055,.5)
  box('Wall art',pos,size,m,finished)
for position,power,size in [((0,-1,2.7),350,2),((-1,0,2.5),220,1.5)]:
 light=bpy.data.lights.new('Work light','AREA');light.energy=power;light.shape='DISK';light.size=size;o=bpy.data.objects.new('Work light',light);scene.collection.objects.link(o);o.location=position
camera_data=bpy.data.cameras.new('Camera');camera_data.lens=28;camera_data.sensor_width=36;camera_data.sensor_fit='HORIZONTAL';camera=bpy.data.objects.new('Camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
width,height=640,480;dw,dh=192,144;fx=width*28/36;cx=(width-1)/2;cy=(height-1)/2;k=[fx,0,cx,0,fx,cy,0,0,1]
assets={};oracle={'renderer':'Blender 4.5.3 Cycles','syntheticOnly':True,'fieldQualified':False,'mappingCameras':{},'injectedTranslationDriftMetres':.03,'queries':[]}
room_id=identity('room');rough_id=identity('rough');finish_id=identity('finish');segment_id=identity('segment');now=813974400.
house=dict(schema=1,id=identity('house'),name='Cycles construction laboratory',created=now,revision=1,rooms=[dict(id=room_id,name='Rendered construction room',level=0,origin=v((0,0,0)),size=v((5,4,2.9)),isDesign=True)],stages=[dict(id=rough_id,name='Rough-in',date=now,kind='synthetic'),dict(id=finish_id,name='Finished',date=now+1,kind='synthetic')],features=[],observations=[],segments=[dict(id=segment_id,roomID=room_id,stageID=rough_id,started=now,interrupted=False,approved=False,referencePoses=[])],dimensions=[],drawings=[],bookmarks=[],references=[],documentaryPhotos=[],connections=[],isDemo=True,notes='Physically rendered analytic scene; not a validated phone sensor model.',closureNotes='')
def asset(data,ext):
 key=hashlib.sha256(data).hexdigest()+'.'+ext;assets['assets/'+key]=data;return key
native_from_world=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
def capture(name,shift,angle=0,elevation=0,depth_needed=False):
 heading=math.pi/4+math.radians(angle);camera.location=(shift/math.sqrt(2),-shift/math.sqrt(2),1.45+elevation)
 forward=Vector((math.sin(heading),math.cos(heading),-.06));camera.rotation_euler=forward.to_track_quat('-Z','Y').to_euler();bpy.context.view_layer.update()
 scene.render.filepath=str(dest/(name+'.jpg'));bpy.ops.render.render(write_still=True)
 native=native_from_world@camera.matrix_world;pose=[float(native[r][c]) for r in range(4) for c in range(4)]
 if not depth_needed:return (dest/(name+'.jpg')).read_bytes(),None,None,pose
 deps=bpy.context.evaluated_depsgraph_get();depth=np.zeros((dh,dw),dtype='<f4');confidence=np.zeros((dh,dw),dtype=np.uint8);inverse=camera.matrix_world.inverted();origin=camera.matrix_world.translation
 for y in range(dh):
  for x in range(dw):
   ray=Vector(((x-cx*dw/width)/(fx*dw/width),-(y-cy*dh/height)/(fx*dh/height),-1)).normalized();direction=camera.matrix_world.to_3x3()@ray
   hit,point,normal,index,obj,matrix=scene.ray_cast(deps,origin,direction,distance=5)
   if hit:
    distance=-(inverse@point).z
    if .15<distance<5:depth[y,x]=max(.15,distance+rng.normal(0,.006));confidence[y,x]=2
 missing=rng.random((dh,dw))<.02;depth[missing]=0;confidence[missing]=0
 return (dest/(name+'.jpg')).read_bytes(),depth,confidence,pose
for o in finished:o.hide_render=True;o.hide_set(True)
for index,shift in enumerate([-.35,-.22,-.10,.10,.22,.35]):
 image,depth,confidence,pose=capture('map-'+str(index),shift,depth_needed=True);oid=identity('map-'+str(index));oracle['mappingCameras'][oid]=pose
 prior=pose.copy();prior[3]+=.03*index/5;prior[7]+=float(rng.normal(0,.001))
 house['observations'].append(dict(id=oid,roomID=room_id,stageID=rough_id,segmentID=segment_id,timestamp=float(index),date=now+index,image=asset(image,'jpg'),depth=asset(depth.tobytes(),'depth32'),confidence=asset(confidence.tobytes(),'confidence8'),depthWidth=dw,depthHeight=dh,width=width,height=height,camera=prior,intrinsics=k,tracking='rendered noisy camera prior',light=800,sharpness=.1,note='Cycles rough-in image with coarse noisy optical-axis depth.',documentary=False,imageOrientation=1))
entries={'house.json':json.dumps(house,separators=(',',':')).encode(),**assets};entries['manifest.json']=json.dumps({'format':'HouseXray','version':1,'sha256':{n:hashlib.sha256(d).hexdigest() for n,d in entries.items()}}).encode()
with zipfile.ZipFile(dest/'vision-map.hxray','w',compression=zipfile.ZIP_STORED) as archive:
 for name,data in entries.items():archive.writestr(name,data)
for index,(shift,angle,elevation) in enumerate([(-.17,-2,.03),(.03,1,-.05),(.26,3,.07)]):
 image,_,_,pose=capture('vision-query-'+str(index),shift,angle,elevation)
 world=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))@Matrix([pose[i:i+4] for i in range(0,16,4)])
 oracle['queries'].append(dict(image='vision-query-'+str(index)+'.jpg',width=width,height=height,intrinsics=k,expectedCamera=[float(world[r][c]) for r in range(4) for c in range(4)],shouldMatch=True))
# Stage change is exploratory: surviving floor/ceiling features may legitimately localize.
# Do not label a valid cross-stage pose a false accept.
for o in rough:o.hide_render=True;o.hide_set(True)
for o in finished:o.hide_render=False;o.hide_set(False)
image,_,_,pose=capture('vision-query-3',0)
oracle['queries'].append(dict(image='vision-query-3.jpg',width=width,height=height,intrinsics=k,expectedCamera=pose,shouldMatch=None,scenario='finished-wall stage change'))
# Unrelated close-up surface covers the camera view and has no map correspondences.
card=material('Unrelated test surface',(.8,.1,.6),True)
box('Unrelated surface',(0.4,.4,1.5),(2,2,3),card)
image,_,_,pose=capture('vision-query-4',0)
oracle['queries'].append(dict(image='vision-query-4.jpg',width=width,height=height,intrinsics=k,expectedCamera=pose,shouldMatch=False))
(dest/'vision-queries.json').write_text(json.dumps(oracle,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(dest/'construction-house.blend'))
(dest/'renderer.json').write_text(json.dumps(dict(version=bpy.app.version_string,engine='CYCLES',samples=12,depth='separate triangle ray casts, optical-axis metres',depthNoiseSigmaMetres=.006,rgbResolution=[width,height],depthResolution=[dw,dh],limitations=['One constructed room','Procedural materials','No empirically fitted rolling shutter or multipath model','No physical precision qualification']),indent=2))
print('HOUSE_XRAY_RENDER_COMPLETE',flush=True)
