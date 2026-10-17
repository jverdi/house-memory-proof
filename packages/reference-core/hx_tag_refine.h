#ifndef HX_TAG_REFINE_H
#define HX_TAG_REFINE_H
// Bounded photometric refinement of an already decoded tag. Internal cell
// transitions constrain the same projective square as the outside border.
// No pose, camera prior, query label or metric truth enters this operation.
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
typedef struct {double u,v,level;} HXTagEdge;
typedef struct {float* pixels;int x,y,w,h;} HXTagPatch;
static int hx_tag_linear(double a[8][8],double b[8],double x[8]) {
  for(int col=0;col<8;col++) {
    int pivot=col;for(int row=col+1;row<8;row++)if(fabs(a[row][col])>fabs(a[pivot][col]))pivot=row;
    if(!isfinite(a[pivot][col])||fabs(a[pivot][col])<1e-12)return 0;
    if(pivot!=col){for(int j=col;j<8;j++){double t=a[col][j];a[col][j]=a[pivot][j];a[pivot][j]=t;}double t=b[col];b[col]=b[pivot];b[pivot]=t;}
    for(int row=col+1;row<8;row++) {double f=a[row][col]/a[col][col];for(int j=col;j<8;j++)a[row][j]-=f*a[col][j];b[row]-=f*b[col];}
  }
  for(int row=7;row>=0;row--){double v=b[row];for(int col=row+1;col<8;col++)v-=a[row][col]*x[col];x[row]=v/a[row][row];if(!isfinite(x[row]))return 0;}return 1;
}
static int hx_tag_project(const double h[8],double u,double v,double* x,double* y) {
  double d=h[6]*u+h[7]*v+1;if(!isfinite(d)||d<.2)return 0;
  *x=(h[0]*u+h[1]*v+h[2])/d;*y=(h[3]*u+h[4]*v+h[5])/d;return isfinite(*x)&&isfinite(*y);
}
static int hx_tag_sample(const HXTagPatch* p,double x,double y,double* value,double* gx,double* gy) {
  x-=p->x;y-=p->y;
  // Reject diverged trial projections before converting to integer indices.
  if(!isfinite(x)||!isfinite(y)||x<0||y<0||x>=p->w-1||y>=p->h-1)return 0;
  int ix=(int)floor(x),iy=(int)floor(y);
  double a=x-ix,b=y-iy,p00=p->pixels[iy*p->w+ix],p10=p->pixels[iy*p->w+ix+1],p01=p->pixels[(iy+1)*p->w+ix],p11=p->pixels[(iy+1)*p->w+ix+1];
  *value=(1-a)*(1-b)*p00+a*(1-b)*p10+(1-a)*b*p01+a*b*p11;
  *gx=(1-b)*(p10-p00)+b*(p11-p01);*gy=(1-a)*(p01-p00)+a*(p11-p10);return 1;
}
static double hx_tag_objective(const HXTagPatch* patch,const HXTagEdge* edges,int count,const double h[8],double cx,double cy,double scale,double normal[8][8],double rhs[8]) {
  if(normal){memset(normal,0,64*sizeof(double));memset(rhs,0,8*sizeof(double));}
  double cost=0;
  for(int i=0;i<count;i++) {
    double u=edges[i].u,v=edges[i].v,x,y,value,gx,gy;
    if(!hx_tag_project(h,u,v,&x,&y)||!hx_tag_sample(patch,x*scale+cx,y*scale+cy,&value,&gx,&gy))return INFINITY;
    double r=(value-edges[i].level)/255;cost+=r*r;
    if(normal) {
      double d=1+h[6]*u+h[7]*v,dx=gx*scale/(255*d),dy=gy*scale/(255*d);
      double j[8]={dx*u,dx*v,dx,dy*u,dy*v,dy,-(dx*x+dy*y)*u,-(dx*x+dy*y)*v};
      for(int a=0;a<8;a++){rhs[a]-=j[a]*r;for(int b=0;b<8;b++)normal[a][b]+=j[a]*j[b];}
    }
  }
  return cost;
}
static int hx_tag_refine(const uint8_t* image,int width,int height,int stride,const uint8_t cells[100],double corners[4][2]) {
  double cx=0,cy=0,scale=0,loX=width,loY=height,hiX=0,hiY=0;
  for(int i=0;i<4;i++){cx+=corners[i][0]-.5;cy+=corners[i][1]-.5;loX=fmin(loX,corners[i][0]);loY=fmin(loY,corners[i][1]);hiX=fmax(hiX,corners[i][0]);hiY=fmax(hiY,corners[i][1]);}cx/=4;cy/=4;
  for(int i=0;i<4;i++)scale+=pow(corners[i][0]-.5-cx,2)+pow(corners[i][1]-.5-cy,2);scale=sqrt(scale/4);
  if(scale<12||!isfinite(scale))return 0;
  const double uv[4][2]={{-1,1},{1,1},{1,-1},{-1,-1}};
  double a[8][8]={{0}},b[8],h[8]={0};
  for(int i=0;i<4;i++) {double u=uv[i][0],v=uv[i][1],x=(corners[i][0]-.5-cx)/scale,y=(corners[i][1]-.5-cy)/scale;
    a[2*i][0]=u;a[2*i][1]=v;a[2*i][2]=1;a[2*i][6]=-u*x;a[2*i][7]=-v*x;b[2*i]=x;
    a[2*i+1][3]=u;a[2*i+1][4]=v;a[2*i+1][5]=1;a[2*i+1][6]=-u*y;a[2*i+1][7]=-v*y;b[2*i+1]=y;
  }
  if(!hx_tag_linear(a,b,h))return 0;
  double padding=ceil(scale*.2)+4;
  HXTagPatch patch={0};patch.x=(int)fmax(2,floor(loX)-padding);patch.y=(int)fmax(2,floor(loY)-padding);
  patch.w=(int)fmin(width-3,ceil(hiX)+padding)-patch.x+1;patch.h=(int)fmin(height-3,ceil(hiY)+padding)-patch.y+1;
  if(patch.w<8||patch.h<8||(size_t)patch.w*patch.h>262144)return 0;
  patch.pixels=malloc((size_t)patch.w*patch.h*sizeof(float));if(!patch.pixels)return 0;
  // Gaussian sigma 0.7, radius 2. Pixel centres are integer coordinates here;
  // AprilTag's half-pixel convention is converted only inside this adapter.
  const double k[5]={.0096200568,.2054236973,.5699124918,.2054236973,.0096200568};
  for(int y=0;y<patch.h;y++)for(int x=0;x<patch.w;x++) {double sum=0;for(int j=-2;j<=2;j++)for(int i=-2;i<=2;i++)sum+=k[j+2]*k[i+2]*image[(y+patch.y+j)*stride+x+patch.x+i];patch.pixels[y*patch.w+x]=(float)sum;}
  double levels[100];int usable=1;
  for(int y=0;y<10;y++)for(int x=0;x<10;x++) {double px,py,gx,gy;
    // Only the inner 8x8 code/border needs cell intensities. Exterior white
    // uses adjacent quiet-margin samples, still bounded by the patch.
    if(!hx_tag_project(h,(x+.5-5)/4,(y+.5-5)/4,&px,&py)||!hx_tag_sample(&patch,px*scale+cx,py*scale+cy,&levels[y*10+x],&gx,&gy))levels[y*10+x]=NAN;
  }
  HXTagEdge edges[540];int count=0;
  for(int axis=0;axis<2;axis++)for(int y=0;y<10;y++)for(int x=1;x<10;x++) {
    int first=axis ? (x-1)*10+y:y*10+x-1,second=axis ? x*10+y:y*10+x;
    if(cells[first]==cells[second])continue;
    double l=levels[first],r=levels[second];
    if(!isfinite(l)||!isfinite(r)||((cells[second]>cells[first]) ? r-l:l-r)<40){usable=0;break;}
    for(int f=1;f<=3;f++) {double along=y+f*.25;edges[count++]=(HXTagEdge){( (axis?along:x)-5)/4,((axis?x:along)-5)/4,(l+r)/2};}
  }
  if(!usable||count<40){free(patch.pixels);return 0;}
  double original=hx_tag_objective(&patch,edges,count,h,cx,cy,scale,NULL,NULL),cost=original,damping=1e-3;
  for(int iteration=0;iteration<20;iteration++) {
    double normal[8][8],rhs[8],step[8]={0},next[8];
    hx_tag_objective(&patch,edges,count,h,cx,cy,scale,normal,rhs);
    for(int j=0;j<8;j++)normal[j][j]+=damping*fmax(normal[j][j],1e-6);
    if(!hx_tag_linear(normal,rhs,step))break;
    for(int j=0;j<8;j++)next[j]=h[j]+step[j];
    double candidate=hx_tag_objective(&patch,edges,count,next,cx,cy,scale,NULL,NULL);
    if(candidate<cost){double improvement=cost-candidate;memcpy(h,next,sizeof(h));cost=candidate;damping=fmax(1e-7,damping*.3);if(improvement<1e-9)break;}
    else damping*=10;
  }
  free(patch.pixels);
  if(!isfinite(cost)||cost>=original||sqrt(cost/count)>.2)return 0;
  double refined[4][2];
  for(int i=0;i<4;i++) {
    if(!hx_tag_project(h,uv[i][0],uv[i][1],&refined[i][0],&refined[i][1]))return 0;
    refined[i][0]=refined[i][0]*scale+cx+.5;refined[i][1]=refined[i][1]*scale+cy+.5;
    if(refined[i][0]<2||refined[i][1]<2||refined[i][0]>=width-2||refined[i][1]>=height-2||hypot(refined[i][0]-corners[i][0],refined[i][1]-corners[i][1])>2)return 0;
  }
  memcpy(corners,refined,sizeof(refined));return 1;
}
#endif
