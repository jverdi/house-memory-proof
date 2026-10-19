#include "hx_core.h"
#include <cmath>
#include <unordered_map>
#include <algorithm>
#include <new>
#include <vector>
struct Key{int64_t x,y,z;bool operator==(const Key&b)const{return x==b.x&&y==b.y&&z==b.z;}};
struct Hash{size_t operator()(const Key&k)const{return std::hash<int64_t>()(k.x)^(std::hash<int64_t>()(k.y)<<1)^(std::hash<int64_t>()(k.z)<<2);}};
struct Cell{double x=0,y=0,z=0,w=0,m2=0;uint32_t views=0,last=UINT32_MAX;};
struct Core{double voxel;uint32_t capacity,dropped=0;std::unordered_map<Key,Cell,Hash> cells;Core(double v,uint32_t n):voxel(v),capacity(n){cells.reserve(std::min(n,100000u));}};
extern "C" void* hx_create(double v,uint32_t n){if(!std::isfinite(v)||v<0.002||v>0.5||n==0||n>500000)return nullptr;try{return new Core(v,n);}catch(...){return nullptr;}}
extern "C" void hx_destroy(void*p){delete static_cast<Core*>(p);}
extern "C" int32_t hx_add(void*p,const HXSample*s,uint32_t n){if(!p||(!s&&n)||n>1000000)return -1;auto&c=*static_cast<Core*>(p);int32_t accepted=0;for(uint32_t i=0;i<n;++i){auto&a=s[i];if(!std::isfinite(a.x)||!std::isfinite(a.y)||!std::isfinite(a.z)||std::abs(a.x)>10000||std::abs(a.y)>10000||std::abs(a.z)>10000||!std::isfinite(a.weight)||a.weight<=0||a.weight>1||a.frame==UINT32_MAX)continue;Key k{int64_t(std::floor(a.x/c.voxel)),int64_t(std::floor(a.y/c.voxel)),int64_t(std::floor(a.z/c.voxel))};auto it=c.cells.find(k);if(it==c.cells.end()){if(c.cells.size()>=c.capacity){++c.dropped;continue;}it=c.cells.emplace(k,Cell{}).first;}auto&v=it->second;if(v.views && a.frame<=v.last)continue;const double old=v.w,w=old+a.weight,dx=a.x-v.x,dy=a.y-v.y,dz=a.z-v.z;v.x+=dx*a.weight/w;v.y+=dy*a.weight/w;v.z+=dz*a.weight/w;v.m2+=a.weight*old/w*(dx*dx+dy*dy+dz*dz);v.w=w;++v.views;v.last=a.frame;++accepted;}return accepted;}
extern "C" uint32_t hx_count(void*p,uint32_t min){if(!p)return 0;uint32_t n=0;for(auto&kv:static_cast<Core*>(p)->cells)if(kv.second.views>=min)++n;return n;}
extern "C" uint32_t hx_copy(void*p,HXPoint*out,uint32_t cap,uint32_t min){if(!p||(!out&&cap))return 0;auto&c=*static_cast<Core*>(p);std::vector<std::pair<Key,Cell>> sorted;for(auto&kv:c.cells)if(kv.second.views>=min)sorted.push_back(kv);std::sort(sorted.begin(),sorted.end(),[](auto&a,auto&b){if(a.first.x!=b.first.x)return a.first.x<b.first.x;if(a.first.y!=b.first.y)return a.first.y<b.first.y;return a.first.z<b.first.z;});uint32_t n=0;for(auto&kv:sorted){if(n>=cap)break;auto&v=kv.second;out[n++]={v.x,v.y,v.z,std::sqrt(std::max(0.0,v.m2/v.w)),v.views};}return n;}
extern "C" uint32_t hx_dropped(void*p){return p?static_cast<Core*>(p)->dropped:0;}

namespace {
struct PickVector {
 double x,y,z;
 PickVector operator-(const PickVector& b)const{return {x-b.x,y-b.y,z-b.z};}
 PickVector operator*(double s)const{return {x*s,y*s,z*s};}
 double dot(const PickVector& b)const{return x*b.x+y*b.y+z*b.z;}
 PickVector cross(const PickVector& b)const{return {y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x};}
 bool finite()const{return std::isfinite(x)&&std::isfinite(y)&&std::isfinite(z);}
};
PickVector pick_vector(const double* p){return {p[0],p[1],p[2]};}
}
extern "C" int32_t hx_pick_segment(const double* xyz,uint32_t vertices,
 const int32_t* indices,uint32_t count,const double* start,const double* end,double* fraction){
 if(!start||!end||!fraction||vertices>400000||count>400000||count%3||
    (!xyz&&vertices)||(!indices&&count))return -1;
 const auto origin=pick_vector(start),finish=pick_vector(end),delta=finish-origin;
 const double length=std::sqrt(delta.dot(delta));
 if(!origin.finite()||!finish.finite()||!std::isfinite(length)||length<=0)return -1;
 // Validate before searching: a malformed late face cannot hide behind a hit.
 for(uint32_t i=0;i<vertices;++i)if(!pick_vector(xyz+3*i).finite())return -1;
 for(uint32_t i=0;i<count;++i)if(indices[i]<0||uint32_t(indices[i])>=vertices)return -1;
 const auto direction=delta*(1/length);
 double nearest=length;bool found=false;
 for(uint32_t face=0;face<count;face+=3){
  const auto a=pick_vector(xyz+3*indices[face]);
  const auto ab=pick_vector(xyz+3*indices[face+1])-a;
  const auto ac=pick_vector(xyz+3*indices[face+2])-a;
  const auto cross=direction.cross(ac);
  const double determinant=ab.dot(cross);
  const double scale=std::sqrt(ab.dot(ab))*std::sqrt(ac.dot(ac));
  // Relative parallelism threshold, independent of triangle size. An absolute
  // area epsilon would discard visible millimetre-scale source surfaces.
  if(!std::isfinite(scale)||scale==0||std::abs(determinant)<=scale*1e-12)continue;
  const auto offset=origin-a;
  const double u=offset.dot(cross)/determinant;
  if(u<0||u>1)continue;
  const auto q=offset.cross(ab);
  const double v=direction.dot(q)/determinant;
  if(v<0||u+v>1)continue;
  const double distance=ac.dot(q)/determinant;
  if(std::isfinite(distance)&&distance>=0&&distance<=nearest){nearest=distance;found=true;}
 }
 if(!found)return 0;
 *fraction=nearest/length;return 1;
}
