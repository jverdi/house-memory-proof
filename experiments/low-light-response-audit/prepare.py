"""Second bounded low-light candidate: adapt feature response, not pixels.

The preceding fixed-gain experiment showed recoverable texture, but the runbook
reserves photometric normalization for display derivatives. This candidate keeps
analysis pixels unchanged and scales the AKAZE detection response by the squared
measured exposure ratio. Matching, geometric admission and evaluation gates stay
unchanged. One fixed candidate, two 30-minute managed jobs, no parameter sweep.
"""
from pathlib import Path
import hashlib
import json

p=Path('packages/visual-core/hx_vision.cpp');source=p.read_text()
before=' auto detector=cv::AKAZE::create(cv::AKAZE::DESCRIPTOR_MLDB,256,3,0.001f,4,4,cv::KAZE::DIFF_PM_G2,int(capacity));'
after=''' // Experimental exposure-aware detector response; image values unchanged.
 cv::Scalar mean,deviation;cv::meanStdDev(image,mean,deviation);
 double response=0.001;
 if(mean[0]<64.0 && deviation[0]>4.0){
   const double ratio=std::max(0.25,mean[0]/96.0);
   response*=ratio*ratio;
 }
 auto detector=cv::AKAZE::create(cv::AKAZE::DESCRIPTOR_MLDB,256,3,float(response),4,4,cv::KAZE::DIFF_PM_G2,int(capacity));'''
assert source.count(before)==1
candidate=source.replace(before,after);p.write_text(candidate)
out=Path('build/low-light-aggregates');out.mkdir(parents=True,exist_ok=True)
(out/'candidate.json').write_text(json.dumps(dict(experiment='exposure-aware detector response',adopted=False,
    originalSourceSHA256=hashlib.sha256(source.encode()).hexdigest(),candidateSourceSHA256=hashlib.sha256(candidate.encode()).hexdigest(),
    originalPixelsChanged=False,minimumResponse=0.0000625,maximumResponse=0.001,meanBelow=64,referenceMean=96,minimumStandardDeviation=4,
    candidates=1,maximumManagedRunnerMinutes=60,originalSpatialGatesUnchanged=True),indent=2)+'\n')
