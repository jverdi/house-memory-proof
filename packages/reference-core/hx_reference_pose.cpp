#include "hx_reference_pose.h"
#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <algorithm>
#include <cmath>
#include <set>
#include <vector>
namespace {
struct Estimate {cv::Mat r,t,R,position;double rms=0,maximum=0,condition=0;};
bool solve(const std::vector<cv::Point3d>& world,const std::vector<cv::Point2d>& image,const cv::Mat& K,Estimate& out) {
  if(!cv::solvePnP(world,image,K,cv::noArray(),out.r,out.t,false,cv::SOLVEPNP_EPNP))return false;
  cv::solvePnPRefineLM(world,image,K,cv::noArray(),out.r,out.t);
  cv::Rodrigues(out.r,out.R);out.position=-out.R.t()*out.t;
  std::vector<cv::Point2d> projected;cv::Mat jacobian,singular;
  cv::projectPoints(world,out.r,out.t,K,cv::noArray(),projected,jacobian);
  cv::SVD::compute(jacobian.colRange(0,6),singular);out.condition=singular.at<double>(5)/singular.at<double>(0);
  double sum=0;
  for(size_t i=0;i<world.size();i++) {
    const auto& p=world[i];double z=out.R.at<double>(2,0)*p.x+out.R.at<double>(2,1)*p.y+out.R.at<double>(2,2)*p.z+out.t.at<double>(2);
    double error=cv::norm(projected[i]-image[i]);if(!std::isfinite(error)||z<.15||z>5)return false;
    sum+=error*error;out.maximum=std::max(out.maximum,error);
  }
  out.rms=std::sqrt(sum/world.size());return out.rms<=1&&out.maximum<=2&&std::isfinite(out.condition)&&out.condition>=1e-5;
}
}
extern "C" int32_t hx_reference_pose(const double* xyz,const double* xy,const uint32_t* ids,uint32_t boards,
                                    double fx,double fy,double cx,double cy,uint32_t width,uint32_t height,
                                    double* pose,HXReferenceQuality* quality) try {
  if(!xyz||!xy||!ids||!pose||!quality||boards<4||boards>16||width<64||height<64||width>4096||height>4096||
     !std::isfinite(fx)||!std::isfinite(fy)||!std::isfinite(cx)||!std::isfinite(cy)||fx<1||fy<1||fx>100000||fy>100000)return -1;
  *quality={};quality->boards=boards;auto reject=[&](uint32_t gate){quality->rejection=gate;return 0;};
  std::set<uint32_t> identities;std::vector<cv::Point3d> world;std::vector<cv::Point2d> image;cv::Mat centres(boards,3,CV_64F);
  cv::Point3d origin(0,0,0);
  for(uint32_t board=0;board<boards;board++) {
    if(ids[board]>=587||!identities.insert(ids[board]).second)return reject(1);
    cv::Point3d centre(0,0,0);
    for(uint32_t corner=0;corner<4;corner++) {
      uint32_t p=board*4+corner;double x=xyz[p*3],y=xyz[p*3+1],z=xyz[p*3+2],u=xy[p*2],v=xy[p*2+1];
      if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(z)||std::max({std::abs(x),std::abs(y),std::abs(z)})>100000||!std::isfinite(u)||!std::isfinite(v)||u<2||v<2||u>=width-2||v>=height-2)return -1;
      world.emplace_back(x,y,z);image.emplace_back(u,v);centre+=cv::Point3d(x,y,z);
    }
    centre*=.25;origin+=centre;centres.at<double>(board,0)=centre.x;centres.at<double>(board,1)=centre.y;centres.at<double>(board,2)=centre.z;
    for(int j=0;j<4;j++)if(cv::norm(image[board*4+j]-image[board*4+(j+1)%4])<24)return reject(2);
  }
  // Explicitly refuse clustered/coplanar control centres. Plan drawings and
  // a single planar marker cannot silently establish a house-wide pose.
  cv::PCA spread(centres,cv::Mat(),cv::PCA::DATA_AS_ROW);
  if(spread.eigenvalues.at<double>(0)<.09||spread.eigenvalues.at<double>(1)<.0225||spread.eigenvalues.at<double>(2)<.0016)return reject(3);
  origin*=1./boards;for(auto& p:world)p-=origin;
  cv::Mat K=(cv::Mat_<double>(3,3)<<fx,0,cx,0,fy,cy,0,0,1);Estimate fitted;
  if(!solve(world,image,K,fitted))return reject(4);
  quality->rms_pixels=fitted.rms;quality->condition=fitted.condition;
  for(uint32_t excluded=0;excluded<boards;excluded++) {
    std::vector<cv::Point3d> fitWorld,checkWorld;std::vector<cv::Point2d> fitImage,checkImage;
    for(uint32_t i=0;i<boards*4;i++) {
      if(i/4==excluded){checkWorld.push_back(world[i]);checkImage.push_back(image[i]);}
      else {fitWorld.push_back(world[i]);fitImage.push_back(image[i]);}
    }
    Estimate independent;if(!solve(fitWorld,fitImage,K,independent))return reject(5);
    double shift=cv::norm(independent.position-fitted.position);
    cv::Mat delta=independent.R*fitted.R.t();double angle=std::acos(std::max(-1.,std::min(1.,(cv::trace(delta)[0]-1)*.5)));
    quality->maximum_leave_out_shift_metres=std::max(quality->maximum_leave_out_shift_metres,shift);
    if(shift>.02||angle>CV_PI/180)return reject(6);
    std::vector<cv::Point2d> prediction;cv::projectPoints(checkWorld,independent.r,independent.t,K,cv::noArray(),prediction);
    for(size_t i=0;i<checkImage.size();i++) {
      double error=cv::norm(prediction[i]-checkImage[i]);quality->maximum_check_pixels=std::max(quality->maximum_check_pixels,error);
      if(!std::isfinite(error)||error>2)return reject(7);
    }
  }
  const cv::Mat rotation=fitted.R.t();
  for(int row=0;row<4;row++)for(int col=0;col<4;col++)pose[row*4+col]=row==col?1:0;
  for(int row=0;row<3;row++) {
    for(int col=0;col<3;col++)pose[row*4+col]=rotation.at<double>(row,col)*(col==0?1:-1);
    pose[row*4+3]=fitted.position.at<double>(row)+(row==0?origin.x:row==1?origin.y:origin.z);
  }
  return 1;
} catch(...){return -2;}

