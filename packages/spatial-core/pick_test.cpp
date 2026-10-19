#include "hx_core.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <vector>

int main(){
 unsigned cases=0;double worst=0;
 // Independent expected intersections lie on an axis-aligned plane. Rotate
 // axes, reverse winding/ray direction, and vary scale and global offsets.
 for(double offset:{0.0,50000.0,-50000.0})for(double size:{1e-6,0.001,1.0,10000.0})
 for(int axis=0;axis<3;++axis)for(int side:{-1,1})for(bool reversed:{false,true}){
  std::array<double,9> vertices;vertices.fill(offset);
  vertices[3+(axis+1)%3]+=size;vertices[6+(axis+2)%3]+=size;
  const int32_t indices[]={0,reversed?2:1,reversed?1:2};
  std::array<double,3> a,b,target;target.fill(offset);
  target[(axis+1)%3]+=size*.25;target[(axis+2)%3]+=size*.25;
  a=target;b=target;a[axis]+=side*size;b[axis]-=side*size;
  double t=-1;assert(hx_pick_segment(vertices.data(),3,indices,3,a.data(),b.data(),&t)==1);
  double error=0;for(int i=0;i<3;++i)error=std::max(error,std::abs(a[i]+(b[i]-a[i])*t-target[i]));
  assert(std::abs(t-.5)<1e-9);assert(error<.000002);worst=std::max(worst,error);++cases;
  // Beyond the finite segment, outside the triangle, and a parallel segment.
  b=a;b[axis]+=side*size;assert(hx_pick_segment(vertices.data(),3,indices,3,a.data(),b.data(),&t)==0);++cases;
  a=target;b=target;a[(axis+1)%3]+=size;b[(axis+1)%3]+=size;a[axis]+=size;b[axis]-=size;
  assert(hx_pick_segment(vertices.data(),3,indices,3,a.data(),b.data(),&t)==0);++cases;
  b=a;b[(axis+1)%3]+=size;assert(hx_pick_segment(vertices.data(),3,indices,3,a.data(),b.data(),&t)==0);++cases;
 }
 const double vertices[]={0,0,0, 0,1,0, 0,0,1, .1,0,0, .1,1,0, .1,0,1};
 const int32_t indices[]={0,1,2,3,4,5};
 const double a[]={.2,.25,.25},b[]={-.2,.25,.25};double t=-1;
 assert(hx_pick_segment(vertices,6,indices,6,a,b,&t)==1&&std::abs(t-.25)<1e-12);++cases;
 const int32_t reverseFaces[]={3,4,5,0,1,2};
 assert(hx_pick_segment(vertices,6,reverseFaces,6,a,b,&t)==1&&std::abs(t-.25)<1e-12);++cases;
 const int32_t degenerate[]={0,0,1};assert(hx_pick_segment(vertices,6,degenerate,3,a,b,&t)==0);++cases;
 const int32_t invalid[]={0,1,2,3,4,6};t=-17;
 assert(hx_pick_segment(vertices,6,invalid,6,a,b,&t)==-1&&t==-17);++cases;
 const int32_t negative[]={0,-1,2};assert(hx_pick_segment(vertices,6,negative,3,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(vertices,6,indices,5,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(nullptr,6,indices,6,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(vertices,6,nullptr,6,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(vertices,400001,indices,6,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(vertices,6,indices,400002,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(vertices,6,indices,6,a,a,&t)==-1);++cases;
 double bad[]={std::numeric_limits<double>::quiet_NaN(),0,0};
 assert(hx_pick_segment(vertices,6,indices,6,bad,b,&t)==-1);++cases;
 double badVertices[]={0,0,0,0,1,0,0,0,std::numeric_limits<double>::infinity()};
 assert(hx_pick_segment(badVertices,3,indices,3,a,b,&t)==-1);++cases;
 assert(hx_pick_segment(nullptr,0,nullptr,0,a,b,&t)==0);++cases;
 // A bounded worst-residency query, not an iPhone performance claim.
 std::vector<int32_t> dense(399999);for(size_t i=0;i<dense.size();++i)dense[i]=int32_t(i%3);
 const auto started=std::chrono::steady_clock::now();
 assert(hx_pick_segment(vertices,6,dense.data(),uint32_t(dense.size()),a,b,&t)==1);++cases;
 const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
 std::cout<<"{\"suite\":\"production displayed-triangle segment query\",\"passed\":true,\"cases\":"<<cases
 <<",\"maximumErrorMetres\":"<<worst<<",\"residentTriangles\":133333,\"hostQueryMilliseconds\":"<<ms
 <<",\"physicalQualification\":false}\n";
}
