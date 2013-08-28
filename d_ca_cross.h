#ifndef D_CA_CROSS_H
#define D_CA_CROSS_H
#include <stdio.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>

void ca_cross(unsigned int* img_l, unsigned int* img_r, float** cost_l, float** cost_r,
              float** acost_l, float** acost_r, float ucd, float lcd, int usd, int lsd);

#endif
