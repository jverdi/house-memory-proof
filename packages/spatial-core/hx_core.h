#ifndef HX_CORE_H
#define HX_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct HXSample {double x,y,z;float weight;uint32_t frame;} HXSample;
typedef struct HXPoint {double x,y,z,spread;uint32_t views;} HXPoint;
void* hx_create(double voxel_metres,uint32_t capacity);
void hx_destroy(void* context);
// Returns accepted input samples, or -1 for invalid arguments. Capacity overflow
// is reported separately; it never silently purges prior evidence.
int32_t hx_add(void* context,const HXSample* samples,uint32_t count);
uint32_t hx_count(void* context,uint32_t min_views);
uint32_t hx_copy(void* context,HXPoint* output,uint32_t capacity,uint32_t min_views);
uint32_t hx_dropped(void* context);
#ifdef __cplusplus
}
#endif
#endif
