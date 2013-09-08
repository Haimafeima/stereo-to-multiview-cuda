#ifndef D_CI_AD_KERNEL 
#define D_CI_AD_KERNEL
#include "d_ci_ad.h"
#include "cuda_utils.h"
#include <math.h>

__global__ void ci_ad_kernel_2(unsigned char* img_l, unsigned char* img_r, 
                                float** cost_l, float** cost_r,
                                int num_disp, int zero_disp, 
                                int num_rows, int num_cols, int elem_sz)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;
    
    int l_idx = (gx + gy * num_cols) * elem_sz;
    for (int d = 0; d < num_disp; ++d)
    {
        int r_offset = min(max(gx + (d - zero_disp), 0), num_cols - 1);
        int r_idx = (r_offset + gy * num_cols) * elem_sz;

        float cost_1 = (float) abs(img_l[l_idx]     - img_r[r_idx]);
        float cost_2 = (float) abs(img_l[l_idx + 1] - img_r[r_idx + 1]);
        float cost_3 = (float) abs(img_l[l_idx + 2] - img_r[r_idx + 2]);

        float cost_average = (cost_1 + cost_2 + cost_3) * 0.33333333333;
        cost_l[d][gx + gy * num_cols] = cost_average;
        
        int l_offset = min(max(gx - (d - zero_disp), 0), num_cols - 1);
        r_idx = (l_offset + gy * num_cols) * elem_sz;

        cost_1 = (float) abs(img_r[l_idx]     - img_l[r_idx]);
        cost_2 = (float) abs(img_r[l_idx + 1] - img_l[r_idx + 1]);
        cost_3 = (float) abs(img_r[l_idx + 2] - img_l[r_idx + 2]);

        cost_average = (cost_1 + cost_2 + cost_3) * 0.33333333333;
        cost_r[d][gx + gy * num_cols] = cost_average;
    }
}

__global__ void ci_ad_kernel(unsigned char* img_l, unsigned char* img_r, 
                             float** cost, 
                             int num_disp, int zero_disp, int dir,
                             int num_rows, int num_cols, int elem_sz)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;
    
    int l_idx = gx + gy * num_cols * elem_sz;
    for (int d = 0; d < num_disp; ++d)
    {
        int r_coord = min(max(gx + dir * (d - zero_disp), 0), num_cols - 1);
        int r_idx = (r_coord + gy * num_cols) * elem_sz;
        float l_cost = (float) img_l[l_idx];
        float r_cost = (float) img_r[r_idx];
        float cost_b = abs(l_cost - r_cost);
        
        l_cost = (float) img_l[l_idx + 1];
        r_cost = (float) img_r[r_idx + 1];
        float cost_g = abs(l_cost - r_cost);
        
        l_cost = (float) img_l[l_idx + 2];
        r_cost = (float) img_r[r_idx + 2];
        float cost_r = abs(l_cost - r_cost);

        float cost_average = (cost_b + cost_g + cost_r) * 0.33333333333;
        cost[d][gx + gy * num_cols] = cost_average;
    }
}
#endif
