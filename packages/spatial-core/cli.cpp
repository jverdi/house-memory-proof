#include "hx_core.h"
#include <iostream>
#include <vector>
int main(){auto*c=hx_create(0.02,100000);if(!c)return 2;HXSample s;while(std::cin>>s.x>>s.y>>s.z>>s.weight>>s.frame){if(hx_add(c,&s,1)<0)return 3;}std::vector<HXPoint>p(hx_count(c,3));hx_copy(c,p.data(),uint32_t(p.size()),3);std::cout.precision(12);for(auto&a:p)std::cout<<a.x<<' '<<a.y<<' '<<a.z<<' '<<a.spread<<' '<<a.views<<'\n';if(hx_dropped(c))std::cerr<<"capacity_exceeded="<<hx_dropped(c)<<'\n';hx_destroy(c);return 0;}
