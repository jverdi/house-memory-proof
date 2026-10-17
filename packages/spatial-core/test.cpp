#include "hx_core.h"
#include <cassert>
#include <cmath>
int main(){assert(!hx_create(0,10));assert(!hx_create(.02,0));auto*c=hx_create(.02,2);HXSample s{.005,.005,.005,1,0};for(int i=0;i<20;i++)hx_add(c,&s,1);assert(hx_count(c,2)==0);s.frame=1;hx_add(c,&s,1);s.frame=2;hx_add(c,&s,1);assert(hx_count(c,3)==1);HXPoint p;assert(hx_copy(c,&p,1,3)==1);assert(p.views==3&&std::abs(p.x-.005)<1e-12&&p.spread<1e-9);s.x=NAN;assert(hx_add(c,&s,1)==0);s.x=1;hx_add(c,&s,1);s.x=2;hx_add(c,&s,1);assert(hx_dropped(c)==1);hx_destroy(c);}
