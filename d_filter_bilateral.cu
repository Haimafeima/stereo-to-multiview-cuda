#ifndef D_FILTER_BILATERAL_KERNEL
#define D_FILTER_BILATERAL_KERNEL
#include "d_filter_bilateral.h"
#include "d_filter_gaussian.h"
#include "cuda_utils.h"
#include <math.h>

#define PI 3.14159265359f

inline __device__ float gaussian1D(float x, float sigma)
{
    float variance = pow(sigma, 2);
    float power = pow(x, 2);
    float exponent = -power/(2*variance);
    return __expf(exponent) / sqrt(2 * PI * variance);
}

inline __device__ float gaussian1D_REG(float x, float variance, float sqrt_pi_variance)
{
    float g1d = -(x*x)/(2*variance);
    g1d = __expf(g1d);
    g1d /= sqrt_pi_variance;
    return g1d;
}

float gaussian1D_host(float x, float sigma)
{
    float variance = pow(sigma, 2);
    float power = pow(x, 2);
    float exponent = -power/(2*variance);
    return exp(exponent) / sqrt(2 * PI * variance);
}


void generateGaussian1D(float* kernel, int size, float sigma)
{
    for (int i = 0; i < size; ++i)
        kernel[i] = gaussian1D_host(i, sigma);
}

texture<float, 1, cudaReadModeElementType> tex;

__global__ void filter_bilateral_1_kernel_5(float *img_out, float* kernel,
                                            int radius, float sigma_color, float sigma_color_sqrt_pi,
                                            int num_rows, int num_cols,
                                            int sm_img_rows, int sm_img_cols, int sm_img_sz, int sm_img_padding,
                                            int sm_kernel_len, int sm_kernel_sz)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;
    int tx = threadIdx.x;
    int ty = threadIdx.y;

    extern __shared__ float sm_memory[];
    float* sm_img = sm_memory;
    float* sm_kernel = sm_memory + sm_img_sz;

    // Populate Shared Memory IMG
    for (int gsy = gy - sm_img_padding, tsy = ty;
         tsy < sm_img_rows;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = gx - sm_img_padding, tsx = tx; 
              tsx < sm_img_cols;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             
             int sm_idx = tsx + tsy * sm_img_cols;
             int gm_idx = gsx + gsy * num_cols;
             sm_img[sm_idx] = tex1Dfetch(tex, gm_idx);
         }
    }

    // Populate Shared Memory KERNEL

    for (int gsy = ty, tsy = ty;
         tsy < sm_kernel_len;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = tx, tsx = tx; 
              tsx < sm_kernel_len;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_kernel_len;
             int gm_idx = gsx + gsy * sm_kernel_len;

             sm_kernel[sm_idx] = kernel[gm_idx];
         }
    }

    __syncthreads();
    
    float val_a = sm_img[tx + sm_img_padding + (ty + sm_img_padding) * sm_img_cols];

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = tx + sm_img_padding + x;
            int sy = ty + sm_img_padding + y;

            float val_s = sm_img[sx + sy * sm_img_cols];
           
            float val_gspatial = sm_kernel[(x + radius) + (y + radius) * kernel_width];
            float val_gcolor = gaussian1D_REG(val_a - val_s, sigma_color, sigma_color_sqrt_pi);
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    res /= norm;
    img_out[gx + gy * num_cols] = res;
}
__global__ void filter_bilateral_1_kernel_4(float *img_out, float* kernel,
                                            int radius, float sigma_color, float sigma_color_sqrt_pi,
                                            int num_rows, int num_cols)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;
    
    int idx = gx + gy * num_cols;
    float val_a = tex1Dfetch(tex, idx);

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = gx + x;
            int sy = gy + y;

            if (sx < 0) sx = -sx;
            if (sy < 0) sy = -sy;
            if (sx > num_cols - 1) sx = num_cols - 1 - x;
            if (sy > num_rows - 1) sy = num_rows - 1 - y;

            float val_s = tex1Dfetch(tex, sx + sy * num_cols);

            float val_gspatial = kernel[(x + radius) + (y + radius) * kernel_width];
            float val_gcolor = gaussian1D_REG(val_a - val_s, sigma_color, sigma_color_sqrt_pi);
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    res /= norm;

    img_out[gx + gy * num_cols] = res;
}

