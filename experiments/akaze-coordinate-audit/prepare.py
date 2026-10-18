"""Isolated development experiment; the shipping detector is unchanged.

Refine native-resolution AKAZE positions conservatively, then compute descriptors
at those positions. Scale-space identity and detector budgets remain unchanged.
No ground truth enters this candidate and no acceptance threshold is changed.
"""
from pathlib import Path

path=Path('packages/visual-core/hx_vision.cpp')
source=path.read_text()
before=' detector->detectAndCompute(image,cv::noArray(),keys,desc);'
after=''' detector->detect(image,keys);
 if(keys.empty())return 0;
 std::vector<cv::Point2f> refined;refined.reserve(keys.size());
 for(const auto& key:keys)refined.push_back(key.pt);
 cv::cornerSubPix(image,refined,cv::Size(2,2),cv::Size(-1,-1),
   cv::TermCriteria(cv::TermCriteria::COUNT|cv::TermCriteria::EPS,20,0.001));
 for(size_t i=0;i<keys.size();i++){
   const auto p=refined[i];
   if(std::isfinite(p.x)&&std::isfinite(p.y)&&p.x>=3&&p.y>=3&&
      p.x<image.cols-3&&p.y<image.rows-3&&cv::norm(p-keys[i].pt)<=0.75)
     keys[i].pt=p;
 }
 // AKAZE compute preserves the retained keypoint's scale-space identity and
 // describes its updated location; no descriptor is paired with a stale point.
 detector->compute(image,keys,desc);'''
assert source.count(before)==1
path.write_text(source.replace(before,after))
print('Prepared one bounded AKAZE coordinate experiment; all gates unchanged')
