#ifndef D_CA_CROSS_KERNEL 
#define D_CA_CROSS_KERNEL
#include "d_ca_cross.h"
#include "cuda_utils.h"
#include <math.h>

#define CROSS_ARM_COUNT 4

typedef enum
{
    CROSS_ARM_UP = 0,
    CROSS_ARM_DOWN,
    CROSS_ARM_LEFT,
    CROSS_ARM_RIGHT
} cross_arm_e;

__global__ void ca_cross_construction_kernel(unsigned char* img, unsigned char** cross,
                                             float ucd, float lcd, int usd, int lsd,
                                             int num_rows, int num_cols, int elem_sz)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    int ty = threadIdx.y + blockIdx.y * blockDim.y;
    
    if ((tx > num_cols - 1) || (ty > num_rows - 1))
        return;

    unsigned char a_color_b = img[(tx + ty * num_cols) * elem_sz];
    unsigned char a_color_g = img[(tx + ty * num_cols) * elem_sz + 1];
    unsigned char a_color_r = img[(tx + ty * num_cols) * elem_sz + 2];
    
    cross[CROSS_ARM_UP][tx + ty * num_cols] = 0;
    cross[CROSS_ARM_DOWN][tx + ty * num_cols] = 0;
    cross[CROSS_ARM_LEFT][tx + ty * num_cols] = 0;
    cross[CROSS_ARM_RIGHT][tx + ty * num_cols] = 0;
    
    // Upper arm
    for (int y = 1; y <= usd; ++y)
    {
        if (ty - y < 0)
            break;
        
        cross[CROSS_ARM_UP][tx + ty * num_cols] = (unsigned char) y;
        
        int c_color_b = (int) img[(tx + (ty - y) * num_cols) * elem_sz];
        int c_color_g = (int) img[(tx + (ty - y) * num_cols) * elem_sz + 1];
        int c_color_r = (int) img[(tx + (ty - y) * num_cols) * elem_sz + 2];
        
        int p_color_b = (int) img[(tx + (ty - y) * num_cols) * elem_sz];
        int p_color_g = (int) img[(tx + (ty - y) * num_cols) * elem_sz + 1];
        int p_color_r = (int) img[(tx + (ty - y) * num_cols) * elem_sz + 2];

        int ac_mad = max(max(abs(c_color_b - a_color_b), abs(c_color_g - a_color_g)), abs(c_color_r - a_color_r));
        int cp_mad = max(max(abs(c_color_b - p_color_b), abs(c_color_g - p_color_g)), abs(c_color_r - p_color_r));

        if (y > lsd)
        {
            if ((float) ac_mad > ucd)
                break;
        }
        else
        {
            if ((float) ac_mad > lcd || (float) cp_mad > lcd)
                break;
        }
    }

    // Down arm
    for (int y = 1; y <= usd; ++y)
    {
        if ((ty + y) > (num_rows - 1))
            break;
        
        cross[CROSS_ARM_DOWN][tx + ty * num_cols] = (unsigned char) y;
        
        int c_color_b = (int) img[(tx + (ty + y) * num_cols) * elem_sz];
        int c_color_g = (int) img[(tx + (ty + y) * num_cols) * elem_sz + 1];
        int c_color_r = (int) img[(tx + (ty + y) * num_cols) * elem_sz + 2];
        
        int p_color_b = (int) img[(tx + (ty + y) * num_cols) * elem_sz];
        int p_color_g = (int) img[(tx + (ty + y) * num_cols) * elem_sz + 1];
        int p_color_r = (int) img[(tx + (ty + y) * num_cols) * elem_sz + 2];

        int ac_mad = max(max(abs(c_color_b - a_color_b), abs(c_color_g - a_color_g)), abs(c_color_r - a_color_r));
        int cp_mad = max(max(abs(c_color_b - p_color_b), abs(c_color_g - p_color_g)), abs(c_color_r - p_color_r));

        if (y > lsd)
        {
            if ((float) ac_mad > ucd)
                break;
        }
        else
        {
            if ((float) ac_mad > lcd || (float) cp_mad > lcd)
                break;
        }
    }
    
    // Left arm
    for (int x = 1; x <= usd; ++x)
    {
        if (tx - x < 0)
            break;
        
        cross[CROSS_ARM_LEFT][tx + ty * num_cols] = (unsigned char) x;
        
        int c_color_b = (int) img[(tx - x + ty * num_cols) * elem_sz];
        int c_color_g = (int) img[(tx - x + ty * num_cols) * elem_sz + 1];
        int c_color_r = (int) img[(tx - x + ty * num_cols) * elem_sz + 2];
        
        int p_color_b = (int) img[(tx - x + ty * num_cols) * elem_sz];
        int p_color_g = (int) img[(tx - x + ty * num_cols) * elem_sz + 1];
        int p_color_r = (int) img[(tx - x + ty * num_cols) * elem_sz + 2];

        int ac_mad = max(max(abs(c_color_b - a_color_b), abs(c_color_g - a_color_g)), abs(c_color_r - a_color_r));
        int cp_mad = max(max(abs(c_color_b - p_color_b), abs(c_color_g - p_color_g)), abs(c_color_r - p_color_r));

        if (x > lsd)
        {
            if ((float) ac_mad > ucd)
                break;
        }
        else
        {
            if ((float) ac_mad > lcd || (float) cp_mad > lcd)
                break;
        }
    }
    
    // Right arm
    for (int x = 1; x <= usd; ++x)
    {
        if ((tx + x) > (num_cols - 1))
            break;
        
        cross[CROSS_ARM_RIGHT][tx + ty * num_cols] = (unsigned char) x;
        
        int c_color_b = (int) img[(tx + x + ty * num_cols) * elem_sz];
        int c_color_g = (int) img[(tx + x + ty * num_cols) * elem_sz + 1];
        int c_color_r = (int) img[(tx + x + ty * num_cols) * elem_sz + 2];
        
        int p_color_b = (int) img[(tx + x + ty * num_cols) * elem_sz];
        int p_color_g = (int) img[(tx + x + ty * num_cols) * elem_sz + 1];
        int p_color_r = (int) img[(tx + x + ty * num_cols) * elem_sz + 2];

        int ac_mad = max(max(abs(c_color_b - a_color_b), abs(c_color_g - a_color_g)), abs(c_color_r - a_color_r));
        int cp_mad = max(max(abs(c_color_b - p_color_b), abs(c_color_g - p_color_g)), abs(c_color_r - p_color_r));

        if (x > lsd)
        {
            if ((float) ac_mad > ucd)
                break;
        }
        else
        {
            if ((float) ac_mad > lcd || (float) cp_mad > lcd)
                break;
        }
    }
}

