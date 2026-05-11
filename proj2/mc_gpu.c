#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <omp.h>

// Simple xorshift32 RNG - same as CUDA version
#pragma omp declare target
static inline unsigned int xorshift32(unsigned int *state) {
    unsigned int x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}
#pragma omp end declare target

int main(int argc, char **argv) {
    unsigned long long total_points = 10000000ULL; // default 10M
    if (argc > 1) {
        total_points = strtoull(argv[1], NULL, 10);
        if (total_points == 0ULL) {
            fprintf(stderr, "Invalid total points '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }

    // Configuration - batch points to reduce reduction overhead
    int threads_per_block = 256;
    unsigned long long num_threads = 65536ULL;  // Total GPU threads
    
    if (num_threads > total_points) {
        num_threads = total_points;
    }
    
    unsigned long long points_per_thread = (total_points + num_threads - 1) / num_threads;
    
    unsigned long long seed_base = 123456789ULL;
    unsigned long long inside = 0ULL;
    
    int num_teams = (int)((num_threads + threads_per_block - 1) / threads_per_block);

    double start = omp_get_wtime();

    // OpenMP target offload - batch points per thread to reduce reduction overhead
    #pragma omp target teams distribute parallel for \
        num_teams(num_teams) thread_limit(threads_per_block) \
        reduction(+:inside)
    for (unsigned long long tid = 0; tid < num_threads; tid++) {
        // Initialize RNG state per thread
        unsigned int state = (unsigned int)((seed_base ^ tid) + 0x9e3779b9u);
        
        // Local accumulation - critical for performance!
        unsigned long long local_inside = 0ULL;
        
        unsigned long long start_point = tid * points_per_thread;
        unsigned long long end_point = start_point + points_per_thread;
        if (end_point > total_points) {
            end_point = total_points;
        }
        
        for (unsigned long long i = start_point; i < end_point; i++) {
            unsigned int r1 = xorshift32(&state);
            unsigned int r2 = xorshift32(&state);
            
            // Map to [-1, 1)
            float x = (r1 / 4294967296.0f) * 2.0f - 1.0f;
            float y = (r2 / 4294967296.0f) * 2.0f - 1.0f;
            
            if (x * x + y * y <= 1.0f) {
                local_inside++;
            }
        }
        
        // Only one reduction operation per thread!
        inside += local_inside;
    }

    double end = omp_get_wtime();
    double time_ms = (end - start) * 1000.0;

    unsigned long long produced = total_points;

    double pi_est = 4.0 * (double)inside / (double)produced;

    // Human-friendly output
    printf("Monte Carlo Pi on GPU (OpenMP offload): requested=%llu produced=%llu\n", 
           total_points, produced);
    printf("Kernel time: %.3f ms\n", time_ms);
    printf("Inside = %llu\n", inside);
    printf("Pi estimate = %.8f\n", pi_est);

    // CSV-friendly single-line output: benchmark,points,gpu_count,time_ms,pi_estimate,inside
    printf("monte_carlo_pi_omp_gpu,%llu,1,%.6f,%.8f,%llu\n", 
           total_points, time_ms, pi_est, inside);

    return EXIT_SUCCESS;
}