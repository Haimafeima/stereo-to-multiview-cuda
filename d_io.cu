#ifndef D_IO_KERNEL 
#define D_IO_KERNEL
#include "d_io.h"

#define CROSS_ARM_COUNT 4

void adcensus_stm(unsigned char *img_sbs, float *disp_l, float *disp_r,
                  unsigned char* interlaced,
                  int num_rows, int num_cols_sbs, int num_cols, 
                  int num_rows_out, int num_cols_out, int elem_sz,
                  int num_views, int angle,
                  int num_disp, int zero_disp,
                  float ad_coeff, float census_coeff,
                  float ucd, float lcd, int usd, int lsd,
                  int thresh_s, float thresh_h)
{
    ///////////
    // SIZES //
    ///////////

    size_t bw = 32;
    size_t bh = 32;
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);
    
    size_t img_sz = num_rows * num_cols;
    size_t imgelem_sz = img_sz * elem_sz;
    size_t cost_sz = img_sz * num_disp;
    
    size_t gw_sbs = (num_cols_sbs + bw - 1) / bw;
    const dim3 grid_sz_sbs(gw_sbs, gh, 1);
    
    ///////////////////////
    // MEMORY ALLOCATION //
    ///////////////////////

    unsigned char* d_img_sbs;    
    unsigned char* d_img_l;
    unsigned char* d_img_r;

    checkCudaError(cudaMalloc(&d_img_sbs, sizeof(unsigned char) * num_rows * num_cols_sbs * elem_sz));
    checkCudaError(cudaMemcpy(d_img_sbs, img_sbs, sizeof(unsigned char) * num_rows * num_cols_sbs * elem_sz, cudaMemcpyHostToDevice)); 

    checkCudaError(cudaMalloc(&d_img_l, sizeof(unsigned char) * imgelem_sz));
    checkCudaError(cudaMalloc(&d_img_r, sizeof(unsigned char) * imgelem_sz));
    
    ///////////////////////////
    // SIDE BY SIDE SPLITTER //
    ///////////////////////////

    demux_sbs<<<grid_sz_sbs, block_sz>>>(d_img_l, d_img_r, d_img_sbs, num_rows, num_cols_sbs, num_cols, elem_sz);
    cudaDeviceSynchronize();
    
    cudaFree(d_img_sbs);

    /////////////////////////
    // COST INITIALIZATION //
    /////////////////////////
    
    float** d_adcensus_cost_l;
    float** d_adcensus_cost_r;
    
    checkCudaError(cudaMalloc(&d_adcensus_cost_l, sizeof(float*) * num_disp));
    checkCudaError(cudaMalloc(&d_adcensus_cost_r, sizeof(float*) * num_disp));
   
    float** h_adcensus_cost_l = (float**) malloc(sizeof(float*) * num_disp);
    float** h_adcensus_cost_r = (float**) malloc(sizeof(float*) * num_disp);

    float* d_adcensus_cost_memory;
    checkCudaError(cudaMalloc(&d_adcensus_cost_memory, sizeof(float) * cost_sz * 2));

    d_ci_adcensus(d_img_l, d_img_r, d_adcensus_cost_l, d_adcensus_cost_r, 
                  h_adcensus_cost_l, h_adcensus_cost_r, d_adcensus_cost_memory,
                  ad_coeff, census_coeff, 
                  num_disp, zero_disp, num_rows, num_cols, elem_sz);
    
    //////////////////////
    // COST AGGRAGATION //
    //////////////////////

    float** d_acost_l, **d_acost_r;

    checkCudaError(cudaMalloc(&d_acost_l, sizeof(float*) * num_disp));
    checkCudaError(cudaMalloc(&d_acost_r, sizeof(float*) * num_disp));

    float** h_acost_l = (float**) malloc(sizeof(float*) * num_disp);
    float** h_acost_r = (float**) malloc(sizeof(float*) * num_disp);

    float* d_acost_memory;
    checkCudaError(cudaMalloc(&d_acost_memory, sizeof(float) * cost_sz * 2));
    
    unsigned char** d_cross_l;
    checkCudaError(cudaMalloc(&d_cross_l, sizeof(unsigned char*) * CROSS_ARM_COUNT));
    unsigned char** h_cross_l = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);
    unsigned char* d_cross_memory_l;
    checkCudaError(cudaMalloc(&d_cross_memory_l, sizeof(unsigned char) * img_sz * CROSS_ARM_COUNT));
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
        h_cross_l[i] = d_cross_memory_l + (i * img_sz);
    checkCudaError(cudaMemcpy(d_cross_l, h_cross_l, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    d_ca_cross(d_img_l, d_adcensus_cost_l, d_acost_l, h_acost_l, d_acost_memory, d_cross_l, ucd, lcd, usd, lsd, num_disp, num_rows, num_cols, elem_sz);
    
    unsigned char** d_cross_r;
    checkCudaError(cudaMalloc(&d_cross_r, sizeof(unsigned char*) * CROSS_ARM_COUNT));
    unsigned char** h_cross_r = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);
    unsigned char* d_cross_memory_r;
    checkCudaError(cudaMalloc(&d_cross_memory_r, sizeof(unsigned char) * img_sz * CROSS_ARM_COUNT));
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
        h_cross_r[i] = d_cross_memory_r + (i * img_sz);
    checkCudaError(cudaMemcpy(d_cross_r, h_cross_r, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    d_ca_cross(d_img_r, d_adcensus_cost_r, d_acost_r, h_acost_r, d_acost_memory + cost_sz, d_cross_r, ucd, lcd, usd, lsd, num_disp, num_rows, num_cols, elem_sz);

    cudaFree(d_acost_l);
    cudaFree(d_acost_r);
    cudaFree(d_acost_memory);
    free(h_acost_l); 
    free(h_acost_r); 

    ///////////////////////////
    // DISPARITY COMPUTATION //
    ///////////////////////////
    
    float* d_disp_l, *d_disp_r;
    
    checkCudaError(cudaMalloc(&d_disp_l, sizeof(float) * img_sz));
    checkCudaError(cudaMalloc(&d_disp_r, sizeof(float) * img_sz));
	
	d_dc_wta(d_adcensus_cost_l, d_disp_l, num_disp, zero_disp, num_rows, num_cols);
    d_dc_wta(d_adcensus_cost_r, d_disp_r, num_disp, zero_disp, num_rows, num_cols);
	
	cudaFree(d_adcensus_cost_l);
    cudaFree(d_adcensus_cost_r);
    cudaFree(d_adcensus_cost_memory);
    free(h_adcensus_cost_l); 
    free(h_adcensus_cost_r); 
   
    unsigned char *d_outliers_l, *d_outliers_r;
    checkCudaError(cudaMalloc(&d_outliers_l, sizeof(unsigned char) * img_sz));
    checkCudaError(cudaMemset(d_outliers_l, 0, sizeof(unsigned char) * img_sz));
    checkCudaError(cudaMalloc(&d_outliers_r, sizeof(unsigned char) * img_sz));
    checkCudaError(cudaMemset(d_outliers_r, 0, sizeof(unsigned char) * img_sz));
    d_dr_dcc(d_outliers_l, d_outliers_r, d_disp_l, d_disp_r, num_rows, num_cols);

    d_dr_irv(d_disp_l, d_outliers_l, d_cross_l, thresh_s, thresh_h, num_rows, num_cols, num_disp, zero_disp, usd, 5);
    d_dr_irv(d_disp_r, d_outliers_r, d_cross_r, thresh_s, thresh_h, num_rows, num_cols, num_disp, zero_disp, usd, 5);
    
    d_filter_bilateral_1(d_disp_l, 7, 5, 10, num_rows, num_cols, num_disp);
    d_filter_bilateral_1(d_disp_r, 7, 5, 10, num_rows, num_cols, num_disp);
    
    checkCudaError(cudaMemcpy(disp_l, d_disp_l, sizeof(float) * img_sz, cudaMemcpyDeviceToHost));
    checkCudaError(cudaMemcpy(disp_r, d_disp_r, sizeof(float) * img_sz, cudaMemcpyDeviceToHost));
    
    //////////
    // DIBR //
    //////////

    unsigned char *d_occl_l, *d_occl_r;
    
    checkCudaError(cudaMalloc(&d_occl_l, sizeof(unsigned char) * img_sz));
    checkCudaError(cudaMalloc(&d_occl_r, sizeof(unsigned char) * img_sz));
    
    d_dibr_occl(d_occl_l, d_occl_r, d_disp_l, d_disp_r, num_rows, num_cols);

    d_filter_bleed_1(d_occl_l, 1, num_rows, num_cols);    
    d_filter_bleed_1(d_occl_r, 1, num_rows, num_cols);

    float *d_mask_l, *d_mask_r;

    checkCudaError(cudaMalloc(&d_mask_l, sizeof(float) * img_sz));
    checkCudaError(cudaMalloc(&d_mask_r, sizeof(float) * img_sz));
    
    dibr_occl_to_mask_kernel<<<grid_sz, block_sz>>>(d_mask_l, d_occl_l, num_rows, num_cols);
    dibr_occl_to_mask_kernel<<<grid_sz, block_sz>>>(d_mask_r, d_occl_r, num_rows, num_cols);
    
    unsigned char* d_views_memory;
    checkCudaError(cudaMalloc(&d_views_memory, sizeof(unsigned char) * imgelem_sz * num_views));

    unsigned char** h_views = (unsigned char**) malloc(sizeof(unsigned char*) * num_views);
    h_views[0] = d_img_r;
    h_views[num_views - 1] = d_img_l;
    for (int v = 1; v < num_views - 1; ++v)
        h_views[v] = d_views_memory + (v * imgelem_sz);
    
    for (int v = 1; v < num_views - 1; ++v)
    {   
        float shift = 1.0 - ((1.0 * (float) v) / ((float) num_views - 1.0));
        d_dibr_dbm(h_views[v], d_img_l, d_img_r, d_disp_l, d_disp_r, d_occl_l, d_occl_r, d_mask_l, d_mask_r, shift, num_rows, num_cols, elem_sz);
    }

    /////////
    // MUX //
    /////////
    unsigned char** d_views;
    checkCudaError(cudaMalloc(&d_views, sizeof(unsigned char*) * num_views));
    checkCudaError(cudaMemcpy(d_views, h_views, sizeof(unsigned char*) * num_views, cudaMemcpyHostToDevice));

    unsigned char* d_interlaced;
    checkCudaError(cudaMalloc(&d_interlaced, sizeof(unsigned char) * num_rows_out * num_cols_out * elem_sz));

    d_mux_multiview(d_views, d_interlaced, num_views, angle, num_rows, num_cols, num_rows_out, num_cols_out, elem_sz);

    checkCudaError(cudaMemcpy(interlaced, d_interlaced, sizeof(unsigned char) * num_rows_out * num_cols_out * elem_sz, cudaMemcpyDeviceToHost));
    
    ///////////////////
    // DE-ALLOCATION //
    ///////////////////
    
    cudaFree(d_img_l);
    cudaFree(d_img_r);
    
    cudaFree(d_cross_l);
    cudaFree(d_cross_r);
    cudaFree(d_cross_memory_l);
    cudaFree(d_cross_memory_r);
    free(h_cross_l);
    free(h_cross_r);
    
    cudaFree(d_disp_l);
    cudaFree(d_disp_r);
    
    cudaFree(d_outliers_l);
    cudaFree(d_outliers_r);
    
    cudaFree(d_occl_l);
    cudaFree(d_occl_r);
    cudaFree(d_mask_l);
    cudaFree(d_mask_r);
    
    cudaFree(d_views_memory);
    cudaFree(d_views);

    cudaFree(d_interlaced);
    
    free(h_views);
}

void adcensus_stm_2(unsigned char *img_sbs, float *disp_l, float *disp_r,
                    unsigned char* interlaced,
                    int num_rows, int num_cols_sbs, int num_cols, 
                    int num_rows_out, int num_cols_out, 
					int num_rows_disp, int num_cols_disp,	
					int elem_sz, float disp_scale,
                    int num_views, int angle,
                    int num_disp, int zero_disp,
                    float ad_coeff, float census_coeff,
                    float ucd, float lcd, int usd, int lsd,
                    int thresh_s, float thresh_h)
{
    ///////////
    // SIZES //
    ///////////

    size_t bw = 32;
    size_t bh = 32;
    size_t gw = (num_cols + bw - 1) / bw;
    size_t gh = (num_rows + bh - 1) / bh;
    const dim3 block_sz(bw, bh, 1);
    const dim3 grid_sz(gw, gh, 1);
    
    size_t img_sz = num_rows * num_cols;
    size_t imgelem_sz = img_sz * elem_sz;
    
    size_t disp_img_sz = num_rows_disp * num_cols_disp;
    size_t disp_imgelem_sz = img_sz * elem_sz;
    size_t disp_cost_sz = disp_img_sz * num_disp;
    
    size_t gw_sbs = (num_cols_sbs + bw - 1) / bw;
    const dim3 grid_sz_sbs(gw_sbs, gh, 1);
    
    ///////////////////////
    // MEMORY ALLOCATION //
    ///////////////////////

    unsigned char* d_img_sbs;    
    unsigned char* d_img_l;
    unsigned char* d_img_r;

    checkCudaError(cudaMalloc(&d_img_sbs, sizeof(unsigned char) * num_rows * num_cols_sbs * elem_sz));
    checkCudaError(cudaMemcpy(d_img_sbs, img_sbs, sizeof(unsigned char) * num_rows * num_cols_sbs * elem_sz, cudaMemcpyHostToDevice)); 

    checkCudaError(cudaMalloc(&d_img_l, sizeof(unsigned char) * imgelem_sz));
    checkCudaError(cudaMalloc(&d_img_r, sizeof(unsigned char) * imgelem_sz));
    
    ///////////////////////////
    // SIDE BY SIDE SPLITTER //
    ///////////////////////////

    demux_sbs<<<grid_sz_sbs, block_sz>>>(d_img_l, d_img_r, d_img_sbs, num_rows, num_cols_sbs, num_cols, elem_sz);
    cudaDeviceSynchronize();
    
    cudaFree(d_img_sbs);
	
	unsigned char* d_low_img_l;
	unsigned char* d_low_img_r;
    
	checkCudaError(cudaMalloc(&d_low_img_l, sizeof(unsigned char) * disp_imgelem_sz));
    checkCudaError(cudaMalloc(&d_low_img_r, sizeof(unsigned char) * disp_imgelem_sz));
	
	tx_scale_bilinear_kernel<<<grid_sz, block_sz>>>(d_img_l, d_low_img_l, num_rows, num_cols, num_rows_disp, num_cols_disp, elem_sz);
	
	tx_scale_bilinear_kernel<<<grid_sz, block_sz>>>(d_img_r, d_low_img_r, num_rows, num_cols, num_rows_disp, num_cols_disp, elem_sz);

    /////////////////////////
    // COST INITIALIZATION //
    /////////////////////////
    
    float** d_adcensus_cost_l;
    float** d_adcensus_cost_r;
    
    checkCudaError(cudaMalloc(&d_adcensus_cost_l, sizeof(float*) * num_disp));
    checkCudaError(cudaMalloc(&d_adcensus_cost_r, sizeof(float*) * num_disp));
   
    float** h_adcensus_cost_l = (float**) malloc(sizeof(float*) * num_disp);
    float** h_adcensus_cost_r = (float**) malloc(sizeof(float*) * num_disp);

    float* d_adcensus_cost_memory;
    checkCudaError(cudaMalloc(&d_adcensus_cost_memory, sizeof(float) * disp_cost_sz * 2));

    d_ci_adcensus(d_low_img_l, d_low_img_r, d_adcensus_cost_l, d_adcensus_cost_r, 
                  h_adcensus_cost_l, h_adcensus_cost_r, d_adcensus_cost_memory,
                  ad_coeff, census_coeff, 
                  num_disp, zero_disp, num_rows_disp, num_cols_disp, elem_sz);
    
    //////////////////////
    // COST AGGRAGATION //
    //////////////////////

    float** d_acost_l, **d_acost_r;

    checkCudaError(cudaMalloc(&d_acost_l, sizeof(float*) * num_disp));
    checkCudaError(cudaMalloc(&d_acost_r, sizeof(float*) * num_disp));

    float** h_acost_l = (float**) malloc(sizeof(float*) * num_disp);
    float** h_acost_r = (float**) malloc(sizeof(float*) * num_disp);

    float* d_acost_memory;
    checkCudaError(cudaMalloc(&d_acost_memory, sizeof(float) * disp_cost_sz * 2));

    unsigned char** d_cross_l;
    checkCudaError(cudaMalloc(&d_cross_l, sizeof(unsigned char*) * CROSS_ARM_COUNT));
    unsigned char** h_cross_l = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);
    unsigned char* d_cross_memory_l;
    checkCudaError(cudaMalloc(&d_cross_memory_l, sizeof(unsigned char) * disp_img_sz * CROSS_ARM_COUNT));
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
        h_cross_l[i] = d_cross_memory_l + (i * disp_img_sz);
    checkCudaError(cudaMemcpy(d_cross_l, h_cross_l, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    d_ca_cross(d_low_img_l, d_adcensus_cost_l, d_acost_l, h_acost_l, d_acost_memory, d_cross_l, ucd, lcd, usd, lsd, num_disp, num_rows_disp, num_cols_disp, elem_sz);

    unsigned char** d_cross_r;
    checkCudaError(cudaMalloc(&d_cross_r, sizeof(unsigned char*) * CROSS_ARM_COUNT));
    unsigned char** h_cross_r = (unsigned char**) malloc(sizeof(unsigned char*) * CROSS_ARM_COUNT);
    unsigned char* d_cross_memory_r;
    checkCudaError(cudaMalloc(&d_cross_memory_r, sizeof(unsigned char) * disp_img_sz * CROSS_ARM_COUNT));
    for (int i = 0; i < CROSS_ARM_COUNT; ++i)
        h_cross_r[i] = d_cross_memory_r + (i * disp_img_sz);
    checkCudaError(cudaMemcpy(d_cross_r, h_cross_r, sizeof(unsigned char*) * CROSS_ARM_COUNT, cudaMemcpyHostToDevice));
    
    d_ca_cross(d_low_img_r, d_adcensus_cost_r, d_acost_r, h_acost_r, d_acost_memory + disp_cost_sz, d_cross_r, ucd, lcd, usd, lsd, num_disp, num_rows_disp, num_cols_disp, elem_sz);
    
    cudaFree(d_acost_l);
    cudaFree(d_acost_r);
    cudaFree(d_acost_memory);
    free(h_acost_l); 
    free(h_acost_r); 

    ///////////////////////////
    // DISPARITY COMPUTATION //
    ///////////////////////////
    
    float* d_disp_l, *d_disp_r;
    
    checkCudaError(cudaMalloc(&d_disp_l, sizeof(float) * disp_img_sz));
    checkCudaError(cudaMalloc(&d_disp_r, sizeof(float) * disp_img_sz));
	
	d_dc_wta(d_adcensus_cost_l, d_disp_l, num_disp, zero_disp, num_rows_disp, num_cols_disp);
    d_dc_wta(d_adcensus_cost_r, d_disp_r, num_disp, zero_disp, num_rows_disp, num_cols_disp);
	
    cudaFree(d_adcensus_cost_l);
    cudaFree(d_adcensus_cost_r);
    cudaFree(d_adcensus_cost_memory);
    free(h_adcensus_cost_l); 
    free(h_adcensus_cost_r); 
    
    //////////////////////////
    // DISPARITY REFINEMENT //
    //////////////////////////
    
    unsigned char *d_outliers_l, *d_outliers_r;
    checkCudaError(cudaMalloc(&d_outliers_l, sizeof(unsigned char) * disp_img_sz));
    checkCudaError(cudaMemset(d_outliers_l, 0, sizeof(unsigned char) * disp_img_sz));
    checkCudaError(cudaMalloc(&d_outliers_r, sizeof(unsigned char) * disp_img_sz));
    checkCudaError(cudaMemset(d_outliers_r, 0, sizeof(unsigned char) * disp_img_sz));
    
    d_dr_dcc(d_outliers_l, d_outliers_r, d_disp_l, d_disp_r, num_rows_disp, num_cols_disp);

    d_dr_irv(d_disp_l, d_outliers_l, d_cross_l, thresh_s, thresh_h, num_rows_disp, num_cols_disp, num_disp, zero_disp, usd, 5);
    d_dr_irv(d_disp_r, d_outliers_r, d_cross_r, thresh_s, thresh_h, num_rows_disp, num_cols_disp, num_disp, zero_disp, usd, 5);
    
    d_filter_bilateral_1(d_disp_l, 7, 5, 10, num_rows_disp, num_cols_disp, num_disp);
    d_filter_bilateral_1(d_disp_r, 7, 5, 10, num_rows_disp, num_cols_disp, num_disp);
	
    ///////////////////////
    // DISPARITY UPSCALE //
    ///////////////////////
    
    float *d_high_disp_l, *d_high_disp_r;	
    
	checkCudaError(cudaMalloc(&d_high_disp_l, sizeof(float) * img_sz));
    checkCudaError(cudaMalloc(&d_high_disp_r, sizeof(float) * img_sz));

	tx_disp_scale_kernel<<<grid_sz, block_sz>>>(d_high_disp_l, d_disp_l, num_rows, num_cols, num_rows_disp, num_cols_disp, 1.0f/disp_scale);
	
	tx_disp_scale_kernel<<<grid_sz, block_sz>>>(d_high_disp_r, d_disp_r, num_rows, num_cols, num_rows_disp, num_cols_disp, 1.0f/disp_scale);

    checkCudaError(cudaMemcpy(disp_l, d_high_disp_l, sizeof(float) * img_sz, cudaMemcpyDeviceToHost));
    checkCudaError(cudaMemcpy(disp_r, d_high_disp_r, sizeof(float) * img_sz, cudaMemcpyDeviceToHost));
    
    //////////
    // DIBR //
    //////////

    unsigned char *d_occl_l, *d_occl_r;
    
    checkCudaError(cudaMalloc(&d_occl_l, sizeof(unsigned char) * img_sz));
    checkCudaError(cudaMalloc(&d_occl_r, sizeof(unsigned char) * img_sz));
    
    d_dibr_occl(d_occl_l, d_occl_r, d_high_disp_l, d_high_disp_r, num_rows, num_cols);

    d_filter_bleed_1(d_occl_l, 1, num_rows, num_cols);    
    d_filter_bleed_1(d_occl_r, 1, num_rows, num_cols);

    float *d_mask_l, *d_mask_r;

    checkCudaError(cudaMalloc(&d_mask_l, sizeof(float) * img_sz));
    checkCudaError(cudaMalloc(&d_mask_r, sizeof(float) * img_sz));
    
    dibr_occl_to_mask_kernel<<<grid_sz, block_sz>>>(d_mask_l, d_occl_l, num_rows, num_cols);
    dibr_occl_to_mask_kernel<<<grid_sz, block_sz>>>(d_mask_r, d_occl_r, num_rows, num_cols);
    
    unsigned char* d_views_memory;
    checkCudaError(cudaMalloc(&d_views_memory, sizeof(unsigned char) * imgelem_sz * num_views));

    unsigned char** h_views = (unsigned char**) malloc(sizeof(unsigned char*) * num_views);
    h_views[0] = d_img_r;
    h_views[num_views - 1] = d_img_l;
    for (int v = 1; v < num_views - 1; ++v)
        h_views[v] = d_views_memory + (v * imgelem_sz);
    
    for (int v = 1; v < num_views - 1; ++v)
    {   
        float shift = 1.0 - ((1.0 * (float) v) / ((float) num_views - 1.0));
        d_dibr_dbm(h_views[v], d_img_l, d_img_r, d_high_disp_l, d_high_disp_r, d_occl_l, d_occl_r, d_mask_l, d_mask_r, shift, num_rows, num_cols, elem_sz);
    }

    /////////
    // MUX //
    /////////
    unsigned char** d_views;
    checkCudaError(cudaMalloc(&d_views, sizeof(unsigned char*) * num_views));
    checkCudaError(cudaMemcpy(d_views, h_views, sizeof(unsigned char*) * num_views, cudaMemcpyHostToDevice));

    unsigned char* d_interlaced;
    checkCudaError(cudaMalloc(&d_interlaced, sizeof(unsigned char) * num_rows_out * num_cols_out * elem_sz));

    d_mux_multiview(d_views, d_interlaced, num_views, angle, num_rows, num_cols, num_rows_out, num_cols_out, elem_sz);

    checkCudaError(cudaMemcpy(interlaced, d_interlaced, sizeof(unsigned char) * num_rows_out * num_cols_out * elem_sz, cudaMemcpyDeviceToHost));
    
    ///////////////////
    // DE-ALLOCATION //
    ///////////////////
    
    cudaFree(d_img_l);
    cudaFree(d_img_r);
    cudaFree(d_low_img_l);
    cudaFree(d_low_img_r);
    
    cudaFree(d_cross_l);
    cudaFree(d_cross_r);
    cudaFree(d_cross_memory_l);
    cudaFree(d_cross_memory_r);
    free(h_cross_l);
    free(h_cross_r);
    cudaFree(d_outliers_l);
    cudaFree(d_outliers_r);
    
    cudaFree(d_disp_l);
    cudaFree(d_disp_r);
	cudaFree(d_high_disp_l);
    cudaFree(d_high_disp_r);

    
	cudaFree(d_occl_l);
    cudaFree(d_occl_r);
    cudaFree(d_mask_l);
    cudaFree(d_mask_r);
    
    cudaFree(d_views_memory);
    cudaFree(d_views);

    cudaFree(d_interlaced);
    
    free(h_views);
}


#endif
