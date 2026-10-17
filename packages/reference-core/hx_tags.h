#ifndef HX_TAGS_H
#define HX_TAGS_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// AprilTag 36h11 only. Image is the canonical 10x10 cells including white margin;
// the measurable black border spans eight cells. No metric pose is claimed here.
int32_t hx_tag_image(uint32_t id,uint8_t* output,uint32_t capacity);
// Full-resolution pixel coordinates, AprilTag corner order (-1,+1),(+1,+1),
// (+1,-1),(-1,-1) in the canonical tag plane. Zero corrected bits, bounded input,
// unique IDs and minimum edge/contrast gates. Negative return refuses the frame.
int32_t hx_tag_detect(const uint8_t* gray,uint32_t bytes,uint32_t width,uint32_t height,uint32_t stride,
                     uint32_t* ids,double* corners,double* margins,uint32_t capacity);
int32_t hx_tag_selftest(void);
#ifdef __cplusplus
}
#endif
#endif
