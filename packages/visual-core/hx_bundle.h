#ifndef HX_BUNDLE_H
#define HX_BUNDLE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct HXBundleObservation {
 uint32_t camera,point,fit;
 double u,v,depth;
} HXBundleObservation;
typedef struct HXBundleQuality {
 double initial_check_rms,final_check_rms,fit_rms,depth_rms,seconds;
 uint32_t optimized_cameras,iterations;
} HXBundleQuality;
// Native AR camera-to-world matrices; points use the same world axes.
// Every point needs >=2 fitting views and >=1 held-out check view. Intrinsics
// are [fx,fy,cx,cy] per camera. No distortion model is inferred.
// 3..120 cameras, 20..2000 points, <=24000 observations; anchor camera zero.
int32_t hx_bundle_optimize(const double* cameras,uint32_t camera_count,
 const double* points,uint32_t point_count,const double* intrinsics,
 const HXBundleObservation* observations,uint32_t observation_count,
 double* output_cameras,double* output_points,HXBundleQuality* quality);
int32_t hx_bundle_selftest(double* maximum_error);
#ifdef __cplusplus
}
#endif
#endif