void filter_bilateral_1_tex(float *img,
                            int radius, float sigma_color, float sigma_spatial,
                            int num_rows, int num_cols)
{
    cudaEventPair_t timer;
	
    // Setup Block & Grid Size
    size_t bw = 32;
    size_t bh = 32;
    
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);

    int sm_img_rows = bh + 2 * radius;
    int sm_img_cols = bw + 2 * radius;
    int sm_img_sz = sm_img_rows * sm_img_cols;
    int sm_img_padding = radius;

    int sm_kernel_len = 2 * radius + 1;
    int sm_kernel_sz = sm_kernel_len * sm_kernel_len; 
    
    int kernel_sz = sm_kernel_sz; 
    float* kernel = (float*) malloc(sizeof(float) * kernel_sz);
    generateGaussianKernel(kernel, radius, sigma_spatial);
    
    // Device Memory Allocation & Copy
    float* d_img_in;
    float* d_img_out;

    checkCudaError(cudaMalloc(&d_img_in, sizeof(float) * num_rows * num_cols));
    checkCudaError(cudaMemcpy(d_img_in, img, sizeof(float) * num_rows * num_cols, cudaMemcpyHostToDevice));
    cudaBindTexture(0, tex, d_img_in, sizeof(float) * num_rows * num_cols);

    checkCudaError(cudaMalloc(&d_img_out, sizeof(float) * num_rows * num_cols));

    float* d_kernel;
    checkCudaError(cudaMalloc(&d_kernel, sizeof(float) * kernel_sz));
    checkCudaError(cudaMemcpy(d_kernel, kernel, sizeof(float) * kernel_sz, cudaMemcpyHostToDevice));
    
    startCudaTimer(&timer);
    filter_bilateral_1_kernel_5<<<grid_sz, block_sz, sizeof(float) * (sm_img_sz + sm_kernel_sz)>>>(d_img_out, d_kernel, radius, sigma_color, sqrt(2 * PI * sigma_color), num_rows, num_cols, sm_img_rows, sm_img_cols, sm_img_sz, sm_img_padding, sm_kernel_len, sm_kernel_sz);
    stopCudaTimer(&timer, "Bilateral Filter (1 Component) Kernel #5");
    
    checkCudaError(cudaMemcpy(img, d_img_out, sizeof(float) * num_rows * num_cols, cudaMemcpyDeviceToHost));

    free(kernel);
    cudaFree(d_kernel);
    cudaFree(d_img_out);
    cudaFree(d_img_in);
}

__global__ void filter_bilateral_1_kernel_6(float *img_out, float *img_in, 
                                            float* spatial_kernel, float* color_kernel,
                                            int radius, 
                                            int num_rows, int num_cols,
                                            int sm_img_rows, int sm_img_cols, int sm_img_sz, int sm_img_padding,
                                            int sm_spatial_kernel_len, int sm_spatial_kernel_sz,
                                            int sm_color_kernel_len)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;

    int tx = threadIdx.x;
    int ty = threadIdx.y;

    extern __shared__ float sm_memory[];
    float* sm_img = sm_memory;
    float* sm_spatial_kernel = sm_memory + sm_img_sz;
    float* sm_color_kernel = sm_spatial_kernel + sm_spatial_kernel_sz;
    
    for (int gsy = gy - sm_img_padding, tsy = ty;
         tsy < sm_img_rows;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = gx - sm_img_padding, tsx = tx; 
              tsx < sm_img_cols;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_img_cols;
             int gm_idx = min(max(gsx, 0), num_cols - 1) + (min(max(gsy, 0), num_rows - 1) * num_cols);
             sm_img[sm_idx] = img_in[gm_idx];
         }
    }
    
    for (int tsy = ty;
         tsy < sm_spatial_kernel_len;
         tsy += blockDim.y)
    {
         for (int tsx = tx; 
              tsx < sm_spatial_kernel_len;
              tsx += blockDim.x)
         {
             int idx = tsx + tsy * sm_spatial_kernel_len;

             sm_spatial_kernel[idx] = spatial_kernel[idx];
         }
    }
    
    if (ty == 0)
         for (int tsx = tx; tsx < sm_color_kernel_len; tsx += blockDim.x)
             sm_color_kernel[tsx] = color_kernel[tsx];

    __syncthreads();

    float val_a = sm_img[tx + sm_img_padding + (ty + sm_img_padding) * sm_img_cols];

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        int sy = ty + sm_img_padding + y;
        int sy_sm_img_cols = sy * sm_img_cols;
        int y_radius_kernel_width =  (y + radius) * kernel_width;
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = tx + sm_img_padding + x;
            float val_s = sm_img[sx + sy_sm_img_cols];
           
            float val_gspatial = sm_spatial_kernel[(x + radius) + y_radius_kernel_width];
            float val_gcolor = sm_color_kernel[(int)abs(val_a - val_s)];
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    img_out[gx + gy * num_cols] = res / norm;
}


