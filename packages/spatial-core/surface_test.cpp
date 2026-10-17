#include "hx_surface.h"
#include <cassert>
#include <cmath>
#include <vector>
#include <iostream>
int main(){
 const int w=96,h=72;std::vector<float> depth(w*h);std::vector<uint8_t> confidence(w*h,2);double m[16]={1,0,0,0,0,1,0,1.4,0,0,1,0,0,0,0,1};
 void*p=hx_surface_create(.02,200000);assert(p);
 for(int f=0;f<9;f++){m[3]=(f-4)*.04;for(int i=0;i<w*h;i++)depth[i]=float(2+std::sin(i*7+f*19)*.001);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,f)>0);}
 assert(hx_surface_dropped(p)==0);auto count=hx_surface_mesh(p,nullptr,0,3);assert(count>300&&count%3==0);std::vector<HXVertex> mesh(count);assert(hx_surface_mesh(p,mesh.data(),count,3)==count);double max=0;for(auto v:mesh){assert(std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z));max=std::fmax(max,std::abs(v.y-2));}assert(max<.003);
 assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,8)==0);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,0,65,48,36,m,9)==-1);hx_surface_destroy(p);
 p=hx_surface_create(.02,1);assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,0)>0);assert(hx_surface_dropped(p)>0);hx_surface_destroy(p);
 // A one-metre foreground/background discontinuity must not become a bridge.
 p=hx_surface_create(.02,200000);m[3]=0;
 for(int f=0;f<4;f++){for(int y=0;y<h;y++)for(int x=0;x<w;x++)depth[y*w+x]=x<w/2?1.f:2.f;assert(hx_surface_integrate(p,depth.data(),confidence.data(),w,h,65,65,48,36,m,f)>0);}
 auto edgeCount=hx_surface_mesh(p,nullptr,0,3);assert(edgeCount>300);std::vector<HXVertex> edge(edgeCount);hx_surface_mesh(p,edge.data(),edgeCount,3);for(auto v:edge)assert(std::fmin(std::abs(v.y-1),std::abs(v.y-2))<.003);hx_surface_destroy(p);
 std::cout<<"{\"passed\":true,\"surface_vertices\":"<<count<<",\"max_plane_error_m\":"<<max<<",\"scope\":\"analytic noisy depth with known pose priors\"}\n";
}
