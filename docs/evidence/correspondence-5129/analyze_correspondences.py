"""Development-only residual diagnosis after candidate output has been sealed."""
import json,sys
from pathlib import Path
import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation
root=Path(sys.argv[1]);results=[]
for name in ['rough-a','rough-b','paired','staggered']:
 report=json.loads((root/(name+'.json')).read_text())
 truth={q['image']:q for q in json.loads((root/(name+'-evaluator-cameras.json')).read_text())['queries']}
 for q in report['queries']:
  records=[s[len('CorrespondencesJSON: '):] for s in q.get('diagnostics',[]) if s.startswith('CorrespondencesJSON: ')]
  if not records or not q.get('accepted'):continue
  data=json.loads(records[-1]);points=np.asarray(data['xyz']).reshape(-1,3);pixels=np.asarray(data['xy']).reshape(-1,2)
  oracle=truth[q['image']];K=np.asarray(oracle['intrinsics']).reshape(3,3)
  expected=np.asarray(oracle['expectedCamera']).reshape(4,4);estimated=np.asarray(q['worldFromARCamera']).reshape(4,4)
  flip=np.diag([1.,-1.,-1.])
  def extrinsic(pose):
   R=flip@pose[:3,:3].T
   return R,-R@pose[:3,3]
  def project(R,t):
   camera=points@R.T+t
   return camera[:,:2]/camera[:,2,None]*[K[0,0],K[1,1]]+[K[0,2],K[1,2]]
  true_residual=project(*extrinsic(expected))-pixels
  base_residual=project(*extrinsic(estimated))-pixels
  inliers=np.linalg.norm(base_residual,axis=1)<=2.5
  def stats(residual):
   residual=residual[inliers]
   return {'medianXY':np.median(residual,axis=0).tolist(),'meanXY':np.mean(residual,axis=0).tolist(),'normP50P95':np.quantile(np.linalg.norm(residual,axis=1),[.5,.95]).tolist()}
  R,t=extrinsic(estimated);initial=np.r_[Rotation.from_matrix(R).as_rotvec(),t]
  def residual(x):return (project(Rotation.from_rotvec(x[:3]).as_matrix(),x[3:])-pixels).reshape(-1)
  fits=[]
  for loss,scale in [('linear',1),('huber',1),('huber',.5),('soft_l1',.5)]:
   fitted=least_squares(residual,initial,loss=loss,f_scale=scale,max_nfev=100,ftol=1e-10,xtol=1e-10,gtol=1e-10)
   rotation=Rotation.from_rotvec(fitted.x[:3]).as_matrix();position=-rotation.T@fitted.x[3:]
   fits.append({'loss':loss,'scale':scale,'positionErrorMetres':float(np.linalg.norm(position-expected[:3,3])),'position':position.tolist(),'success':bool(fitted.success)})
  results.append({'fixture':name,'image':q['image'],'correspondences':len(points),'diagnosticInliersAt2_5Pixels':int(inliers.sum()),'originalPositionErrorMetres':q.get('evaluatorPositionErrorMetres'),'truthPoseResidualPixels':stats(true_residual),'estimatedPoseResidualPixels':stats(base_residual),'independentScipyFits':fits})
output={'productionQualified':False,'method':'Projection of sealed candidate 3D/2D correspondences under evaluator-only true camera; independent SciPy robust fitting is diagnostic, not native acceptance. Residual statistics use <=2.5-pixel errors at the original candidate pose; fits use all retained correspondences.','cases':results}
(root/'residual-analysis.json').write_text(json.dumps(output,indent=2)+'\n')
for q in results:
 print(q['fixture'],q['image'],'original mm',round(1000*(q['originalPositionErrorMetres'] or 0),3),'truth mean',q['truthPoseResidualPixels']['meanXY'],'fits mm',[(f['loss'],f['scale'],round(1000*f['positionErrorMetres'],3)) for f in q['independentScipyFits']])
