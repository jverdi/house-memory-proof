#include "hx_reference_pose.h"
#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <ceres/ceres.h>
#include <ceres/rotation.h>
#include <array>
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

namespace {
struct BoardPixel {
  std::array<double,16> camera;std::array<double,4> k;double x,z,u,v;
  template<class T>bool operator()(const T* board,T* residual)const {
    T local[3]={T(x),T(0),T(z)},world[3];ceres::AngleAxisRotatePoint(board,local,world);
    for(int i=0;i<3;i++)world[i]+=board[i+3]-T(camera[i*4+3]);
    T cx=T(camera[0])*world[0]+T(camera[4])*world[1]+T(camera[8])*world[2];
    T cy=T(camera[1])*world[0]+T(camera[5])*world[1]+T(camera[9])*world[2];
    T cz=T(camera[2])*world[0]+T(camera[6])*world[1]+T(camera[10])*world[2];
    residual[0]=T(k[0])*cx/(-cz)+T(k[2])-T(u);
    residual[1]=T(k[1])*cy/cz+T(k[3])-T(v);return true;
  }
};
bool rigidMatrix(const double* matrix) {
  for(int i=0;i<16;i++)if(!std::isfinite(matrix[i])||std::abs(matrix[i])>100000)return false;
  if(std::abs(matrix[12])+std::abs(matrix[13])+std::abs(matrix[14])+std::abs(matrix[15]-1)>1e-6)return false;
  cv::Mat R(3,3,CV_64F);for(int r=0;r<3;r++)for(int c=0;c<3;c++)R.at<double>(r,c)=matrix[r*4+c];
  return cv::norm(R.t()*R-cv::Mat::eye(3,3,CV_64F))<1e-5&&std::abs(cv::determinant(R)-1)<1e-5;
}
}
extern "C" int32_t hx_reference_refine_board(const double* cameras,const double* calibration,const double* xy,
 uint32_t views,double width,const double* initial,double* pose,HXBoardFitQuality* quality) try {
  if(!cameras||!calibration||!xy||!initial||!pose||!quality||views<2||views>64||!std::isfinite(width)||width<.024||width>1.6||!rigidMatrix(initial))return -1;
  *quality={};quality->views=views;auto reject=[&](uint32_t reason){quality->rejection=reason;return 0;};
  double baseline=0;std::vector<BoardPixel> factors;
  const double sign[4][2]={{-1,1},{1,1},{1,-1},{-1,-1}};
  for(uint32_t i=0;i<views;i++) {
    const double* m=cameras+i*16;const double* k=calibration+i*6;
    if(!rigidMatrix(m))return -1;
    for(int j=0;j<6;j++)if(!std::isfinite(k[j]))return -1;
    if(k[0]<1||k[1]<1||k[0]>100000||k[1]>100000||k[4]<64||k[5]<64||k[4]>4096||k[5]>4096)return -1;
    for(uint32_t j=0;j<i;j++){double distance=0;for(int axis=0;axis<3;axis++)distance+=std::pow(m[axis*4+3]-cameras[j*16+axis*4+3],2);baseline=std::max(baseline,std::sqrt(distance));}
    for(int c=0;c<4;c++) {
      double u=xy[i*8+c*2],v=xy[i*8+c*2+1];if(!std::isfinite(u)||!std::isfinite(v)||u<2||v<2||u>=k[4]-2||v>=k[5]-2)return -1;
      const int next=(c+1)%4;if(std::hypot(u-xy[i*8+next*2],v-xy[i*8+next*2+1])<24)return reject(1);
      BoardPixel factor{};std::copy(m,m+16,factor.camera.begin());std::copy(k,k+4,factor.k.begin());
      factor.x=sign[c][0]*width/2;factor.z=sign[c][1]*width/2;factor.u=u;factor.v=v;factors.push_back(factor);
    }
  }
  if(baseline<.15)return reject(2);
  cv::Mat R(3,3,CV_64F),angle;for(int r=0;r<3;r++)for(int c=0;c<3;c++)R.at<double>(r,c)=initial[r*4+c];cv::Rodrigues(R,angle);
  double parameters[6];for(int i=0;i<3;i++){parameters[i]=angle.at<double>(i);parameters[i+3]=initial[i*4+3];}
  ceres::Problem problem;
  // No robust outlier loss: an inconsistent observed board must not disappear
  // from the objective to make a convenient subset look trustworthy.
  for(auto factor:factors)problem.AddResidualBlock(new ceres::AutoDiffCostFunction<BoardPixel,2,6>(new BoardPixel(factor)),nullptr,parameters);
  ceres::Solver::Options options;options.linear_solver_type=ceres::DENSE_QR;options.max_num_iterations=40;options.max_solver_time_in_seconds=1;options.num_threads=1;options.logging_type=ceres::SILENT;
  ceres::Solver::Summary summary;ceres::Solve(options,&problem,&summary);if(!summary.IsSolutionUsable())return reject(3);
  cv::Mat fittedAngle(3,1,CV_64F,parameters),fittedR;cv::Rodrigues(fittedAngle,fittedR);
  double distance=0;for(int i=0;i<3;i++)distance+=std::pow(parameters[i+3]-initial[i*4+3],2);
  cv::Mat delta=fittedR*R.t();double rotation=std::acos(std::max(-1.,std::min(1.,(cv::trace(delta)[0]-1)*.5)));
  if(std::sqrt(distance)>.10||rotation>10*CV_PI/180)return reject(4);
  double squared=0;
  for(const auto& f:factors) {
    double local[3]={f.x,0,f.z},world[3];ceres::AngleAxisRotatePoint(parameters,local,world);
    for(int i=0;i<3;i++)world[i]+=parameters[i+3]-f.camera[i*4+3];
    double depth=-(f.camera[2]*world[0]+f.camera[6]*world[1]+f.camera[10]*world[2]);
    if(!std::isfinite(depth)||depth<.15||depth>5)return reject(5);
    double residual[2];f(parameters,residual);double error=std::hypot(residual[0],residual[1]);
    if(!std::isfinite(error))return reject(6);squared+=error*error;quality->maximum_pixels=std::max(quality->maximum_pixels,error);
  }
  quality->rms_pixels=std::sqrt(squared/factors.size());if(quality->rms_pixels>1||quality->maximum_pixels>2.5)return reject(7);
  std::copy(initial,initial+16,pose);for(int r=0;r<3;r++){for(int c=0;c<3;c++)pose[r*4+c]=fittedR.at<double>(r,c);pose[r*4+3]=parameters[r+3];}
  return rigidMatrix(pose)?1:reject(8);
}catch(...){return -2;}

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
  // Independent source-camera projection of a fixed metric board. Deliberately
  // perturb the initializer; require all views, including a corrupted last view.
  for(int trial=0;trial<12;trial++) {
    cv::Mat rv=(cv::Mat_<double>(3,1)<<.12,.38+trial*.01,-.03),R;cv::Rodrigues(rv,R);
    cv::Mat boardR=toNative*R*fromImage,boardT=(cv::Mat_<double>(3,1)<<.15,.08,-2.4);
    std::vector<double> cameras,calibration,pixels;double seed[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
    for(int r=0;r<3;r++){for(int c=0;c<3;c++)seed[r*4+c]=boardR.at<double>(r,c);seed[r*4+3]=boardT.at<double>(r)+(r==0?.008:r==2?.016:0);}
    const double sx[4]={-1,1,1,-1},sz[4]={1,1,-1,-1};
    for(int view=0;view<4;view++) {
      double x=(view-1.5)*.16,y=std::sin(view)*.04;
      double m[16]={1,0,0,x,0,1,0,y,0,0,1,0,0,0,0,1};cameras.insert(cameras.end(),m,m+16);calibration.insert(calibration.end(),{1400,1400,960,720,1920,1440});
      for(int c=0;c<4;c++) {
        cv::Mat local=(cv::Mat_<double>(3,1)<<sx[c]*.072,0,sz[c]*.072),world=boardR*local+boardT;
        pixels.push_back(1400*(world.at<double>(0)-x)/(-world.at<double>(2))+960+rng.gaussian(.05));
        pixels.push_back(1400*(world.at<double>(1)-y)/world.at<double>(2)+720+rng.gaussian(.05));
      }
    }
    double out[16];HXBoardFitQuality quality{};
    if(hx_reference_refine_board(cameras.data(),calibration.data(),pixels.data(),4,.144,seed,out,&quality)!=1)return -30;
    double error=0;for(int axis=0;axis<3;axis++)error+=std::pow(out[axis*4+3]-boardT.at<double>(axis),2);
    if(std::sqrt(error)>.003)return -31;
    auto broken=pixels;for(int c=0;c<4;c++)broken[24+c*2]+=20;
    if(hx_reference_refine_board(cameras.data(),calibration.data(),broken.data(),4,.144,seed,out,&quality)!=0)return -32;
    auto stationary=cameras;for(int v=1;v<4;v++)std::copy(cameras.begin(),cameras.begin()+16,stationary.begin()+v*16);
    if(hx_reference_refine_board(stationary.data(),calibration.data(),pixels.data(),4,.144,seed,out,&quality)!=0)return -33;
    if(hx_reference_refine_board(cameras.data(),calibration.data(),pixels.data(),4,.216,seed,out,&quality)!=0)return -34;
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
