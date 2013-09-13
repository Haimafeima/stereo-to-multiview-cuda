#ifndef D_CI_CENSUS_H
#define D_CI_CENSUS_H
#include <stdio.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>

__global__ void tx_census_9x7_kernel_3(unsigned char* img, unsigned long long* census, 
                                       int num_rows, int num_cols);

__global__ void tx_census_9x7_kernel_2(unsigned char *img, 
                                       unsigned int **census, 
                                       int num_rows, int num_cols, int elem_sz);


__global__ void tx_census_9x7_kernel(unsigned char* img, unsigned long long* census, 
                                     int num_rows, int num_cols, int elem_sz);

__global__ void ci_census_kernel_6(unsigned long long *census_l, unsigned long long *census_r, 
                                  float **cost_l, float **cost_r,
                                  int num_disp, int zero_disp,
                                  int num_rows, int num_cols, 
                                  int sm_cols, int sm_sz, 
                                  int sm_padding_l, int sm_padding_r);

__global__ void ci_census_kernel_5(unsigned int **census_l, unsigned int **census_r, 
                                  float **cost_l, float **cost_r,
                                  int num_disp, int zero_disp,
                                  int num_rows, int num_cols, int elem_sz,
                                  int sm_cols, int sm_sz, 
                                  int sm_padding_l, int sm_padding_r);

__global__ void ci_census_kernel_4(unsigned long long *census_l, unsigned long long *census_r, 
                                  float **cost_l, float **cost_r,
                                  int num_disp, int zero_disp,
                                  int num_rows, int num_cols, int elem_sz,
                                  int sm_cols, int sm_sz, 
                                  int sm_padding_l, int sm_padding_r);

__global__ void ci_census_kernel_3(unsigned long long *census_l, unsigned long long *census_r, 
                                  float **cost_l, float **cost_r,
                                  int num_disp, int zero_disp,
                                  int num_rows, int num_cols, int elem_sz,
                                  int sm_cols, int sm_sz, 
                                  int sm_padding_l, int sm_padding_r);

__global__ void ci_census_kernel_2(unsigned long long *census_l, unsigned long long *census_r, 
                                  float **cost_l, float **cost_r,
                                  int num_disp, int zero_disp,
                                  int num_rows, int num_cols, int elem_sz);

__global__ void ci_census_kernel(unsigned long long* census_l, unsigned long long* census_r, 
                                 float** cost_l,
                                 int num_disp, int zero_disp, int dir,
                                 int num_rows, int num_cols, int elem_sz);

#endif
