#include "hx_tags.h"
#include <apriltag/apriltag.h>
#include <apriltag/tag36h11.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

int32_t hx_tag_image(uint32_t id,uint8_t* output,uint32_t capacity) {
  if(!output||capacity<100||id>=587)return -1;
  apriltag_family_t* family=tag36h11_create();if(!family)return -2;
  image_u8_t* image=apriltag_to_image(family,id);int32_t status=-2;
  if(image&&image->width==10&&image->height==10&&family->width_at_border==8){
    for(int y=0;y<10;y++)memcpy(output+y*10,image->buf+y*image->stride,10);
    status=10;
  }
  if(image)image_u8_destroy(image);tag36h11_destroy(family);return status;
}
int32_t hx_tag_detect(const uint8_t* gray,uint32_t bytes,uint32_t width,uint32_t height,uint32_t stride,
                     uint32_t* ids,double* corners,double* margins,uint32_t capacity) {
  if(!gray||!ids||!corners||!margins||width<64||height<64||width>4096||height>4096||stride<width||
     (uint64_t)stride*height>bytes||capacity<1||capacity>64)return -1;
  apriltag_family_t* family=tag36h11_create();if(!family)return -2;
  apriltag_detector_t* detector=apriltag_detector_create();
  if(!detector){tag36h11_destroy(family);return -2;}
  detector->nthreads=1;detector->quad_decimate=1;detector->quad_sigma=0;detector->refine_edges=true;
  apriltag_detector_add_family_bits(detector,family,0);
  image_u8_t image={.width=(int)width,.height=(int)height,.stride=(int)stride,.buf=(uint8_t*)gray};
  zarray_t* found=apriltag_detector_detect(detector,&image);int32_t count=0;
  for(int i=0;i<zarray_size(found);i++) {
    apriltag_detection_t* d;zarray_get(found,i,&d);
    if(d->hamming!=0||!isfinite(d->decision_margin)||d->decision_margin<30)continue;
    int valid=1;
    for(int j=0;j<4;j++) {
      double x=d->p[j][0],y=d->p[j][1],dx=x-d->p[(j+1)%4][0],dy=y-d->p[(j+1)%4][1];
      if(!isfinite(x)||!isfinite(y)||x<2||y<2||x>=width-2||y>=height-2||hypot(dx,dy)<24)valid=0;
    }
    if(!valid)continue;
    if((uint32_t)count>=capacity){count=-3;break;}
    for(int prior=0;prior<count;prior++)if(ids[prior]==(uint32_t)d->id){count=-4;break;}
    if(count<0)break;
    ids[count]=(uint32_t)d->id;margins[count]=d->decision_margin;
    for(int j=0;j<4;j++){corners[count*8+j*2]=d->p[j][0];corners[count*8+j*2+1]=d->p[j][1];}
    count++;
  }
  apriltag_detections_destroy(found);apriltag_detector_destroy(detector);tag36h11_destroy(family);return count;
}
int32_t hx_tag_selftest(void) {
  const int width=640,height=480;uint8_t* image=malloc(width*height);if(!image)return -1;
  uint8_t cells[100];uint32_t ids[8];double xy[64],margin[8];int32_t result=1;
  for(int rotation=0;rotation<4;rotation++) {
    memset(image,235,width*height);
    if(hx_tag_image(17,cells,100)!=10){result=-2;break;}
    for(int y=0;y<160;y++)for(int x=0;x<160;x++) {
      int u=x/16,v=y/16;
      for(int r=0;r<rotation;r++){int old=u;u=v;v=9-old;}
      image[(y+140)*width+x+240]=cells[v*10+u]?235:20;
    }
    int count=hx_tag_detect(image,width*height,width,height,width,ids,xy,margin,8);
    if(count!=1||ids[0]!=17){result=-3;break;}
    // Known raster edge, independently specified; corners must remain in the
    // original pixel frame, including under quarter-turn rotations.
    for(int j=0;j<4;j++) {
      double x=xy[j*2],y=xy[j*2+1];
      if(fmin(fabs(x-256),fabs(x-384))>1||fmin(fabs(y-156),fabs(y-284))>1)result=-4;
    }
  }
  if(result==1) {
    // A duplicated physical identity must refuse the complete frame.
    memset(image,255,width*height);
    for(int copy=0;copy<2;copy++)for(int y=0;y<100;y++)for(int x=0;x<100;x++)image[(y+160)*width+x+80+copy*300]=cells[(y/10)*10+x/10];
    if(hx_tag_detect(image,width*height,width,height,width,ids,xy,margin,8)!=-4)result=-5;
    memset(image,255,width*height);
    if(hx_tag_detect(image,width*height,width,height,width,ids,xy,margin,8)!=0)result=-6;
    if(hx_tag_image(587,cells,100)!=-1||hx_tag_detect(image,10,width,height,width,ids,xy,margin,8)!=-1)result=-7;
  }
  free(image);return result;
}
#ifdef HX_TAG_TEST_MAIN
#include <stdio.h>
int main(void){int status=hx_tag_selftest();printf("{\"suite\":\"pinned AprilTag detector and raster coordinates\",\"status\":%d,\"passed\":%s,\"fieldQualified\":false}\n",status,status==1?"true":"false");return status==1?0:1;}
#endif