void d_ca_cross(unsigned char* d_img, float** d_cost, float **h_cost, 
                float** d_acost, float** h_acost, float *d_acost_memory,
                float ucd, float lcd, int usd, int lsd,
                int num_disp, int num_rows, int num_cols, int elem_sz)
{
    /////////////////////// 
    // DEVICE PARAMETERS //
    ///////////////////////
    
    size_t bw = 160;
    size_t bh = 1;
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);
    
    size_t img_sz = num_rows * num_cols;
    size_t imgelem_sz = img_sz * elem_sz;
    size_t cost_sz = img_sz * num_disp;
    
    //////////////////////// 
    // CROSS CONSTRUCTION //
    ////////////////////////

    unsigned char** d_cross;
    checkCudaError(cudaMalloc(&d_cross, sizeof(unsigned char*) * CROSS_ARM_COUNT));

    unsigned char** h_cross = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);

    unsigned char* d_cross_memory;
    checkCudaError(cudaMalloc(&d_cross_memory, sizeof(unsigned char) * img_sz * CROSS_ARM_COUNT));
    
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
        h_cross[i] = d_cross_memory + (i * img_sz);

    checkCudaError(cudaMemcpy(d_cross, h_cross, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    ca_cross_construction_kernel<<<grid_sz, block_sz>>>(d_img, d_cross, ucd, lcd, usd, lsd, num_rows, num_cols, elem_sz);
    cudaDeviceSynchronize();
    
    ///////////////////////////
    // CROSS-AGGRAGATE COSTS // 
    ///////////////////////////
	int sm_cols = bw + (usd) * 2;
	int sm_sz = sm_cols * bh;
	int sm_padding = usd;
	
	size_t bw_v = 1;
    size_t bh_v = num_rows / 4;
    size_t gw_v = (num_cols + bw_v - 1) / bw_v;
    size_t gh_v = (num_rows + bh_v - 1) / bh_v;
    const dim3 block_sz_v(bw_v, bh_v, 1);
    const dim3 grid_sz_v(gw_v, gh_v, 1);
	
	int sm_rows = bh_v + (usd) * 2;
	int sm_sz_v = sm_rows * bw_v;
	int sm_padding_v = usd;

    for (int d = 0; d < num_disp; ++d)
        h_acost[d] = d_acost_memory + (d * img_sz);

    checkCudaError(cudaMemcpy(d_acost, h_acost, sizeof(float*) * num_disp, cudaMemcpyHostToDevice));
    
    ca_cross_hsum_kernel_2<<<grid_sz, block_sz, sizeof(float) * sm_sz>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols, sm_cols, sm_sz, sm_padding); 
    cudaDeviceSynchronize();
    
    ca_cross_vsum_kernel_2<<<grid_sz_v, block_sz_v, sizeof(float) * sm_sz_v>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols, sm_rows, sm_sz_v, sm_padding_v); 
    cudaDeviceSynchronize();
    
    ca_cross_vsum_kernel_2<<<grid_sz_v, block_sz_v, sizeof(float) * sm_sz_v>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols, sm_rows, sm_sz_v, sm_padding_v); 
    cudaDeviceSynchronize();
    
    ca_cross_hsum_kernel_2<<<grid_sz, block_sz, sizeof(float) * sm_sz>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols, sm_cols, sm_sz, sm_padding); 
    cudaDeviceSynchronize();
    
    
    ///////////////////
    // DE-ALLOCATION // 
    ///////////////////
    
    cudaFree(d_cross_memory);
    cudaFree(d_cross);
    free(h_cross);
}

