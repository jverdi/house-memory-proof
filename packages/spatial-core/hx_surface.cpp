#include "hx_surface.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <vector>
namespace {
struct Vec {double x,y,z;Vec operator+(Vec b)const{return{x+b.x,y+b.y,z+b.z};}Vec operator-(Vec b)const{return{x-b.x,y-b.y,z-b.z};}Vec operator*(double s)const{return{x*s,y*s,z*s};}};
double dot(Vec a,Vec b){return a.x*b.x+a.y*b.y+a.z*b.z;}
Vec cross(Vec a,Vec b){return{a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
struct Key {int x,y,z;bool operator==(const Key&b)const{return x==b.x&&y==b.y&&z==b.z;}bool operator<(const Key&b)const{return x!=b.x?x<b.x:y!=b.y?y<b.y:z<b.z;}};
struct Hash {size_t operator()(Key k)const{return size_t(uint32_t(k.x)*73856093u)^size_t(uint32_t(k.y)*19349663u)^size_t(uint32_t(k.z)*83492791u);}};
struct Cell {double value=0,weight=0;uint32_t views=0,last=UINT32_MAX;};
struct Surface {double voxel,band;uint32_t capacity,dropped=0;std::unordered_map<Key,Cell,Hash> cells;Surface(double v,uint32_t n):voxel(v),band(v*3),capacity(n){cells.reserve(std::min(n,100000u));}};
Vec world(double x,double y,double z,const double*m){return{m[0]*x-m[1]*y-m[2]*z+m[3],-(m[8]*x-m[9]*y-m[10]*z+m[11]),m[4]*x-m[5]*y-m[6]*z+m[7]};}
Vec camera(Vec p,const double*m){Vec d={p.x-m[3],p.z-m[7],-p.y-m[11]};return{m[0]*d.x+m[4]*d.y+m[8]*d.z,-(m[1]*d.x+m[5]*d.y+m[9]*d.z),-(m[2]*d.x+m[6]*d.y+m[10]*d.z)};}
}
extern "C" void* hx_surface_create(double v,uint32_t cap){if(!std::isfinite(v)||v<0.005||v>0.1||cap<1||cap>500000)return nullptr;try{return new Surface(v,cap);}catch(...){return nullptr;}}
extern "C" void hx_surface_destroy(void*p){delete static_cast<Surface*>(p);}
extern "C" uint32_t hx_surface_dropped(void*p){return p?static_cast<Surface*>(p)->dropped:0;}
extern "C" int32_t hx_surface_integrate(void*p,const float*depth,const uint8_t*confidence,uint32_t w,uint32_t h,double fx,double fy,double cx,double cy,const double*m,uint32_t frame) try {
 if(!p||!depth||!m||w<3||h<3||uint64_t(w)*h>1000000||!std::isfinite(fx)||!std::isfinite(fy)||fx<0.1||fy<0.1||fx>1000000||fy>1000000||!std::isfinite(cx)||!std::isfinite(cy)||std::abs(cx)>1000000||std::abs(cy)>1000000||frame==UINT32_MAX)return -1;
 for(int i=0;i<16;i++)if(!std::isfinite(m[i]))return -1;
 Vec axisX={m[0],m[4],m[8]},axisY={m[1],m[5],m[9]},axisZ={m[2],m[6],m[10]};
 if(std::abs(dot(axisX,axisX)-1)>0.002||std::abs(dot(axisY,axisY)-1)>0.002||std::abs(dot(axisZ,axisZ)-1)>0.002||std::abs(dot(axisX,axisY))>0.001||std::abs(dot(cross(axisX,axisY),axisZ)-1)>0.001||std::abs(m[12])+std::abs(m[13])+std::abs(m[14])+std::abs(m[15]-1)>0.001)return -1;
 if(std::abs(m[3])+std::abs(m[7])+std::abs(m[11])>10000)return -1;
 auto&s=*static_cast<Surface*>(p);int32_t accepted=0;
 for(uint32_t y=1;y+1<h;y++)for(uint32_t x=1;x+1<w;x++){
  const size_t i=size_t(y)*w+x;double z=depth[i];if(!std::isfinite(z)||z<0.15||z>5||(confidence&&confidence[i]==0))continue;
  // Do not interpolate a depth discontinuity across foreground services.
  if(!std::isfinite(depth[i-1])||!std::isfinite(depth[i+1])||!std::isfinite(depth[i-w])||!std::isfinite(depth[i+w])||std::abs(z-depth[i-1])>0.08||std::abs(z-depth[i+1])>0.08||std::abs(z-depth[i-w])>0.08||std::abs(z-depth[i+w])>0.08)continue;
  for(double sample=z-s.band;sample<=z+s.band;sample+=s.voxel*0.7){
   Vec q=world((double(x)-cx)*sample/fx,(double(y)-cy)*sample/fy,sample,m);
   if(!std::isfinite(q.x)||!std::isfinite(q.y)||!std::isfinite(q.z)||std::abs(q.x)>10000||std::abs(q.y)>10000||std::abs(q.z)>10000)continue;
   Key key={int(std::floor(q.x/s.voxel)),int(std::floor(q.y/s.voxel)),int(std::floor(q.z/s.voxel))};
   auto it=s.cells.find(key);if(it!=s.cells.end()&&it->second.views&&frame<=it->second.last)continue;
   Vec center={(key.x+0.5)*s.voxel,(key.y+0.5)*s.voxel,(key.z+0.5)*s.voxel};Vec c=camera(center,m);if(c.z<=0.15)continue;
   double projectedX=fx*c.x/c.z+cx,projectedY=fy*c.y/c.z+cy;
   if(!std::isfinite(projectedX)||!std::isfinite(projectedY)||projectedX<1||projectedX>=w-1||projectedY<1||projectedY>=h-1)continue;
   int px=int(std::lround(projectedX)),py=int(std::lround(projectedY));if(px<1||px>=int(w)-1||py<1||py>=int(h)-1)continue;
   size_t j=size_t(py)*w+px;double measured=depth[j];if(!std::isfinite(measured)||measured<0.15||measured>5||(confidence&&confidence[j]==0))continue;
   double distance=measured-c.z;if(distance < -s.band||distance>s.band)continue;
   if(it==s.cells.end()){if(s.cells.size()>=s.capacity){s.dropped++;continue;}it=s.cells.emplace(key,Cell{}).first;}
   auto&cell=it->second;double weight=confidence&&confidence[j]==2?1:0.5;cell.value=(cell.value*cell.weight+distance*weight)/(cell.weight+weight);cell.weight=std::min(64.0,cell.weight+weight);cell.views++;cell.last=frame;accepted++;
  }
 }
 return accepted;
} catch(...){return -2;}
extern "C" uint32_t hx_surface_mesh(void*p,HXVertex*out,uint32_t cap,uint32_t minViews) try {
 if(!p||(!out&&cap))return 0;auto&s=*static_cast<Surface*>(p);uint32_t count=0;
 const int offsets[8][3]={{0,0,0},{1,0,0},{1,1,0},{0,1,0},{0,0,1},{1,0,1},{1,1,1},{0,1,1}};
 const int tetra[6][4]={{0,5,1,6},{0,1,2,6},{0,2,3,6},{0,3,7,6},{0,7,4,6},{0,4,5,6}};
 std::vector<Key> keys;keys.reserve(s.cells.size());for(auto&kv:s.cells)keys.push_back(kv.first);std::sort(keys.begin(),keys.end());
 for(auto key:keys){Vec vertices[8];double values[8];bool ready=true,positive=false,negative=false;
  for(int i=0;i<8;i++){Key k={key.x+offsets[i][0],key.y+offsets[i][1],key.z+offsets[i][2]};auto it=s.cells.find(k);if(it==s.cells.end()||it->second.views<minViews){ready=false;break;}values[i]=it->second.value;positive|=values[i]>0;negative|=values[i]<=0;vertices[i]={(k.x+0.5)*s.voxel,(k.y+0.5)*s.voxel,(k.z+0.5)*s.voxel};}
  if(!ready||!positive||!negative)continue;
  Vec gradient={(values[1]+values[2]+values[5]+values[6])-(values[0]+values[3]+values[4]+values[7]),(values[2]+values[3]+values[6]+values[7])-(values[0]+values[1]+values[4]+values[5]),(values[4]+values[5]+values[6]+values[7])-(values[0]+values[1]+values[2]+values[3])};
  for(auto&t:tetra){std::vector<Vec> polygon;
   for(int a=0;a<4;a++)for(int b=a+1;b<4;b++){int i=t[a],j=t[b];if((values[i]>0)==(values[j]>0))continue;double fraction=values[i]/(values[i]-values[j]);polygon.push_back(vertices[i]+(vertices[j]-vertices[i])*fraction);}
   if(polygon.size()<3)continue;
   Vec center={0,0,0};for(auto q:polygon)center=center+q;center=center*(1.0/polygon.size());Vec normal=cross(polygon[1]-polygon[0],polygon[2]-polygon[0]);if(dot(normal,normal)<1e-18)continue;if(dot(normal,gradient)<0)normal=normal*(-1);Vec u=polygon[0]-center,v=cross(normal,u);
   double ul=std::sqrt(dot(u,u)),vl=std::sqrt(dot(v,v));if(ul<1e-12||vl<1e-12)continue;u=u*(1/ul);v=v*(1/vl);
   std::sort(polygon.begin(),polygon.end(),[&](Vec a,Vec b){return std::atan2(dot(a-center,v),dot(a-center,u))<std::atan2(dot(b-center,v),dot(b-center,u));});
   for(size_t n=1;n+1<polygon.size();n++){Vec a=polygon[0],b=polygon[n],c=polygon[n+1];if(dot(cross(b-a,c-a),cross(b-a,c-a))<1e-18)continue;if(out&&count+3<=cap){out[count]={a.x,a.y,a.z};out[count+1]={b.x,b.y,b.z};out[count+2]={c.x,c.y,c.z};}count+=3;}
  }
 }
 return count;
} catch(...){return UINT32_MAX;}
