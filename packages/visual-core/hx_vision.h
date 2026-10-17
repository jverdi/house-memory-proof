#ifndef HX_VISION_H
#define HX_VISION_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// XY locations are normalized to input width/height; 32 descriptor bytes per point.
int32_t hx_vision_detect(const uint8_t* gray,uint32_t bytes,uint32_t width,uint32_t height,uint32_t stride,float* xy,uint8_t* descriptors,uint32_t capacity);
// Returns pairs (map index, query index) with ratio and reciprocal-match checks.
int32_t hx_vision_match(const uint8_t* map,uint32_t map_count,const uint8_t* query,uint32_t query_count,uint32_t* pairs,uint32_t capacity);
typedef struct HXPoseQuality {uint32_t inliers;double fraction;double rms_pixels;double p95_pixels;double condition;uint32_t rejection;} HXPoseQuality;
// Output maps native AR camera right/up/back into the supplied right-handed world.
// rejection: 0 accepted, 1 RANSAC, 2 inliers, 3 image coverage, 4 3D spread,
// 5 depth, 6 reprojection, 7 conditioning. Invalid arguments return <0.
// Diagnostic pose only: image residuals are not a physical accuracy certificate.
int32_t hx_vision_pose(const double* xyz,const double* xy,uint32_t count,double fx,double fy,double cx,double cy,uint32_t width,uint32_t height,double* world_from_ar_camera,HXPoseQuality* quality);
#ifdef __cplusplus
}
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Simulator diagnostics: 200 known-correspondence poses and 300 random mismatches.
int32_t hx_vision_selftest(double* max_position_error,uint32_t* false_accepts);
#ifdef __cplusplus
}
#endif

#endif
