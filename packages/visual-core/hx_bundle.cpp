#define EIGEN_MPL2_ONLY
#include "hx_bundle.h"
#include <ceres/ceres.h>
#include <ceres/rotation.h>
#include <Eigen/Geometry>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <iostream>
#include <set>
#include <vector>
namespace {
using Camera=std::array<double,6>;using Point=std::array<double,3>;
struct ImageFactor {
 double u,v,fx,fy,cx,cy;
 template<class T> bool operator()(const T* c,const T* p,T* residual)const {
  T q[3];ceres::AngleAxisRotatePoint(c,p,q);for(int i=0;i<3;i++)q[i]+=c[i+3];
  residual[0]=(T(fx)*q[0]/(-q[2])+T(cx)-T(u));
  residual[1]=(-T(fy)*q[1]/(-q[2])+T(cy)-T(v));return true;
 }
};
struct DepthFactor {
 double depth;
 template<class T>bool operator()(const T* c,const T* p,T* r)const {T q[3];ceres::AngleAxisRotatePoint(c,p,q);r[0]=(-q[2]-c[5]-T(depth))/T(.01);return true;}
};
struct CameraPrior {
 Point center;std::array<double,9> rotation;
 template<class T>bool operator()(const T* c,T* r)const {
  T inverse[3]={-c[0],-c[1],-c[2]},negative[3]={-c[3],-c[4],-c[5]},position[3];ceres::AngleAxisRotatePoint(inverse,negative,position);
  for(int i=0;i<3;i++)r[i]=(position[i]-T(center[i]))/T(.05);
  for(int col=0;col<3;col++){T axis[3]={T(0),T(0),T(0)},rotated[3];axis[col]=T(1);ceres::AngleAxisRotatePoint(c,axis,rotated);for(int row=0;row<3;row++)r[3+col*3+row]=(rotated[row]-T(rotation[col*3+row]))/T(.0872664626);}
  return true;
 }
};
bool readCamera(const double* a,Camera& c) {
 Eigen::Matrix3d R;Eigen::Vector3d t(a[3],a[7],a[11]);
 for(int r=0;r<3;r++)for(int col=0;col<3;col++)R(r,col)=a[r*4+col];
 for(int i=0;i<16;i++)if(!std::isfinite(a[i]))return false;
 if((R.transpose()*R-Eigen::Matrix3d::Identity()).norm()>.005||std::abs(R.determinant()-1)>.005||std::abs(a[12])+std::abs(a[13])+std::abs(a[14])+std::abs(a[15]-1)>1e-6||t.norm()>100000)return false;
 Eigen::AngleAxisd angle(R.transpose());Eigen::Vector3d axis=angle.axis()*angle.angle(),translation=-R.transpose()*t;
 for(int i=0;i<3;i++){c[i]=axis[i];c[i+3]=translation[i];}return true;
}
void writeCamera(const Camera& c,double* output){
 Eigen::Vector3d angle(c[0],c[1],c[2]);Eigen::Matrix3d R=Eigen::Matrix3d::Identity();if(angle.norm()>1e-12)R=Eigen::AngleAxisd(angle.norm(),angle.normalized()).toRotationMatrix();
 Eigen::Vector3d p=-R.transpose()*Eigen::Vector3d(c[3],c[4],c[5]);
 std::fill(output,output+16,0);output[15]=1;
 for(int r=0;r<3;r++){for(int col=0;col<3;col++)output[r*4+col]=R(col,r);output[r*4+3]=p[r];}
}
struct Score{double rms=0,p95=0,depth=0;bool valid=true;};
Score score(const std::vector<Camera>& c,const std::vector<Point>& p,const double* k,const HXBundleObservation* observations,uint32_t count,bool fitting) {
 Score s;std::vector<double> errors;double depth=0;int depths=0;
 for(uint32_t i=0;i<count;i++){const auto& o=observations[i];if(bool(o.fit)!=fitting)continue;double q[3];ceres::AngleAxisRotatePoint(c[o.camera].data(),p[o.point].data(),q);for(int j=0;j<3;j++)q[j]+=c[o.camera][j+3];
  if(-q[2]<.15||-q[2]>8){s.valid=false;return s;}
  const double* intr=k+o.camera*4;double dx=intr[0]*q[0]/(-q[2])+intr[2]-o.u,dy=-intr[1]*q[1]/(-q[2])+intr[3]-o.v;double e=std::hypot(dx,dy);if(!std::isfinite(e)){s.valid=false;return s;}errors.push_back(e);s.rms+=e*e;
  if(o.depth>0){double d=-q[2]-o.depth;depth+=d*d;depths++;}
 }
 if(errors.empty()){s.valid=false;return s;}std::sort(errors.begin(),errors.end());s.rms=std::sqrt(s.rms/errors.size());s.p95=errors[size_t((errors.size()-1)*.95)];s.depth=depths?std::sqrt(depth/depths):0;return s;
}
}
extern "C" int32_t hx_bundle_optimize(const double* input,uint32_t nc,const double* initial,uint32_t np,const double* k,const HXBundleObservation* obs,uint32_t no,double* outC,double* outP,HXBundleQuality* quality) try {
 if(!input||!initial||!k||!obs||!outC||!outP||!quality||nc<3||nc>120||np<20||np>2000||no<np*3||no>24000)return -1;
 *quality={};auto start=std::chrono::steady_clock::now();std::vector<Camera> cameras(nc);std::vector<Point> points(np);std::vector<int> fits(np,0),checks(np,0),cameraFits(nc,0);std::set<std::pair<uint32_t,uint32_t>> seen;
 for(uint32_t c=0;c<nc;c++){if(!readCamera(input+c*16,cameras[c]))return -1;for(int j=0;j<4;j++)if(!std::isfinite(k[c*4+j]))return -1;if(k[c*4]<=0||k[c*4+1]<=0)return -1;}
 for(uint32_t p=0;p<np;p++)for(int j=0;j<3;j++){double v=initial[p*3+j];if(!std::isfinite(v)||std::abs(v)>100000)return -1;points[p][j]=v;}
 for(uint32_t i=0;i<no;i++){const auto& o=obs[i];if(o.camera>=nc||o.point>=np||o.fit>1||!std::isfinite(o.u)||!std::isfinite(o.v)||!std::isfinite(o.depth)||o.depth<0||o.depth>8||!seen.insert({o.camera,o.point}).second)return -1;if(o.fit){fits[o.point]++;cameraFits[o.camera]++;}else checks[o.point]++;}
 for(uint32_t p=0;p<np;p++)if(fits[p]<2||checks[p]<1)return -1;
 if(cameraFits[0]<20)return -1;
 auto initialCheck=score(cameras,points,k,obs,no,false);if(!initialCheck.valid)return 0;quality->initial_check_rms=initialCheck.rms;
 ceres::Problem problem;
 for(uint32_t i=0;i<no;i++){const auto& o=obs[i];if(!o.fit)continue;const double* intr=k+o.camera*4;
  problem.AddResidualBlock(new ceres::AutoDiffCostFunction<ImageFactor,2,6,3>(new ImageFactor{o.u,o.v,intr[0],intr[1],intr[2],intr[3]}),new ceres::HuberLoss(1.5),cameras[o.camera].data(),points[o.point].data());
  if(o.depth>0)problem.AddResidualBlock(new ceres::AutoDiffCostFunction<DepthFactor,1,6,3>(new DepthFactor{o.depth}),new ceres::HuberLoss(1.5),cameras[o.camera].data(),points[o.point].data());
 }
 for(uint32_t c=0;c<nc;c++){
  if(!problem.HasParameterBlock(cameras[c].data()))continue;
  if(c==0||cameraFits[c]<20){problem.SetParameterBlockConstant(cameras[c].data());continue;}
  CameraPrior prior;prior.center={input[c*16+3],input[c*16+7],input[c*16+11]};for(int col=0;col<3;col++)for(int row=0;row<3;row++)prior.rotation[col*3+row]=input[c*16+col*4+row];
  problem.AddResidualBlock(new ceres::AutoDiffCostFunction<CameraPrior,12,6>(new CameraPrior(prior)),nullptr,cameras[c].data());quality->optimized_cameras++;
 }
 ceres::Solver::Options options;options.linear_solver_type=ceres::SPARSE_SCHUR;options.sparse_linear_algebra_library_type=ceres::EIGEN_SPARSE;options.max_num_iterations=40;options.max_solver_time_in_seconds=20;options.num_threads=1;options.minimizer_progress_to_stdout=false;options.logging_type=ceres::SILENT;
 ceres::Solver::Summary summary;ceres::Solve(options,&problem,&summary);quality->iterations=summary.iterations.size();quality->seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();if(!summary.IsSolutionUsable())return 0;
 const auto check=score(cameras,points,k,obs,no,false),fit=score(cameras,points,k,obs,no,true);quality->final_check_rms=check.rms;quality->fit_rms=fit.rms;quality->depth_rms=fit.depth;
 if(!check.valid||!fit.valid||check.rms>2||check.p95>3||check.rms>initialCheck.rms+.2||fit.rms>1.5||fit.depth>.02)return 0;
 std::vector<double> output(nc*16);
 for(uint32_t c=0;c<nc;c++){
  writeCamera(cameras[c],output.data()+c*16);double position=0,trace=0;for(int r=0;r<3;r++){position+=std::pow(output[c*16+r*4+3]-input[c*16+r*4+3],2);for(int col=0;col<3;col++)trace+=output[c*16+r*4+col]*input[c*16+r*4+col];}
  if(std::sqrt(position)>.25||std::acos(std::clamp((trace-1)/2,-1.,1.))>10*3.141592653589793/180)return 0;
 }
 for(uint32_t p=0;p<np;p++){double change=0;for(int j=0;j<3;j++)change+=std::pow(points[p][j]-initial[p*3+j],2);if(std::sqrt(change)>.25)return 0;}
 std::copy(output.begin(),output.end(),outC);for(uint32_t p=0;p<np;p++)std::copy(points[p].begin(),points[p].end(),outP+p*3);return 1;
} catch(...){return -2;}
namespace {
bool derivativeChecks() {
 Camera camera{.03,-.07,.02,.1,-.04,.02};Point point{.4,.3,-2.4};
 ImageFactor image{400,200,500,510,320,240};DepthFactor depth{2.5};
 ceres::AutoDiffCostFunction<ImageFactor,2,6,3> imageCost(new ImageFactor(image));
 ceres::AutoDiffCostFunction<DepthFactor,1,6,3> depthCost(new DepthFactor(depth));
 for(auto* cost:std::vector<ceres::CostFunction*>{&imageCost,&depthCost}) {
  const int rows=cost->num_residuals();std::vector<double> value(rows),cameraJ(rows*6),pointJ(rows*3);double* jacobians[]={cameraJ.data(),pointJ.data()};const double* params[]={camera.data(),point.data()};
  if(!cost->Evaluate(params,value.data(),jacobians))return false;
  for(int block=0;block<2;block++)for(int axis=0;axis<(block?3:6);axis++) {
   double* parameter=block?point.data():camera.data();const double original=parameter[axis];std::vector<double> plus(rows),minus(rows);parameter[axis]=original+1e-6;cost->Evaluate(params,plus.data(),nullptr);parameter[axis]=original-1e-6;cost->Evaluate(params,minus.data(),nullptr);parameter[axis]=original;
   for(int row=0;row<rows;row++){double numeric=(plus[row]-minus[row])/2e-6,automatic=(block?pointJ:cameraJ)[row*(block?3:6)+axis];if(std::abs(numeric-automatic)>1e-5*std::max(1.,std::abs(numeric)))return false;}
  }
 }
 CameraPrior prior;prior.center={.1,.2,.3};prior.rotation={1,0,0,0,1,0,0,0,1};ceres::AutoDiffCostFunction<CameraPrior,12,6> priorCost(new CameraPrior(prior));
 double value[12],jacobian[72];double* derivatives[]={jacobian};const double* params[]={camera.data()};if(!priorCost.Evaluate(params,value,derivatives))return false;
 for(int axis=0;axis<6;axis++){double original=camera[axis],plus[12],minus[12];camera[axis]=original+1e-6;priorCost.Evaluate(params,plus,nullptr);camera[axis]=original-1e-6;priorCost.Evaluate(params,minus,nullptr);camera[axis]=original;for(int row=0;row<12;row++){double numeric=(plus[row]-minus[row])/2e-6;if(std::abs(numeric-jacobian[row*6+axis])>1e-5*std::max(1.,std::abs(numeric)))return false;}}
 return true;
}
}
extern "C" int32_t hx_bundle_selftest(double* maximum) try {
 if(!maximum)return -1;*maximum=0;if(!derivativeChecks())return -9;constexpr int nc=6,np=80;std::vector<double> cameras(nc*16,0),truth(nc*16,0),points(np*3),initial(np*3),k(nc*4),outC(nc*16),outP(np*3);std::vector<HXBundleObservation> observations;
 for(int c=0;c<nc;c++){truth[c*16]=truth[c*16+5]=truth[c*16+10]=truth[c*16+15]=1;truth[c*16+3]=c*.15;std::copy(truth.begin()+c*16,truth.begin()+(c+1)*16,cameras.begin()+c*16);if(c>0)cameras[c*16+3]+=.01;double intr[4]={500,500,320,240};std::copy(intr,intr+4,k.begin()+c*4);}
 for(int p=0;p<np;p++){points[p*3]=(p%10)*.15-.3;points[p*3+1]=(p/10)*.12-.4;points[p*3+2]=-2.2-(p%3)*.25;for(int j=0;j<3;j++)initial[p*3+j]=points[p*3+j]+(j==0?.005:0);
  for(int c=0;c<nc;c++){double z=-points[p*3+2],x=points[p*3]-truth[c*16+3],y=points[p*3+1];observations.push_back({uint32_t(c),uint32_t(p),uint32_t(c!=(p%5+1)),500*x/z+320,-500*y/z+240,z});}
 }
 HXBundleQuality q;int result=hx_bundle_optimize(cameras.data(),nc,initial.data(),np,k.data(),observations.data(),observations.size(),outC.data(),outP.data(),&q);if(result!=1)return -10;
 for(int p=0;p<np;p++){double e=0;for(int j=0;j<3;j++)e+=std::pow(outP[p*3+j]-points[p*3+j],2);*maximum=std::max(*maximum,std::sqrt(e));}if(*maximum>.003||q.final_check_rms>=q.initial_check_rms)return -11;
 for(auto& o:observations)if(!o.fit)o.u+=30;
 if(hx_bundle_optimize(cameras.data(),nc,initial.data(),np,k.data(),observations.data(),observations.size(),outC.data(),outP.data(),&q)!=0)return -12;
 return 1;
} catch(...){return -2;}
#ifdef HX_BUNDLE_TEST_MAIN
int main(){double error=0;int status=hx_bundle_selftest(&error);std::cout<<"{\"passed\":"<<(status==1?"true":"false")<<",\"status\":"<<status<<",\"maximumPointErrorMetres\":"<<error<<",\"physicalQualification\":false}\n";return status==1?0:1;}
#endif
