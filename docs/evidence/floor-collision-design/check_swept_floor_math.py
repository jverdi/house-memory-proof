"""Design check: translated floor SAT against independent LP feasibility."""
import json
import numpy as np
import scipy
from scipy.optimize import linprog
rng=np.random.default_rng(819237)
def sat(vertices,start,end,extents):
 v=vertices-start; edges=np.roll(vertices,-1,axis=0)-vertices
 axes=list(np.eye(3))+[np.cross(edges[0],edges[1])]+[np.cross(e,a) for e in edges for a in np.eye(3)]
 enter,leave=0.,1.
 for axis in axes:
  length=np.linalg.norm(axis)
  if length<=1e-12:continue
  axis=axis/length; r=np.abs(axis)@extents; p=v@axis
  low,high=p.min()-r-1e-9,p.max()+r+1e-9; speed=(end-start)@axis
  if abs(speed)<1e-12:
   if low>0 or high<0:return False
  else:
   first,last=low/speed,high/speed;enter=max(enter,min(first,last));leave=min(leave,max(first,last))
   if enter>leave:return False
 return True
def independent(vertices,start,end,extents):
 # Variables are two barycentric coordinates and time; feasibility requires
 # one point inside both the triangle and the moving box at the same time.
 M=np.column_stack((vertices[1]-vertices[0],vertices[2]-vertices[0],start-end))
 offset=vertices[0]-start
 A=np.vstack((M,-M,[1,1,0])); b=np.r_[extents-offset,extents+offset,1]
 result=linprog([0,0,0],A_ub=A,b_ub=b,bounds=[(0,1)]*3,method='highs')
 assert result.status in (0,2),result.message
 return result.success
colliding=0
for i in range(1000):
 vertices=rng.uniform(-2,2,(3,3)); start=rng.uniform(-2,2,3); end=rng.uniform(-2,2,3); extents=rng.uniform(.02,.9,3)
 if i%4==0:end=start.copy()
 if i%5==0:vertices[:,2]=0
 answer=independent(vertices,start,end,extents)
 assert sat(vertices,start,end,extents)==answer,i
 assert sat(vertices[::-1],end,start,extents)==answer,('reverse',i)
 shift=np.array([1000,-2000,3000.])
 assert sat(vertices+shift,start+shift,end+shift,extents)==answer,('translated',i)
 colliding+=answer
report={'passed':True,'cases':1000,'numpyVersion':np.__version__,'scipyVersion':scipy.__version__,'colliding':colliding,'separated':1000-colliding,'seed':819237,'additionalChecks':['reversed winding and motion','translated origin'],'reference':'SciPy HiGHS linear feasibility in barycentric coordinates and continuous time','scope':'Independent mathematical design check of Python SAT transcription; not execution of the native Swift implementation or device qualification.'}
open('swept-floor-math.json','w').write(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
