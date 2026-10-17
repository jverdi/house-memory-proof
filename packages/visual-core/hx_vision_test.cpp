#include "hx_vision.h"
#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <cmath>
#include <algorithm>
#include <cstring>
#include <vector>
extern "C" int32_t hx_vision_selftest(double* maximum,uint32_t* falseAccepts) try {
 if(!maximum||!falseAccepts)return -1;*maximum=0;*falseAccepts=0;
 cv::RNG random(0x48584a52);const uint32_t w=640,h=480,n=144;std::vector<double> world(n*3),pixels(n*2);double pose[16];HXPoseQuality quality{};
 for(int trial=0;trial<200;trial++){
  cv::Mat angle=(cv::Mat_<double>(3,1)<<random.uniform(-.3,.3),random.uniform(-.3,.3),random.uniform(-.3,.3)),R;cv::Rodrigues(angle,R);
  cv::Vec3d position(random.uniform(-3.,3.),random.uniform(-3.,3.),random.uniform(-1.,1.));
  for(uint32_t i=0;i<n;i++){
   cv::Vec3d p(-1.2+(i%12)*2.4/11,-.9+(i/12)*1.8/11,2.5+(i%3)*.6);
   for(int row=0;row<3;row++)world[i*3+row]=R.at<double>(row,0)*p[0]+R.at<double>(row,1)*p[1]+R.at<double>(row,2)*p[2]+position[row];
   pixels[i*2]=500*p[0]/p[2]+320+random.gaussian(.25);pixels[i*2+1]=500*p[1]/p[2]+240+random.gaussian(.25);
   if(i%5==0){pixels[i*2]=random.uniform(0.,640.);pixels[i*2+1]=random.uniform(0.,480.);}
  }
  if(hx_vision_pose(world.data(),pixels.data(),n,500,500,320,240,w,h,pose,&quality)!=1)return -10;
  double error=0;for(int row=0;row<3;row++)error+=std::pow(pose[row*4+3]-position[row],2);
  *maximum=std::max(*maximum,std::sqrt(error));if(*maximum>.02)return -11;
  for(int row=0;row<3;row++)for(int col=0;col<3;col++)if(std::abs(pose[row*4+col]-R.at<double>(row,col)*(col==0?1:-1))>.015)return -12;
  // The same image/map must remain admissible when registered on another
  // floor or far from the chosen house origin. No thresholds are relaxed.
  if(trial%20==0){auto shifted=world;double offset[3]={80,-60,12};for(uint32_t i=0;i<n;i++)for(int axis=0;axis<3;axis++)shifted[i*3+axis]+=offset[axis];double moved[16];HXPoseQuality checked{};
   if(hx_vision_pose(shifted.data(),pixels.data(),n,500,500,320,240,w,h,moved,&checked)!=1)return -17;
   for(int axis=0;axis<3;axis++)if(std::abs(moved[axis*4+3]-offset[axis]-pose[axis*4+3])>1e-5)return -18;
  }
 }
 for(int trial=0;trial<300;trial++){
  for(uint32_t i=0;i<n;i++){pixels[i*2]=random.uniform(0.,640.);pixels[i*2+1]=random.uniform(0.,480.);}
  if(hx_vision_pose(world.data(),pixels.data(),n,500,500,320,240,w,h,pose,&quality)==1)(*falseAccepts)++;
 }
 if(*falseAccepts)return -13;
 for(uint32_t i=0;i<n;i++){double x=-1.2+(i%12)*2.4/11,y=-.9+(i/12)*1.8/11;world[i*3]=x;world[i*3+1]=y;world[i*3+2]=3;pixels[i*2]=500*x/3+320;pixels[i*2+1]=500*y/3+240;}
 if(hx_vision_pose(world.data(),pixels.data(),n,500,500,320,240,w,h,pose,&quality)!=0)return -14;
 std::vector<uint8_t> gray(w*h),desc(1200*32),again(1200*32);std::vector<float> xy(2400),other(2400);std::vector<uint32_t> pairs(2400);
 for(auto& value:gray)value=uint8_t(random.uniform(0,256));
 int count=hx_vision_detect(gray.data(),uint32_t(gray.size()),w,h,w,xy.data(),desc.data(),1200);
 int repeat=hx_vision_detect(gray.data(),uint32_t(gray.size()),w,h,w,other.data(),again.data(),1200);
 if(count<100||count!=repeat||std::memcmp(desc.data(),again.data(),count*32)||std::memcmp(xy.data(),other.data(),count*2*sizeof(float)))return -15;
 if(hx_vision_match(desc.data(),count,again.data(),repeat,pairs.data(),1200)!=count)return -16;
 return 1;
} catch(...){return -2;}