__global__ void filter_bilateral_1_kernel_3(float *img_out, float *img_in, float* kernel,
                                            int radius, 
                                            float sigma_color, float sigma_color_sqrt_pi, float sigma_spatial,
                                            int num_rows, int num_cols,
                                            int sm_img_rows, int sm_img_cols, int sm_img_sz, int sm_img_padding,
                                            int sm_kernel_len, int sm_kernel_sz)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;

    int tx = threadIdx.x;
    int ty = threadIdx.y;

    extern __shared__ float sm_memory[];
    float* sm_img = sm_memory;
    float* sm_kernel = sm_memory + sm_img_sz;
    
    for (int gsy = gy - sm_img_padding, tsy = ty;
         tsy < sm_img_rows;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = gx - sm_img_padding, tsx = tx; 
              tsx < sm_img_cols;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_img_cols;
             int gm_idx = min(max(gsx, 0), num_cols - 1) + (min(max(gsy, 0), num_rows - 1) * num_cols);
             sm_img[sm_idx] = img_in[gm_idx];
         }
    }
    
    for (int gsy = ty, tsy = ty;
         tsy < sm_kernel_len;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = tx, tsx = tx; 
              tsx < sm_kernel_len;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_kernel_len;
             int gm_idx = gsx + gsy * sm_kernel_len;

             sm_kernel[sm_idx] = kernel[gm_idx];
         }
    }

    __syncthreads();

    float val_a = sm_img[tx + sm_img_padding + (ty + sm_img_padding) * sm_img_cols];

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        int sy = ty + sm_img_padding + y;
        int sy_sm_img_cols = sy * sm_img_cols;
        int y_radius_kernel_width =  (y + radius) * kernel_width;
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = tx + sm_img_padding + x;

            float val_s = sm_img[sx + sy_sm_img_cols];
           
            float val_gspatial = sm_kernel[(x + radius) + y_radius_kernel_width];
            float val_gcolor = gaussian1D_REG(val_a - val_s, sigma_color, sigma_color_sqrt_pi);
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    res /= norm;
    img_out[gx + gy * num_cols] = res;
}

__global__ void filter_bilateral_1_kernel_2(float *img_out, float *img_in, float* kernel,
                                            int radius, float sigma_color, float sigma_spatial,
                                            int num_rows, int num_cols,
                                            int sm_img_rows, int sm_img_cols, int sm_img_sz, int sm_img_padding,
                                            int sm_kernel_len, int sm_kernel_sz)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;

    int tx = threadIdx.x;
    int ty = threadIdx.y;

    extern __shared__ float sm_memory[];
    float* sm_img = sm_memory;
    float* sm_kernel = sm_memory + sm_img_sz;
    
    // Populate Shared Memory IMG
    for (int gsy = gy - sm_img_padding, tsy = ty;
         tsy < sm_img_rows;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = gx - sm_img_padding, tsx = tx; 
              tsx < sm_img_cols;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_img_cols;
             
             int gm_idx = min(max(gsx, 0), num_cols - 1) + min(max(gsy, 0), num_rows - 1) * num_cols;

             sm_img[sm_idx] = img_in[gm_idx];
         }
    }

    for (int gsy = ty, tsy = ty;
         tsy < sm_kernel_len;
         gsy += blockDim.y, tsy += blockDim.y)
    {
         for (int gsx = tx, tsx = tx; 
              tsx < sm_kernel_len;
              gsx += blockDim.x, tsx += blockDim.x)
         {
             int sm_idx = tsx + tsy * sm_kernel_len;
             int gm_idx = gsx + gsy * sm_kernel_len;

             sm_kernel[sm_idx] = kernel[gm_idx];
         }
    }

    __syncthreads();

    float val_a = sm_img[tx + sm_img_padding + (ty + sm_img_padding) * sm_img_cols];

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = tx + sm_img_padding + x;
            int sy = ty + sm_img_padding + y;

            float val_s = sm_img[sx + sy * sm_img_cols];

            float val_gspatial = sm_kernel[(x + radius) + (y + radius) * kernel_width];
            float val_gcolor = gaussian1D(val_a - val_s, sigma_color);
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    res /= norm;
    img_out[gx + gy * num_cols] = res;
}