void ca_cross(unsigned char* img, float** cost, float** acost,
              float ucd, float lcd, int usd, int lsd,
              int num_disp, int num_rows, int num_cols, int elem_sz)
{
    cudaEventPair_t timer;
    
    /////////////////////// 
    // DEVICE PARAMETERS //
    ///////////////////////
    
    size_t bw = 160;
    size_t bh = 1;
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);

    
    //////////////////////// 
    // CROSS CONSTRUCTION //
    ////////////////////////

    unsigned char* d_img;

    checkCudaError(cudaMalloc(&d_img, sizeof(unsigned char) * num_rows * num_cols * elem_sz));
    checkCudaError(cudaMemcpy(d_img, img, sizeof(unsigned char) * num_rows * num_cols * elem_sz, cudaMemcpyHostToDevice));
   
    unsigned char** d_cross;
    checkCudaError(cudaMalloc(&d_cross, sizeof(unsigned char*) * CROSS_ARM_COUNT));

    unsigned char** h_cross = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);
    
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
    {
        checkCudaError(cudaMalloc(&h_cross[i], sizeof(unsigned char) * num_rows * num_cols));
    }

    checkCudaError(cudaMemcpy(d_cross, h_cross, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    // Launch kernel
    startCudaTimer(&timer);
    ca_cross_construction_kernel<<<grid_sz, block_sz>>>(d_img, d_cross, ucd, lcd, usd, lsd, num_rows, num_cols, elem_sz);
    stopCudaTimer(&timer, "Cross Aggragation - Cross Construciton Kernel");
    
    ///////////////////////////
    // CROSS-AGGRAGATE COSTS // 
    ///////////////////////////
    float** d_cost;

    checkCudaError(cudaMalloc(&d_cost, sizeof(float*) * num_disp));

    float** h_cost = (float**) malloc(sizeof(float*) * num_disp);
    
    for (int d = 0; d < num_disp; ++d)
    {
        checkCudaError(cudaMalloc(&h_cost[d], sizeof(float) * num_rows * num_cols));
        checkCudaError(cudaMemcpy(h_cost[d], cost[d], sizeof(float) * num_rows * num_cols, cudaMemcpyHostToDevice));
    }

    checkCudaError(cudaMemcpy(d_cost, h_cost, sizeof(float*) * num_disp, cudaMemcpyHostToDevice));

    
    float** d_acost;
    checkCudaError(cudaMalloc(&d_acost, sizeof(float*) * num_disp));

    float** h_acost = (float**) malloc(sizeof(float*) * num_disp);
    
    for (int d = 0; d < num_disp; ++d)
    {
        checkCudaError(cudaMalloc(&h_acost[d], sizeof(float) * num_rows * num_cols));
    }

    checkCudaError(cudaMemcpy(d_acost, h_acost, sizeof(float*) * num_disp, cudaMemcpyHostToDevice));
    
	int sm_cols = bw + (usd) * 2;
	int sm_sz = sm_cols * bh;
	int sm_padding = usd;
	
	size_t bw_v = 1;
    size_t bh_v = num_rows / 2;
    size_t gw_v = (num_cols + bw_v - 1) / bw_v;
    size_t gh_v = (num_rows + bh_v - 1) / bh_v;
    const dim3 block_sz_v(bw_v, bh_v, 1);
    const dim3 grid_sz_v(gw_v, gh_v, 1);
	
	int sm_rows = bh_v + (usd) * 2;
	int sm_sz_v = sm_rows * bw_v;
	int sm_padding_v = usd;

	/*	
	startCudaTimer(&timer);
    ca_cross_hsum_kernel<<<grid_sz, block_sz>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols); 
    stopCudaTimer(&timer, "Cross Horizontal Sum");
*/
	startCudaTimer(&timer);
    ca_cross_hsum_kernel_2<<<grid_sz, block_sz, sizeof(float) * sm_sz>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols, sm_cols, sm_sz, sm_padding); 
    stopCudaTimer(&timer, "Cross Horizontal Sum #2");
    
	startCudaTimer(&timer);
    ca_cross_vsum_kernel_2<<<grid_sz_v, block_sz_v, sizeof(float) * sm_sz_v>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols, sm_rows, sm_sz_v, sm_padding_v); 
    stopCudaTimer(&timer, "Cross Vertical Sum #2");
    
	startCudaTimer(&timer);
    ca_cross_vsum_kernel_2<<<grid_sz_v, block_sz_v, sizeof(float) * sm_sz_v>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols, sm_rows, sm_sz_v, sm_padding_v); 
    stopCudaTimer(&timer, "Cross Vertical Sum #2");
