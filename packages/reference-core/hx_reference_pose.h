#ifndef HX_REFERENCE_POSE_H
#define HX_REFERENCE_POSE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {uint32_t boards,rejection;double rms_pixels,maximum_check_pixels,maximum_leave_out_shift_metres,condition;} HXReferenceQuality;
// Four to sixteen uniquely identified, fixed boards. Four ordered 3D/pixel
// corners per board; all points remain fitting/check evidence, never an oracle.
// Returns world-from-native-AR-camera, matching the visual core convention.
int32_t hx_reference_pose(const double* corners_xyz,const double* corners_xy,const uint32_t* ids,uint32_t boards,
                         double fx,double fy,double cx,double cy,uint32_t width,uint32_t height,
                         double* pose,HXReferenceQuality* quality);
int32_t hx_reference_selftest(double* maximum_position_error);
typedef struct {double rms_pixels,alternative_pixels;uint32_t rejection;} HXTagPoseQuality;
// Measure a known square directly from detected pixels. Output is native
// AR-camera-from-image-anchor (local X right, Y outward normal, Z image down).
int32_t hx_reference_measure_tag(const double* corners_xy,double border_width,double fx,double fy,double cx,double cy,
                                uint32_t width,uint32_t height,double* pose,HXTagPoseQuality* quality);
typedef struct {double rms_pixels,maximum_pixels;uint32_t views,rejection;} HXBoardFitQuality;
// Fit one rigid, measured square to 2..64 translated source views. Cameras and
// output use native AR axes, row-major world-from-local transforms. Each view
// supplies fx/fy/cx/cy/width/height and eight pixel coordinates. Cameras stay
// fixed: this is not a camera-drift calibration or a physical error bound.
int32_t hx_reference_refine_board(const double* cameras,const double* calibration,const double* corners_xy,
                                 uint32_t views,double border_width,const double* initial_pose,
                                 double* pose,HXBoardFitQuality* quality);
#ifdef __cplusplus
}
#endif
#endif