__global__ void filter_bilateral_1_kernel(float *img_out, float *img_in, float* kernel,
                                          int radius, float sigma_color, float sigma_spatial,
                                          int num_rows, int num_cols)
{
    int gx = threadIdx.x + blockIdx.x * blockDim.x;
    int gy = threadIdx.y + blockIdx.y * blockDim.y;

    if ((gx > num_cols - 1) || (gy > num_rows - 1))
        return;



    float val_a = img_in[gx + gy * num_cols];

    int kernel_width = radius * 2 + 1;
    float norm = 0.0f;
    float res = 0.0f;

    for (int y = -radius; y <= radius; ++y)
    {
        for (int x = -radius; x <= radius; ++x)
        {
            int sx = gx + x;
            int sy = gy + y;

            if (sx < 0) sx = -sx;
            if (sy < 0) sy = -sy;
            if (sx > num_cols - 1) sx = num_cols - 1 - x;
            if (sy > num_rows - 1) sy = num_rows - 1 - y;

            float val_s = img_in[sx + sy * num_cols];

            float val_gspatial = kernel[(x + radius) + (y + radius) * kernel_width];
            float val_gcolor = gaussian1D(val_a - val_s, sigma_color);
            float weight = val_gspatial * val_gcolor;
            
            norm = norm + weight;
            res = res + (val_s * weight); 
        }
    }

    res /= norm;

    img_out[gx + gy * num_cols] = res;
}


void d_filter_bilateral_1(float *d_img,
                          int radius, float sigma_color, float sigma_spatial,
                          int num_rows, int num_cols, int num_disp)
{
    // Setup Block & Grid Size
    size_t bw = 32;
    size_t bh = 30;
    
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);

    int sm_img_rows = bh + 2 * radius;
    int sm_img_cols = bw + 2 * radius;
    int sm_img_sz = sm_img_rows * sm_img_cols;
    int sm_img_padding = radius;

    int sm_spatial_kernel_len = 2 * radius + 1;
    int spatial_kernel_sz = sm_spatial_kernel_len * sm_spatial_kernel_len; 
    
    float* spatial_kernel = (float*) malloc(sizeof(float) * spatial_kernel_sz);
    generateGaussianKernel(spatial_kernel, radius, sigma_spatial);

    int color_kernel_sz = num_disp;
    float* color_kernel = (float*) malloc(sizeof(float) * color_kernel_sz);
    generateGaussian1D(color_kernel, color_kernel_sz, sigma_color);
    
    // Device Memory Allocation & Copy
    float* d_img_out;
    checkCudaError(cudaMalloc(&d_img_out, sizeof(float) * num_rows * num_cols));
    
    float* d_spatial_kernel;
    checkCudaError(cudaMalloc(&d_spatial_kernel, sizeof(float) * spatial_kernel_sz));
    checkCudaError(cudaMemcpy(d_spatial_kernel, spatial_kernel, sizeof(float) * spatial_kernel_sz, cudaMemcpyHostToDevice));
    
    float* d_color_kernel;
    checkCudaError(cudaMalloc(&d_color_kernel, sizeof(float) * color_kernel_sz));
    checkCudaError(cudaMemcpy(d_color_kernel, color_kernel, sizeof(float) * color_kernel_sz, cudaMemcpyHostToDevice));
    
    filter_bilateral_1_kernel_6<<<grid_sz, block_sz, sizeof(float) * (sm_img_sz + spatial_kernel_sz + color_kernel_sz)>>>(d_img_out, d_img, d_spatial_kernel, d_color_kernel, radius, num_rows, num_cols, sm_img_rows, sm_img_cols, sm_img_sz, sm_img_padding, sm_spatial_kernel_len, spatial_kernel_sz, color_kernel_sz);
    cudaDeviceSynchronize(); 
    
    checkCudaError(cudaMemcpy(d_img, d_img_out, sizeof(float) * num_rows * num_cols, cudaMemcpyDeviceToDevice));
    
    cudaFree(d_img_out);
    free(spatial_kernel);
    free(color_kernel);
    cudaFree(d_spatial_kernel);
    cudaFree(d_color_kernel);
}

