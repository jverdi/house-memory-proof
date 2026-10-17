#!/usr/bin/env python3
"""Frozen portable surface candidate vs evaluator-only analytic house truth."""
import argparse,hashlib,json,struct,subprocess,tempfile,zipfile,time,sys
from pathlib import Path
import numpy as np
from house import generate
ROOT=Path(__file__).resolve().parents[2]
def run(executable,bundle):
 with zipfile.ZipFile(bundle) as z:
  h=json.loads(z.read('house.json'));frames=[x for x in h['observations'] if x['segmentID']==h['segments'][0]['id']]
  data=bytearray(b'HXS1'+struct.pack('<I',len(frames)))
  for o in frames:
   k=o['intrinsics'];data+=struct.pack('<II4d16d',o['depthWidth'],o['depthHeight'],k[0],k[4],k[2],k[5],*o['camera']);data+=z.read('assets/'+o['depth']);data+=z.read('assets/'+o['confidence'])
  start=time.monotonic();result=subprocess.run([str(executable)],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
  if result.returncode:return None,{'accepted':False,'exit':result.returncode,'seconds':time.monotonic()-start}
  n=struct.unpack_from('<I',result.stdout)[0];assert len(result.stdout)==4+n*24 and n<=500000
  vertices=np.frombuffer(result.stdout,offset=4,dtype='<f8').reshape(n,3)
  return vertices,{'accepted':True,'vertices':n,'seconds':time.monotonic()-start,'candidate_input_sha256':hashlib.sha256(data).hexdigest()}
def evaluate(vertices,oracle):
 errors=np.full(len(vertices),np.inf)
 for item in oracle['rooms'][0]['rough_geometry']:
  low=np.array(item['low']);high=np.array(item['high']);outside=np.linalg.norm(np.maximum(np.maximum(low-vertices,vertices-high),0),axis=1);inside=np.minimum(vertices-low,high-vertices).min(axis=1);errors=np.minimum(errors,np.where(inside>=0,inside,outside))
 return {'surface_to_truth_p50_m':float(np.median(errors)),'surface_to_truth_p95_m':float(np.quantile(errors,.95)),'surface_to_truth_max_m':float(errors.max()),'p95_10mm_pass':bool(np.quantile(errors,.95)<=.010)}
def main():
 p=argparse.ArgumentParser();p.add_argument('--development',type=int,default=50);p.add_argument('--holdout',type=int,default=20);p.add_argument('--output',type=Path,default=ROOT/'build/evidence/house-qualification.json');a=p.parse_args();a.output.parent.mkdir(parents=True,exist_ok=True)
 executable=ROOT/'build/hx-surface-candidate';sources=[ROOT/'packages/spatial-core/hx_surface.cpp',ROOT/'packages/spatial-core/hx_surface.h',ROOT/'packages/spatial-core/surface_cli.cpp']
 source_hash=hashlib.sha256(b''.join(x.read_bytes() for x in sources)).hexdigest();subprocess.run(['c++','-std=c++17','-O2',str(sources[0]),str(sources[2]),'-o',str(executable)],check=True)
 # Freeze source and seed split before evaluating; no candidate access to this file.
 seed_rng=np.random.default_rng(8675309);seeds=seed_rng.choice(2**30,a.development+a.holdout,replace=False).tolist()
 manifest={'candidate_source_sha256':source_hash,'candidate_binary_sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'development_seeds':seeds[:a.development],'held_out_seeds':seeds[a.development:]};(a.output.parent/'house-suite-manifest.json').write_text(json.dumps(manifest,indent=2))
 results=[]
 with tempfile.TemporaryDirectory(prefix='house-evaluator-') as tmp:
  path=Path(tmp)
  for i,seed in enumerate(seeds):
   # First room only is scored; native integration separately imports all three rooms/stages.
   noise=.002+(i%5)*.001;drift=.005+(i%4)*.005
   generate(seed,path,rooms=1,frames=24,width=96,noise=noise,drift=drift)
   vertices,result=run(executable,path/'candidate.hxray');result.update({'seed':seed,'split':'development' if i<a.development else 'held_out','noise_sigma_m':noise,'pose_drift_m':drift})
   if vertices is not None:result.update(evaluate(vertices,json.loads((path/'oracle.json').read_text())))
   results.append(result)
   report={'candidate_source_sha256':source_hash,'suite':'analytic paired-room rendering with imperfect pose priors','cases':results,'complete':len(results)==len(seeds),'precision_qualified':False,'limitations':['AABB renderer, not a validated iPhone sensor model','One room per house scored; no inter-room registration','Nearest-surface distance, not a completeness measure','Thin-service localization and false room matches are not evaluated','Held-out seeds from the same scene family are not the full protected qualification suite']}
   a.output.write_text(json.dumps(report,indent=2));print(json.dumps({'completed':i+1,'total':len(seeds),'split':result['split'],'p95_m':result.get('surface_to_truth_p95_m'),'accepted':result['accepted']}),flush=True)
 print(json.dumps({'accepted':sum(x['accepted'] for x in results),'p95_10mm_pass':sum(x.get('p95_10mm_pass',False) for x in results),'cases':len(results),'report':str(a.output)}))
if __name__=='__main__':main()