extern "C" int32_t hx_reference_selftest(double* maximum) try {
  if(!maximum)return -1;*maximum=0;
  const uint32_t count=6;uint32_t ids[count]={1,7,19,33,102,301};
  const cv::Point3d centres[count]={{-.75,-.5,2.4},{.65,.6,2.4},{.1,.05,2.1},{.85,-.55,2.0},{.7,.5,3.0},{-.65,.4,2.8}};
  std::vector<cv::Point3d> points;std::vector<double> xyz;
  const double offsets[4][2]={{-1,1},{1,1},{1,-1},{-1,-1}};
  for(uint32_t board=0;board<count;board++)for(int corner=0;corner<4;corner++) {
    double u=offsets[corner][0]*.12,v=offsets[corner][1]*.12,angle=board>=3 ? -.4:0;
    cv::Point3d p=centres[board]+cv::Point3d(std::cos(angle)*u,v,std::sin(angle)*u);points.push_back(p);xyz.insert(xyz.end(),{p.x,p.y,p.z});
  }
  cv::RNG rng(0x4858524546455245ULL);cv::Mat K=(cv::Mat_<double>(3,3)<<1400,0,960,0,1400,720,0,0,1);
  for(int trial=0;trial<50;trial++) {
    cv::Mat r=(cv::Mat_<double>(3,1)<<rng.uniform(-.04,.04),rng.uniform(-.04,.04),rng.uniform(-.02,.02));
    cv::Mat position=(cv::Mat_<double>(3,1)<<rng.uniform(-.08,.08),rng.uniform(-.08,.08),rng.uniform(-.04,.04)),R;cv::Rodrigues(r,R);
    cv::Mat t=-R*position;std::vector<cv::Point2d> rendered;cv::projectPoints(points,r,t,K,cv::noArray(),rendered);
    std::vector<double> xy;for(auto p:rendered){xy.push_back(p.x+rng.gaussian(.08));xy.push_back(p.y+rng.gaussian(.08));}
    double out[16];HXReferenceQuality quality{};
    if(hx_reference_pose(xyz.data(),xy.data(),ids,count,1400,1400,960,720,1920,1440,out,&quality)!=1)return -10;
    double error=0;for(int i=0;i<3;i++)error+=std::pow(out[i*4+3]-position.at<double>(i),2);*maximum=std::max(*maximum,std::sqrt(error));
    if(*maximum>.003)return -11;
    // A moved/wrong board is not discarded as a convenient RANSAC outlier.
    auto moved=xy;for(int corner=0;corner<4;corner++)moved[corner*2]+=20;
    if(hx_reference_pose(xyz.data(),moved.data(),ids,count,1400,1400,960,720,1920,1440,out,&quality)!=0)return -12;
    uint32_t duplicate[count]={1,1,19,33,102,301};
    if(hx_reference_pose(xyz.data(),xy.data(),duplicate,count,1400,1400,960,720,1920,1440,out,&quality)!=0)return -13;
    auto shifted=xyz;for(size_t i=0;i<points.size();i++){shifted[i*3]+=80;shifted[i*3+1]-=60;shifted[i*3+2]+=12;}
    double translated[16];
    if(hx_reference_pose(shifted.data(),xy.data(),ids,count,1400,1400,960,720,1920,1440,translated,&quality)!=1)return -14;
    double delta[3]={80,-60,12};for(int i=0;i<3;i++)if(std::abs(translated[i*4+3]-delta[i]-position.at<double>(i))>.003)return -15;
  }
  // Independently recover the stored image-board coordinate frame from pixels.
  // No AR image-anchor pose is supplied to the single-board solver.
  const std::vector<cv::Point3d> square={{-.072,.072,0},{.072,.072,0},{.072,-.072,0},{-.072,-.072,0}};
  const cv::Mat toNative=(cv::Mat_<double>(3,3)<<1,0,0,0,-1,0,0,0,-1);
  const cv::Mat fromImage=(cv::Mat_<double>(3,3)<<1,0,0,0,0,1,0,-1,0);
  for(int trial=0;trial<25;trial++) {
    cv::Mat r=(cv::Mat_<double>(3,1)<<.1,.35+trial*.008,-.04),t=(cv::Mat_<double>(3,1)<<.15,-.08,2.4),R;
    cv::Rodrigues(r,R);std::vector<cv::Point2d> rendered;cv::projectPoints(square,r,t,K,cv::noArray(),rendered);
    double xy[8];for(int i=0;i<4;i++){xy[i*2]=rendered[i].x+rng.gaussian(.02);xy[i*2+1]=rendered[i].y+rng.gaussian(.02);}
    double out[16];HXTagPoseQuality quality{};
    if(hx_reference_measure_tag(xy,.144,1400,1400,960,720,1920,1440,out,&quality)!=1)return -20;
    cv::Mat expectedR=toNative*R*fromImage,expectedT=toNative*t;double error=0;
    for(int row=0;row<3;row++) {
      error+=std::pow(out[row*4+3]-expectedT.at<double>(row),2);
      for(int col=0;col<3;col++)if(std::abs(out[row*4+col]-expectedR.at<double>(row,col))>.01)return -21;
    }
    if(std::sqrt(error)>.003)return -22;
    if(hx_reference_measure_tag(xy,-1,1400,1400,960,720,1920,1440,out,&quality)!=-1)return -23;
    xy[2]=xy[0];xy[3]=xy[1];
    if(hx_reference_measure_tag(xy,.144,1400,1400,960,720,1920,1440,out,&quality)!=0)return -24;
  }
  return 1;
} catch(...){return -2;}

