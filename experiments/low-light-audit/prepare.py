"""One isolated low-light repair candidate, never a shipping source mutation.

Hypothesis: fixed AKAZE response loses usable texture after underexposure. Apply
a bounded gain to the analysis copy only when its measured mean is below 64.
No detector, correspondence, pose, ambiguity or acceptance threshold changes.
One candidate; two 30-minute managed jobs maximum, no parameter sweep.
"""
from pathlib import Path
import hashlib
import json

p=Path('packages/visual-core/hx_vision.cpp');source=p.read_text()
before=' auto detector=cv::AKAZE::create'
after=''' // Experimental analysis-copy exposure normalization; originals untouched.
 cv::Scalar mean,deviation;cv::meanStdDev(image,mean,deviation);
 if(mean[0]<64.0 && deviation[0]>4.0){
   const double gain=std::min(4.0,96.0/std::max(1.0,mean[0]));
   image.convertTo(image,CV_8U,gain);
 }
 auto detector=cv::AKAZE::create'''
assert source.count(before)==1
candidate=source.replace(before,after);p.write_text(candidate)
out=Path('build/low-light-aggregates');out.mkdir(parents=True,exist_ok=True)
(out/'candidate.json').write_text(json.dumps(dict(experiment='bounded analysis exposure gain',adopted=False,
    originalSourceSHA256=hashlib.sha256(source.encode()).hexdigest(),candidateSourceSHA256=hashlib.sha256(candidate.encode()).hexdigest(),
    maximumGain=4,meanBelow=64,targetMean=96,minimumStandardDeviation=4,
    candidates=1,maximumManagedRunnerMinutes=60,originalSpatialGatesUnchanged=True),indent=2)+'\n')