/*	
	startCudaTimer(&timer);
    ca_cross_vsum_kernel<<<grid_sz, block_sz>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols); 
    stopCudaTimer(&timer, "Cross Vertical Sum");
    
	startCudaTimer(&timer);
    ca_cross_vsum_kernel<<<grid_sz, block_sz>>>(d_cost, d_acost, d_cross, num_disp, num_rows, num_cols); 
    stopCudaTimer(&timer, "Cross Vertical Sum");
*/
	/*
	startCudaTimer(&timer);
    ca_cross_hsum_kernel<<<grid_sz, block_sz>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols); 
    stopCudaTimer(&timer, "Cross Horizontal Sum");
*/	
	startCudaTimer(&timer);
    ca_cross_hsum_kernel_2<<<grid_sz, block_sz, sizeof(float) * sm_sz>>>(d_acost, d_cost, d_cross, num_disp, num_rows, num_cols, sm_cols, sm_sz, sm_padding); 
    stopCudaTimer(&timer, "Cross Horizontal Sum #2");
    
	
	for (int d = 0; d < num_disp; ++d)
    {
        checkCudaError(cudaMemcpy(acost[d], h_cost[d], sizeof(float) * num_cols * num_rows, cudaMemcpyDeviceToHost));
    }
    
     ///////////////////
    // DE-ALLOCATION // 
    ///////////////////

    cudaFree(d_img);
    cudaFree(d_cross);
    cudaFree(d_cost);
    cudaFree(d_acost);
    for (int d = 0; d < num_disp; ++d)
    {
        cudaFree(h_cost[d]);
        cudaFree(h_acost[d]);
    }
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
    {
        cudaFree(h_cross[i]);
    }
    free(h_cost);
    free(h_acost);
    free(h_cross);
}

#endif
