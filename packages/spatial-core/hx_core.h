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
// Two-sided closest intersection with the displayed triangle mesh. Coordinates
// are packed xyz doubles in a node-local frame. Returns 1 (hit), 0 (miss), or
// -1 (invalid input); fraction is written only for a hit. No allocation or
// source mutation. Limits match the existing 400,000-element display budget.
int32_t hx_pick_segment(const double* xyz,uint32_t vertex_count,
 const int32_t* indices,uint32_t index_count,const double* start,
 const double* end,double* fraction);
#ifdef __cplusplus
}
#endif
#endif