extern "C" int32_t hx_reference_measure_tag(const double* xy,double widthMetres,double fx,double fy,double cx,double cy,
                                            uint32_t width,uint32_t height,double* pose,HXTagPoseQuality* quality) try {
  if(!xy||!pose||!quality||!std::isfinite(widthMetres)||widthMetres<.024||widthMetres>1.6||
     width<64||height<64||width>4096||height>4096||!std::isfinite(fx)||!std::isfinite(fy)||!std::isfinite(cx)||!std::isfinite(cy)||fx<1||fy<1||fx>100000||fy>100000)return -1;
  *quality={};auto reject=[&](uint32_t reason){quality->rejection=reason;return 0;};
  const double h=widthMetres/2;
  std::vector<cv::Point3d> object={{-h,h,0},{h,h,0},{h,-h,0},{-h,-h,0}};
  std::vector<cv::Point2d> image;
  for(int i=0;i<4;i++) {
    double x=xy[i*2],y=xy[i*2+1];
    if(!std::isfinite(x)||!std::isfinite(y)||x<2||y<2||x>=width-2||y>=height-2)return -1;
    image.emplace_back(x,y);
  }
  for(int i=0;i<4;i++)if(cv::norm(image[i]-image[(i+1)%4])<24)return reject(1);
  cv::Mat K=(cv::Mat_<double>(3,3)<<fx,0,cx,0,fy,cy,0,0,1);
  std::vector<cv::Mat> rotations,translations;
  if(cv::solvePnPGeneric(object,image,K,cv::noArray(),rotations,translations,false,cv::SOLVEPNP_IPPE_SQUARE)<1)return reject(2);
  struct Candidate {cv::Mat R,t;double rms;};std::vector<Candidate> candidates;
  for(size_t i=0;i<rotations.size();i++) {
    // Keep the two IPPE alternatives distinct for the ambiguity check; a
    // shared iterative initialization must not collapse them into one vote.
    std::vector<cv::Point2d> projected;cv::projectPoints(object,rotations[i],translations[i],K,cv::noArray(),projected);
    cv::Mat R;cv::Rodrigues(rotations[i],R);double sum=0,maximum=0;bool valid=true;
    for(int j=0;j<4;j++) {
      double z=R.at<double>(2,0)*object[j].x+R.at<double>(2,1)*object[j].y+translations[i].at<double>(2);
      double e=cv::norm(projected[j]-image[j]);if(!std::isfinite(e)||z<.15||z>5)valid=false;
      sum+=e*e;maximum=std::max(maximum,e);
    }
    if(valid&&maximum<=2)candidates.push_back({R,translations[i],std::sqrt(sum/4)});
  }
  if(candidates.empty())return reject(3);
  std::sort(candidates.begin(),candidates.end(),[](const Candidate& a,const Candidate& b){return a.rms<b.rms;});
  const auto& best=candidates[0];quality->rms_pixels=best.rms;
  if(best.rms>.8)return reject(4);
  if(candidates.size()>1) {
    const auto& second=candidates[1];quality->alternative_pixels=second.rms;
    cv::Mat delta=best.R*second.R.t();double angle=std::acos(std::max(-1.,std::min(1.,(cv::trace(delta)[0]-1)*.5)));
    if(second.rms<=best.rms*2+.05&&(cv::norm(best.t-second.t)>.003||angle>2*CV_PI/180))return reject(5);
  }
  const cv::Mat toNative=(cv::Mat_<double>(3,3)<<1,0,0,0,-1,0,0,0,-1);
  const cv::Mat fromImage=(cv::Mat_<double>(3,3)<<1,0,0,0,0,1,0,-1,0);
  cv::Mat R=toNative*best.R*fromImage,t=toNative*best.t;
  for(int row=0;row<4;row++)for(int col=0;col<4;col++)pose[row*4+col]=row==col?1:0;
  for(int row=0;row<3;row++){for(int col=0;col<3;col++)pose[row*4+col]=R.at<double>(row,col);pose[row*4+3]=t.at<double>(row);}
  return 1;
} catch(...){return -2;}
