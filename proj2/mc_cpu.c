#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <omp.h>

// Simple xorshift32 RNG
static inline unsigned int xorshift32(unsigned int *state) {
    unsigned int x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

int main(int argc, char **argv) {
    unsigned long long total_points = 10000000ULL; // default 10M
    if (argc > 1) {
        total_points = strtoull(argv[1], NULL, 10);
        if (total_points == 0ULL) {
            fprintf(stderr, "Invalid total points '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }

    unsigned long long seed_base = 123456789ULL;
    unsigned long long inside = 0ULL;

    double start = omp_get_wtime();

    // Parallel CPU version with OpenMP
    #pragma omp parallel reduction(+:inside)
    {
        int tid = omp_get_thread_num();
        unsigned int state = (unsigned int)((seed_base ^ tid) + 0x9e3779b9u);
        
        unsigned long long local_count = 0ULL;
        
        #pragma omp for
        for (unsigned long long i = 0; i < total_points; i++) {
            unsigned int r1 = xorshift32(&state);
            unsigned int r2 = xorshift32(&state);
            
            // Map to [-1, 1)
            float x = (r1 / 4294967296.0f) * 2.0f - 1.0f;
            float y = (r2 / 4294967296.0f) * 2.0f - 1.0f;
            
            if (x * x + y * y <= 1.0f) {
                local_count++;
            }
        }
        
        inside += local_count;
    }

    double end = omp_get_wtime();
    double time_ms = (end - start) * 1000.0;

    double pi_est = 4.0 * (double)inside / (double)total_points;

    // Human-friendly output
    printf("Monte Carlo Pi on CPU (OpenMP): points=%llu\n", total_points);
    printf("Kernel time: %.3f ms\n", time_ms);
    printf("Inside = %llu\n", inside);
    printf("Pi estimate = %.8f\n", pi_est);

    // CSV-friendly single-line output: benchmark,points,cpu_threads,time_ms,pi_estimate,inside
    printf("monte_carlo_pi_cpu,%llu,%d,%.6f,%.8f,%llu\n", 
           total_points, omp_get_max_threads(), time_ms, pi_est, inside);

    return EXIT_SUCCESS;
}
