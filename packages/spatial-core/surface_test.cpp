#include "hx_surface.h"
#include <cassert>
#include <cmath>
#include <vector>
#include <iostream>
#include <cstring>
int main(){
 const int w=96,h=72;std::vector<float> depth(w*h);std::vector<uint8_t> confidence(w*h,2);double m[16]={1,0,0,0,0,1,0,1.4,0,0,1,0,0,0,0,1};
 void*p=hx_surface_create(.02,200000);assert(p);void*resumed=nullptr;
 for(int f=0;f<9;f++){m[3]=(f-4)*.04;for(int i=0;i<w*h;i++)depth[i]=float(2+std::sin(i*7+f*19)*.001);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,f)>0);
  if(f==3){uint32_t bytes=hx_surface_checkpoint(p,nullptr,0);assert(bytes>32);std::vector<uint8_t> data(bytes);assert(hx_surface_checkpoint(p,data.data(),bytes)==bytes);resumed=hx_surface_restore(data.data(),bytes);assert(resumed);assert(!hx_surface_restore(data.data(),bytes-1));data[0]^=1;assert(!hx_surface_restore(data.data(),bytes));}
  else if(f>3)assert(hx_surface_integrate(resumed,depth.data(),confidence.data(),w,h,65,65,48,36,m,f)>0);
 }
 uint32_t fullSize=hx_surface_checkpoint(p,nullptr,0);assert(hx_surface_checkpoint(resumed,nullptr,0)==fullSize);std::vector<uint8_t> full(fullSize),restored(fullSize);hx_surface_checkpoint(p,full.data(),fullSize);hx_surface_checkpoint(resumed,restored.data(),fullSize);assert(full==restored);hx_surface_destroy(resumed);
 assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,1e300,65,48,36,m,9)==-1);
 double invalid[16];std::copy(m,m+16,invalid);invalid[0]=2;assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,invalid,9)==-1);
 assert(hx_surface_dropped(p)==0);auto count=hx_surface_mesh(p,nullptr,0,3);assert(count>300&&count%3==0);std::vector<HXVertex> mesh(count);assert(hx_surface_mesh(p,mesh.data(),count,3)==count);double max=0;for(auto v:mesh){assert(std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z));max=std::fmax(max,std::abs(v.y-2));}assert(max<.003);
 assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,8)==0);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,0,65,48,36,m,9)==-1);hx_surface_destroy(p);
 p=hx_surface_create(.02,1);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,0)>0);assert(hx_surface_dropped(p)>0);hx_surface_destroy(p);
 // A one-metre foreground/background discontinuity must not become a bridge.
 p=hx_surface_create(.02,200000);m[3]=0;
 for(int f=0;f<4;f++){for(int y=0;y<h;y++)for(int x=0;x<w;x++)depth[y*w+x]=x<w/2?1.f:2.f;assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,f)>0);}
 auto edgeCount=hx_surface_mesh(p,nullptr,0,3);assert(edgeCount>300);std::vector<HXVertex> edge(edgeCount);hx_surface_mesh(p,edge.data(),edgeCount,3);for(auto v:edge)assert(std::fmin(std::abs(v.y-1),std::abs(v.y-2))<.003);hx_surface_destroy(p);
 std::cout<<"{\"passed\":true,\"checkpointResumeIdentical\":true,\"checkpointCorruptionRejected\":true,\"surface_vertices\":"<<count<<",\"max_plane_error_m\":"<<max<<",\"scope\":\"analytic noisy depth with known pose priors\"}\n";
}
