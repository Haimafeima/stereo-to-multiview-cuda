#ifndef D_DIBR_WARP_KERNEL 
#define D_DIBR_WARP_KERNEL
#include "d_dibr_warp.h"
#include "d_mux_common.h"
#include "cuda_utils.h"
#include <math.h>

__global__ void dibr_forward_warp_kernel(unsigned char* img_out, unsigned char* holes, 
                                         unsigned char* img_in, float* disp,
                                         float shift, int num_rows, int num_cols, int elem_sz)
{
    int tx = threadIdx.x + blockIdx.x * blockDim.x;
    int ty = threadIdx.y + blockIdx.y * blockDim.y;
    
    if ((tx > num_cols - 1) || (ty > num_rows - 1))
        return;
    
    int sd = (int) (disp[tx + ty * num_cols] * shift); 
    int sx = min(max(tx + sd, 0), num_cols - 1);
    //printf("%d ", sd);

    img_out[(sx + ty * num_cols) * elem_sz] = img_in[(tx + ty * num_cols) * elem_sz];
    img_out[(sx + ty * num_cols) * elem_sz + 1] = img_in[(tx + ty * num_cols) * elem_sz + 1];
    img_out[(sx + ty * num_cols) * elem_sz + 2] = img_in[(tx + ty * num_cols) * elem_sz + 2];
    
    holes[sx + ty * num_cols] = 1;
}


void dibr_dfm(unsigned char* img_out,
              unsigned char* img_in_l, unsigned char* img_in_r, float* disp_l, float* disp_r,
              float shift, int num_rows, int num_cols, int elem_sz)
{
    cudaEventPair_t timer;
    
    /////////////////////// 
    // DEVICE PARAMETERS //
    ///////////////////////
    
    size_t bw = 32;
    size_t bh = 32;
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);
    
    /////////////////////// 
    // MEMORY ALLOCATION //
    ///////////////////////
    float* d_disp_l, *d_disp_r;

    checkCudaError(cudaMalloc(&d_disp_l, sizeof(float) * num_rows * num_cols));
    checkCudaError(cudaMalloc(&d_disp_r, sizeof(float) * num_rows * num_cols));

    checkCudaError(cudaMemcpy(d_disp_l, disp_l, sizeof(float) * num_rows * num_cols, cudaMemcpyHostToDevice));
    checkCudaError(cudaMemcpy(d_disp_r, disp_r, sizeof(float) * num_rows * num_cols, cudaMemcpyHostToDevice));
    
    unsigned char* d_img_in_l, *d_img_in_r; 

    checkCudaError(cudaMalloc(&d_img_in_l, sizeof(unsigned char) * num_rows * num_cols * elem_sz));
    checkCudaError(cudaMalloc(&d_img_in_r, sizeof(unsigned char) * num_rows * num_cols * elem_sz));

    checkCudaError(cudaMemcpy(d_img_in_l, img_in_l, sizeof(unsigned char) * num_rows * num_cols * elem_sz, cudaMemcpyHostToDevice));
    checkCudaError(cudaMemcpy(d_img_in_r, img_in_r, sizeof(unsigned char) * num_rows * num_cols * elem_sz, cudaMemcpyHostToDevice));
    
    unsigned char* d_img_out_l, *d_img_out_r; 
    
    checkCudaError(cudaMalloc(&d_img_out_l, sizeof(unsigned char) * num_rows * num_cols * elem_sz));
    checkCudaError(cudaMalloc(&d_img_out_r, sizeof(unsigned char) * num_rows * num_cols * elem_sz));
    
    checkCudaError(cudaMemset(d_img_out_l, 0, sizeof(unsigned char) * num_rows * num_cols * elem_sz));
    checkCudaError(cudaMemset(d_img_out_r, 0, sizeof(unsigned char) * num_rows * num_cols * elem_sz));

    unsigned char* d_holes_l, *d_holes_r; 

    checkCudaError(cudaMalloc(&d_holes_l, sizeof(unsigned char) * num_rows * num_cols));
    checkCudaError(cudaMalloc(&d_holes_r, sizeof(unsigned char) * num_rows * num_cols));
    
    checkCudaError(cudaMemset(d_holes_l, 0, sizeof(unsigned char) * num_rows * num_cols));
    checkCudaError(cudaMemset(d_holes_r, 0, sizeof(unsigned char) * num_rows * num_cols));
    
    /////////////////// 
    // LAUNCH KERNEL //
    ///////////////////
    
    startCudaTimer(&timer);
    dibr_forward_warp_kernel<<<grid_sz, block_sz>>>(d_img_out_l, d_holes_l, d_img_in_l, d_disp_l, shift, num_rows, num_cols, elem_sz);  
    stopCudaTimer(&timer, "DIBR Forward Map Kernel");
    
    startCudaTimer(&timer);
    dibr_forward_warp_kernel<<<grid_sz, block_sz>>>(d_img_out_r, d_holes_r, d_img_in_r, d_disp_r, 1.0 - shift, num_rows, num_cols, elem_sz);  
    stopCudaTimer(&timer, "DIBR Forward Map Kernel");
    
    startCudaTimer(&timer);
    mux_merge_AB_kernel<<<grid_sz, block_sz>>>(d_img_out_l, d_img_out_r, d_holes_l, num_rows, num_cols, elem_sz);  
    stopCudaTimer(&timer, "Merge Kernel");
    
    ///////////////// 
    // MEMORY COPY //
    /////////////////

    checkCudaError(cudaMemcpy(img_out, d_img_out_l, sizeof(unsigned char) * num_rows * num_cols * elem_sz, cudaMemcpyDeviceToHost));

    /////////////////// 
    // DE-ALLOCATION //
    ///////////////////

    cudaFree(d_disp_l);
    cudaFree(d_disp_r);
    cudaFree(d_img_in_l);
    cudaFree(d_img_in_r);
    cudaFree(d_img_out_l);
    cudaFree(d_img_out_r);
    cudaFree(d_holes_l);
    cudaFree(d_holes_r);
    cudaFree(d_img_out_r);
}


#endif
