#ifndef HX_GRAPH_H
#define HX_GRAPH_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Metric RGB-D correspondence fit. Output is target-camera-from-source-camera.
int32_t hx_depth_transform(const double* source,const double* target,uint32_t count,double* transform,double* rms);
typedef struct HXGraphEdge {uint32_t a,b;double a_from_b[16];} HXGraphEdge;
// Local bounded pose graph, anchored at node zero. Inputs/outputs are native AR
// camera-to-world rigid transforms. Returns zero for disconnected/conflicting data.
int32_t hx_graph_optimize(const double* priors,uint32_t nodes,const HXGraphEdge* edges,uint32_t edge_count,double* output,double* maximum_residual);
int32_t hx_graph_selftest(double* maximum_error);
#ifdef __cplusplus
}
#endif
#endif
