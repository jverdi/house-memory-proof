#include "hx_graph.h"
#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <queue>
#include <set>
#include <vector>
namespace {
using M=cv::Matx33d;using V=cv::Vec3d;
struct Pose{M r;V t;};
bool homogeneous(const double* p){return std::isfinite(p[12])&&std::isfinite(p[13])&&std::isfinite(p[14])&&std::isfinite(p[15])&&std::abs(p[12])+std::abs(p[13])+std::abs(p[14])+std::abs(p[15]-1)<1e-6;}
Pose read(const double* p){return {M(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),V(p[3],p[7],p[11])};}
void write(Pose p,double* out){for(int i=0;i<16;i++)out[i]=0;out[15]=1;for(int i=0;i<3;i++){out[i*4+3]=p.t[i];for(int j=0;j<3;j++)out[i*4+j]=p.r(i,j);}}
bool valid(Pose p){for(double x:p.r.val)if(!std::isfinite(x))return false;for(double x:p.t.val)if(!std::isfinite(x)||std::abs(x)>100000)return false;return cv::norm(cv::Mat(p.r.t()*p.r-M::eye()))<.005&&std::abs(cv::determinant(p.r)-1)<.005;}
V logR(M r){V v;cv::Rodrigues(r,v);return v;}
Pose relative(Pose a,Pose b){return {a.r.t()*b.r,a.r.t()*(b.t-a.t)};}
Pose perturb(Pose p,int dimension,double amount){if(dimension<3)p.t[dimension]+=amount;else{V v(0,0,0);v[dimension-3]=amount;M r;cv::Rodrigues(v,r);p.r=r*p.r;}return p;}
cv::Vec<double,6> residual(Pose a,Pose b,Pose measured){Pose q=relative(a,b);V t=q.t-measured.t,r=logR(measured.r.t()*q.r);return {t[0],t[1],t[2],r[0]*.5,r[1]*.5,r[2]*.5};}
Pose fit(const std::vector<V>& a,const std::vector<V>& b,const std::vector<int>& indices){
 V ca(0,0,0),cb(0,0,0);for(int i:indices){ca+=a[i];cb+=b[i];}ca*=1./indices.size();cb*=1./indices.size();M covariance=M::zeros();
 for(int i:indices){V x=a[i]-ca,y=b[i]-cb;for(int r=0;r<3;r++)for(int c=0;c<3;c++)covariance(r,c)+=x[r]*y[c];}
 cv::SVD svd(cv::Mat(covariance),cv::SVD::FULL_UV);cv::Mat correction=cv::Mat::eye(3,3,CV_64F);correction.at<double>(2,2)=cv::determinant(svd.vt.t()*svd.u.t())<0?-1:1;
 cv::Mat rotation=svd.vt.t()*correction*svd.u.t();M R;for(int r=0;r<3;r++)for(int c=0;c<3;c++)R(r,c)=rotation.at<double>(r,c);return {R,cb-R*ca};
}
}
extern "C" int32_t hx_depth_transform(const double* source,const double* target,uint32_t n,double* output,double* rms) try {
 if(!source||!target||!output||!rms||n<30||n>2400)return -1;
 std::vector<V>a,b;for(uint32_t i=0;i<n;i++){V x(source[i*3],source[i*3+1],source[i*3+2]),y(target[i*3],target[i*3+1],target[i*3+2]);for(int j=0;j<3;j++)if(!std::isfinite(x[j])||!std::isfinite(y[j]))return -1;if(cv::norm(x)>8||cv::norm(y)>8)return -1;a.push_back(x);b.push_back(y);}
 cv::RNG rng(0x485852474244);std::vector<int> best;
 for(int trial=0;trial<400;trial++){std::vector<int> ids;while(ids.size()<3){int i=rng.uniform(0,int(n));if(std::find(ids.begin(),ids.end(),i)==ids.end())ids.push_back(i);}if(cv::norm((a[ids[1]]-a[ids[0]]).cross(a[ids[2]]-a[ids[0]]))<.01)continue;Pose p=fit(a,b,ids);std::vector<int> inliers;for(uint32_t i=0;i<n;i++)if(cv::norm(p.r*a[i]+p.t-b[i])<.025)inliers.push_back(i);if(inliers.size()>best.size())best=std::move(inliers);}
 if(best.size()<30||best.size()<n*.65)return 0;
 Pose result=fit(a,b,best);double sum=0;V center(0,0,0);for(int i:best)center+=a[i];center*=1./best.size();cv::Mat points(best.size(),3,CV_64F);for(size_t i=0;i<best.size();i++){V d=result.r*a[best[i]]+result.t-b[best[i]];sum+=d.dot(d);for(int j=0;j<3;j++)points.at<double>(int(i),j)=a[best[i]][j]-center[j];}
 cv::PCA pca(points,cv::Mat(),cv::PCA::DATA_AS_ROW);*rms=std::sqrt(sum/best.size());if(*rms>.015||pca.eigenvalues.at<double>(1)<.025||!valid(result))return 0;write(result,output);return int32_t(best.size());
} catch(...){return -2;}
extern "C" int32_t hx_graph_optimize(const double* priors,uint32_t n,const HXGraphEdge* edges,uint32_t ne,double* output,double* maximum) try {
 if(!priors||!edges||!output||!maximum||n<3||n>120||ne<n||ne>7140)return -1;
 std::vector<Pose> poses,original,measurements;std::vector<std::vector<int>> adjacency(n);
 for(uint32_t i=0;i<n;i++){Pose p=read(priors+i*16);if(!valid(p)||!homogeneous(priors+i*16))return -1;poses.push_back(p);}original=poses;
 std::set<std::pair<uint32_t,uint32_t>> uniqueEdges;
 for(uint32_t e=0;e<ne;e++){auto edge=edges[e];if(edge.a>=n||edge.b>=n||edge.a==edge.b)return -1;Pose p=read(edge.a_from_b);if(!valid(p)||!homogeneous(edge.a_from_b)||!uniqueEdges.insert({std::min(edge.a,edge.b),std::max(edge.a,edge.b)}).second)return -1;measurements.push_back(p);adjacency[edge.a].push_back(edge.b);adjacency[edge.b].push_back(edge.a);}
 std::vector<bool> seen(n,false);std::queue<int> queue;queue.push(0);seen[0]=true;while(!queue.empty()){int i=queue.front();queue.pop();for(int j:adjacency[i])if(!seen[j]){seen[j]=true;queue.push(j);}}if(std::find(seen.begin(),seen.end(),false)!=seen.end())return 0;
 auto started=std::chrono::steady_clock::now();
 int dimensions=(n-1)*6;double damping=1e-5;
 auto cost=[&](const std::vector<Pose>& p){double value=0;for(uint32_t e=0;e<ne;e++){double x=cv::norm(residual(p[edges[e].a],p[edges[e].b],measurements[e]));value+=x<=.02?.5*x*x:.02*(x-.01);}return value;};
 double current=cost(poses);
 for(int iteration=0;iteration<30;iteration++){
  if(std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count()>20)return 0;
  cv::Mat H=cv::Mat::zeros(dimensions,dimensions,CV_64F),g=cv::Mat::zeros(dimensions,1,CV_64F);
  for(uint32_t e=0;e<ne;e++){auto edge=edges[e];auto r=residual(poses[edge.a],poses[edge.b],measurements[e]);double weight=std::min(1.,.02/std::max(1e-12,cv::norm(r)));std::vector<std::pair<int,cv::Vec<double,6>>> derivatives;
   for(int side=0;side<2;side++){int node=side?edge.b:edge.a;if(node==0)continue;for(int axis=0;axis<6;axis++){Pose a=poses[edge.a],b=poses[edge.b];if(side)b=perturb(b,axis,1e-6);else a=perturb(a,axis,1e-6);derivatives.push_back({(node-1)*6+axis,(residual(a,b,measurements[e])-r)*(1e6)});}}
   for(auto& a:derivatives){g.at<double>(a.first)+=weight*a.second.dot(r);for(auto& b:derivatives)H.at<double>(a.first,b.first)+=weight*a.second.dot(b.second);}
  }
  for(int i=0;i<dimensions;i++)H.at<double>(i,i)+=damping;
  cv::Mat step;if(!cv::solve(H,-g,step,cv::DECOMP_CHOLESKY))return 0;std::vector<Pose> proposed=poses;
  for(uint32_t node=1;node<n;node++)for(int axis=0;axis<6;axis++)proposed[node]=perturb(proposed[node],axis,step.at<double>((node-1)*6+axis));
  double next=cost(proposed);if(next<current){poses=proposed;current=next;damping=std::max(1e-9,damping*.3);if(cv::norm(step)<1e-7)break;}else{damping*=10;if(damping>1e5)break;}
 }
 *maximum=0;for(uint32_t e=0;e<ne;e++){Pose actual=relative(poses[edges[e].a],poses[edges[e].b]);double position=cv::norm(actual.t-measurements[e].t),angle=cv::norm(logR(measurements[e].r.t()*actual.r));*maximum=std::max(*maximum,position);if(position>.025||angle>3*CV_PI/180)return 0;}
 for(uint32_t i=0;i<n;i++){if(!valid(poses[i])||cv::norm(poses[i].t-original[i].t)>.25||cv::norm(logR(original[i].r.t()*poses[i].r))>10*CV_PI/180)return 0;write(poses[i],output+i*16);}return 1;
} catch(...){return -2;}
extern "C" int32_t hx_graph_selftest(double* maximum) try {
 if(!maximum)return -1;*maximum=0;cv::RNG rng(90013);std::vector<double> source(300),target(300);Pose truth{M::eye(),V(.1,-.05,.02)};
 for(int i=0;i<100;i++){V p(rng.uniform(-1.,1.),rng.uniform(-1.,1.),rng.uniform(-3.,-2.));V q=truth.r*p+truth.t;for(int j=0;j<3;j++){source[i*3+j]=p[j];target[i*3+j]=q[j]+rng.gaussian(.001);}if(i%5==0)target[i*3]+=1;}
 double fitted[16],rms;if(hx_depth_transform(source.data(),target.data(),100,fitted,&rms)<70||cv::norm(read(fitted).t-truth.t)>.005)return -10;
 constexpr int n=8;std::vector<Pose> exact;std::vector<double> priors(n*16),out(n*16);std::vector<HXGraphEdge> edges;
 for(int i=0;i<n;i++){Pose p{M::eye(),V(.1*i,.03*std::sin(i),0)};exact.push_back(p);if(i)p.t+=V(.008*i,-.003*i,.001*i);write(p,priors.data()+i*16);}
 for(int i=0;i<n;i++)for(int j=i+1;j<n;j++)if(j-i<=2||i==0&&j==n-1){HXGraphEdge e{};e.a=i;e.b=j;write(relative(exact[i],exact[j]),e.a_from_b);edges.push_back(e);}
 if(hx_graph_optimize(priors.data(),n,edges.data(),edges.size(),out.data(),&rms)!=1)return -11;
 for(int i=0;i<n;i++)*maximum=std::max(*maximum,cv::norm(read(out.data()+i*16).t-exact[i].t));if(*maximum>.0001)return -12;
 edges.back().a_from_b[3]+=1;if(hx_graph_optimize(priors.data(),n,edges.data(),edges.size(),out.data(),&rms)!=0)return -13;
 // Capacity diagnostic: a connected 120-camera route with short overlap and a
 // long loop. Independent exact relative transforms determine the answer.
 constexpr int large=120;std::vector<Pose> route;std::vector<double> inputs(large*16),outputs(large*16);std::vector<HXGraphEdge> links;
 for(int i=0;i<large;i++){Pose p{M::eye(),V(.08*i,.1*std::sin(i*.1),0)};route.push_back(p);if(i)p.t+=V(.04*std::sin(i*.05),.02*std::sin(i*.07),.01*std::sin(i*.03));write(p,inputs.data()+i*16);}
 for(int i=0;i<large;i++)for(int j=i+1;j<large;j++)if(j-i<=2||(i==0&&j==large-1)){HXGraphEdge e{};e.a=i;e.b=j;write(relative(route[i],route[j]),e.a_from_b);links.push_back(e);}
 if(hx_graph_optimize(inputs.data(),large,links.data(),links.size(),outputs.data(),&rms)!=1)return -14;
 for(int i=0;i<large;i++)*maximum=std::max(*maximum,cv::norm(read(outputs.data()+i*16).t-route[i].t));if(*maximum>.0001)return -15;
 return 1;
} catch(...){return -2;}