void filter_bilateral_1(float *img, 
                        int radius, float sigma_color, float sigma_spatial,
                        int num_rows, int num_cols, int num_disp)
{
    cudaEventPair_t timer;
	
    // Setup Block & Grid Size
    size_t bw = 32;
    size_t bh = 30;
    
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);

    int sm_img_rows = bh + 2 * radius;
    int sm_img_cols = bw + 2 * radius;
    int sm_img_sz = sm_img_rows * sm_img_cols;
    int sm_img_padding = radius;

    int sm_spatial_kernel_len = 2 * radius + 1;
    int spatial_kernel_sz = sm_spatial_kernel_len * sm_spatial_kernel_len; 
    
    float* spatial_kernel = (float*) malloc(sizeof(float) * spatial_kernel_sz);
    generateGaussianKernel(spatial_kernel, radius, sigma_spatial);

    int color_kernel_sz = num_disp;
    float* color_kernel = (float*) malloc(sizeof(float) * color_kernel_sz);
    generateGaussian1D(color_kernel, color_kernel_sz, sigma_color);
    
    // Device Memory Allocation & Copy
    float* d_img_in;
    float* d_img_out;

    checkCudaError(cudaMalloc(&d_img_in, sizeof(float) * num_rows * num_cols));
    checkCudaError(cudaMemcpy(d_img_in, img, sizeof(float) * num_rows * num_cols, cudaMemcpyHostToDevice));

    checkCudaError(cudaMalloc(&d_img_out, sizeof(float) * num_rows * num_cols));

    float* d_spatial_kernel;
    checkCudaError(cudaMalloc(&d_spatial_kernel, sizeof(float) * spatial_kernel_sz));
    checkCudaError(cudaMemcpy(d_spatial_kernel, spatial_kernel, sizeof(float) * spatial_kernel_sz, cudaMemcpyHostToDevice));
    
    float* d_color_kernel;
    checkCudaError(cudaMalloc(&d_color_kernel, sizeof(float) * color_kernel_sz));
    checkCudaError(cudaMemcpy(d_color_kernel, color_kernel, sizeof(float) * color_kernel_sz, cudaMemcpyHostToDevice));
    
    startCudaTimer(&timer);
    filter_bilateral_1_kernel_6<<<grid_sz, block_sz, sizeof(float) * (sm_img_sz + spatial_kernel_sz + color_kernel_sz)>>>(d_img_out, d_img_in, d_spatial_kernel, d_color_kernel, radius, num_rows, num_cols, sm_img_rows, sm_img_cols, sm_img_sz, sm_img_padding, sm_spatial_kernel_len, spatial_kernel_sz, color_kernel_sz);
    stopCudaTimer(&timer, "Bilateral Filter (1 Component) Kernel #6");
    
    checkCudaError(cudaMemcpy(img, d_img_out, sizeof(float) * num_rows * num_cols, cudaMemcpyDeviceToHost));

    free(spatial_kernel);
    free(color_kernel);
    cudaFree(d_spatial_kernel);
    cudaFree(d_color_kernel);
    cudaFree(d_img_out);
    cudaFree(d_img_in);
}

#endif
