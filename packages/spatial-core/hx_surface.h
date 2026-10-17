#ifndef HX_SURFACE_H
#define HX_SURFACE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct HXVertex {double x,y,z;} HXVertex;
void* hx_surface_create(double voxel_metres,uint32_t capacity);
void hx_surface_destroy(void* context);
// Native AR camera transform is row-major; depth is optical-axis metres.
// All returned vertices use canonical right-handed Z-up metres.
int32_t hx_surface_integrate(void* context,const float* depth,const uint8_t* confidence,uint32_t width,uint32_t height,double fx,double fy,double cx,double cy,const double* camera,uint32_t frame);
uint32_t hx_surface_dropped(void* context);
// Output is an explicit triangle soup; count is a multiple of three.
// A result above capacity signals truncation and must never be published.
uint32_t hx_surface_mesh(void* context,HXVertex* output,uint32_t capacity,uint32_t min_views);
#ifdef __cplusplus
}
#endif
#endif
