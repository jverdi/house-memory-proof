#include "hx_surface.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <cstdint>
// Binary stdin only. The process never receives a path to evaluator truth.
int main(){char magic[4];uint32_t frames=0;std::cin.read(magic,4);std::cin.read(reinterpret_cast<char*>(&frames),4);if(std::memcmp(magic,"HXS1",4)||frames<1||frames>300)return 2;
 void* core=hx_surface_create(.02,400000);if(!core)return 2;
 for(uint32_t frame=0;frame<frames;frame++){uint32_t w,h;double k[4],m[16];std::cin.read(reinterpret_cast<char*>(&w),4);std::cin.read(reinterpret_cast<char*>(&h),4);std::cin.read(reinterpret_cast<char*>(k),sizeof(k));std::cin.read(reinterpret_cast<char*>(m),sizeof(m));if(w<3||h<3||w>512||h>512){hx_surface_destroy(core);return 2;}
  std::vector<float> depth(size_t(w)*h);std::vector<uint8_t> confidence(size_t(w)*h);std::cin.read(reinterpret_cast<char*>(depth.data()),depth.size()*4);std::cin.read(reinterpret_cast<char*>(confidence.data()),confidence.size());if(!std::cin||hx_surface_integrate(core,depth.data(),confidence.data(),w,h,k[0],k[1],k[2],k[3],m,frame)<0||hx_surface_dropped(core)){hx_surface_destroy(core);return 3;}}
 uint32_t count=hx_surface_mesh(core,nullptr,0,3);if(!count||count>500000){hx_surface_destroy(core);return 4;}std::vector<HXVertex> vertices(count);if(hx_surface_mesh(core,vertices.data(),count,3)!=count){hx_surface_destroy(core);return 4;}hx_surface_destroy(core);
 static_assert(sizeof(HXVertex)==24,"Expected three packed doubles");std::cout.write(reinterpret_cast<char*>(&count),4);std::cout.write(reinterpret_cast<char*>(vertices.data()),vertices.size()*sizeof(HXVertex));return std::cout?0:5;
}
