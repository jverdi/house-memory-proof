#include "hx_vision.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/calib3d.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <mutex>
#include <set>
#include <vector>
namespace {
void configure(){static std::once_flag once;std::call_once(once,[]{cv::setNumThreads(1);});}
bool hxFinite(double x){return std::isfinite(x);}
}
extern "C" int32_t hx_vision_detect(const uint8_t* gray,uint32_t bytes,uint32_t w,uint32_t h,uint32_t stride,float* xy,uint8_t* descriptors,uint32_t capacity) try {
 if(!gray||!xy||!descriptors||w<64||h<64||w>4096||h>4096||stride<w||uint64_t(stride)*h>bytes||capacity<1||capacity>2400)return -1;
 configure();cv::Mat source(h,w,CV_8U,const_cast<uint8_t*>(gray),stride),image;
 double scale=std::min(1.0,1280.0/std::max(w,h));cv::resize(source,image,cv::Size(),scale,scale,cv::INTER_AREA);
 auto detector=cv::AKAZE::create(cv::AKAZE::DESCRIPTOR_MLDB,256,3,0.001f,4,4,cv::KAZE::DIFF_PM_G2,int(capacity));
 std::vector<cv::KeyPoint> keys;cv::Mat desc;
 detector->detectAndCompute(image,cv::noArray(),keys,desc);
 if(keys.empty())return 0;
 if(desc.type()!=CV_8U||desc.cols!=32||desc.rows!=int(keys.size()))return -2;
 std::set<std::array<uint8_t,32>> unique;uint32_t n=0;
 for(size_t i=0;i<keys.size()&&n<capacity;i++){
  std::array<uint8_t,32> descriptor;std::memcpy(descriptor.data(),desc.ptr(i),32);
  // Refinement can converge neighbouring detections onto the same patch.
  // Identical descriptors are ambiguous evidence, not extra independent votes.
  if(!unique.insert(descriptor).second)continue;
  // Restore integer pixel centres to the supplied image after bounded resize.
  // Preserve the existing float arithmetic exactly when there is no resize.
  xy[n*2]=image.cols==int(w) ? keys[i].pt.x/image.cols:(keys[i].pt.x+.5)/image.cols-.5/w;
  xy[n*2+1]=image.rows==int(h) ? keys[i].pt.y/image.rows:(keys[i].pt.y+.5)/image.rows-.5/h;
  std::memcpy(descriptors+n*32,descriptor.data(),32);n++;
 }
 return int32_t(n);
} catch(...){return -2;}
extern "C" int32_t hx_vision_match(const uint8_t* map,uint32_t mn,const uint8_t* query,uint32_t qn,uint32_t* pairs,uint32_t capacity) try {
 if(!map||!query||!pairs||mn<2||qn<2||mn>50000||qn>2400||capacity>2400)return -1;
 configure();cv::Mat a(mn,32,CV_8U,const_cast<uint8_t*>(map)),b(qn,32,CV_8U,const_cast<uint8_t*>(query));
 cv::BFMatcher matcher(cv::NORM_HAMMING);std::vector<std::vector<cv::DMatch>> forward;std::vector<cv::DMatch> reverse;
 matcher.knnMatch(b,a,forward,2);matcher.match(a,b,reverse);uint32_t count=0;
 for(uint32_t i=0;i<forward.size()&&count<capacity;i++){
  if(forward[i].size()!=2)continue;auto best=forward[i][0],next=forward[i][1];
  if(best.distance>64||best.distance>=next.distance*.75f||reverse[best.trainIdx].trainIdx!=int(i))continue;
  pairs[count*2]=best.trainIdx;pairs[count*2+1]=i;count++;
 }
 return count;
} catch(...){return -2;}
extern "C" int32_t hx_vision_pose(const double* xyz,const double* xy,uint32_t n,double fx,double fy,double cx,double cy,uint32_t w,uint32_t h,double* output,HXPoseQuality* quality) try {
 if(!xyz||!xy||!output||!quality||n<30||n>2400||w<64||h<64||w>4096||h>4096||!hxFinite(fx)||!hxFinite(fy)||fx<1||fy<1||fx>1000000||fy>1000000||!hxFinite(cx)||!hxFinite(cy))return -1;
 *quality={};auto reject=[quality](uint32_t reason){quality->rejection=reason;return 0;};configure();std::vector<cv::Point3d> world;std::vector<cv::Point2d> pixels;
 for(uint32_t i=0;i<n;i++){
  double x=xyz[i*3],y=xyz[i*3+1],z=xyz[i*3+2],u=xy[i*2],v=xy[i*2+1];
  if(!hxFinite(x)||!hxFinite(y)||!hxFinite(z)||std::max({std::abs(x),std::abs(y),std::abs(z)})>100000||!hxFinite(u)||!hxFinite(v)||u<0||u>=w||v<0||v>=h)return -1;
  world.emplace_back(x,y,z);pixels.emplace_back(u,v);
 }
 // Translation of the house origin must not change pose conditioning or
 // candidate rejection. Solve in a local centroid frame, then restore origin.
 cv::Point3d origin(0,0,0);for(const auto& p:world)origin+=p;origin*=1./world.size();for(auto& p:world)p-=origin;
 cv::Mat K=(cv::Mat_<double>(3,3)<<fx,0,cx,0,fy,cy,0,0,1),r,t,inliers;
 cv::theRNG().state=0x4858524159504e50ULL;
 if(!cv::solvePnPRansac(world,pixels,K,cv::noArray(),r,t,false,400,2.5,0.999,inliers,cv::SOLVEPNP_EPNP))return reject(1);
 quality->inliers=uint32_t(inliers.rows);quality->fraction=double(inliers.rows)/n;
 if(inliers.rows<30||double(inliers.rows)/n<.6)return reject(2);
 std::vector<cv::Point3d> selected;std::vector<cv::Point2d> observations;std::set<int> cells;
 double minX=w,minY=h,maxX=0,maxY=0;
 for(int row=0;row<inliers.rows;row++){int i=inliers.at<int>(row);selected.push_back(world[i]);observations.push_back(pixels[i]);cells.insert(std::min(3,int(pixels[i].x*4/w))+4*std::min(2,int(pixels[i].y*3/h)));minX=std::min(minX,pixels[i].x);maxX=std::max(maxX,pixels[i].x);minY=std::min(minY,pixels[i].y);maxY=std::max(maxY,pixels[i].y);}
 quality->image_cells=uint32_t(cells.size());quality->span_x=(maxX-minX)/w;quality->span_y=(maxY-minY)/h;
 cv::Mat points(selected.size(),3,CV_64F);for(size_t i=0;i<selected.size();i++){points.at<double>(i,0)=selected[i].x;points.at<double>(i,1)=selected[i].y;points.at<double>(i,2)=selected[i].z;}
 cv::PCA pca(points,cv::Mat(),cv::PCA::DATA_AS_ROW);
 quality->spread_largest=pca.eigenvalues.at<double>(0);quality->spread_middle=pca.eigenvalues.at<double>(1);quality->spread_smallest=pca.eigenvalues.at<double>(2);
 if(cells.size()<6||maxX-minX<w*.3||maxY-minY<h*.3)return reject(3);
 // Reject near-planar/linear ambiguity instead of inventing a tight pose bound.
 if(pca.eigenvalues.at<double>(0)<.09||pca.eigenvalues.at<double>(1)<.0225||pca.eigenvalues.at<double>(2)<.0016)return reject(4);
 cv::solvePnPRefineLM(selected,observations,K,cv::noArray(),r,t);
 std::vector<cv::Point2d> projected;cv::Mat jacobian,R;cv::projectPoints(selected,r,t,K,cv::noArray(),projected,jacobian);cv::Rodrigues(r,R);
 std::vector<double> errors;double sum=0;
 for(size_t i=0;i<selected.size();i++){
  auto p=selected[i];double depth=R.at<double>(2,0)*p.x+R.at<double>(2,1)*p.y+R.at<double>(2,2)*p.z+t.at<double>(2);
  if(depth<.15||depth>8)return reject(5);double e=cv::norm(projected[i]-observations[i]);if(!hxFinite(e))return reject(6);errors.push_back(e);sum+=e*e;
 }
 std::sort(errors.begin(),errors.end());double rms=std::sqrt(sum/errors.size()),p95=errors[size_t((errors.size()-1)*.95)];
 if(rms>1.5||p95>2.5)return reject(6);
 cv::Mat J=jacobian.colRange(0,6),singular;cv::SVD::compute(J,singular);double condition=singular.at<double>(5)/singular.at<double>(0);
 if(!hxFinite(condition)||condition<1e-5)return reject(7);
 cv::Mat inverse=R.t(),position=-inverse*t;
 for(int row=0;row<4;row++)for(int col=0;col<4;col++)output[row*4+col]=row==col?1:0;
 for(int row=0;row<3;row++){for(int col=0;col<3;col++)output[row*4+col]=inverse.at<double>(row,col)*(col==0?1:-1);output[row*4+3]=position.at<double>(row)+(row==0?origin.x:row==1?origin.y:origin.z);}
 quality->rms_pixels=rms;quality->p95_pixels=p95;quality->condition=condition;quality->rejection=0;return 1;
} catch(...){return -2;}
