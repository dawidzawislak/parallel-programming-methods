#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main(int argc, char **argv) {
    int n = 512;
    if (argc > 1) {
        n = atoi(argv[1]);
        if (n <= 0) {
            fprintf(stderr, "Invalid matrix size '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }
    
    size_t bytes = (size_t)n * n * sizeof(float);

    float *A = (float *)malloc(bytes);
    float *B = (float *)malloc(bytes);
    float *C = (float *)malloc(bytes);

    if (A == NULL || B == NULL || C == NULL) {
        fprintf(stderr, "Host allocation failed\n");
        free(A);
        free(B);
        free(C);
        return EXIT_FAILURE;
    }

    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            A[row * n + col] = 1.0f + (float)((row + col) % 7);
            B[row * n + col] = 1.0f + (float)((row * 2 + col) % 5);
            C[row * n + col] = 0.0f;
        }
    }

    int threads_per_team = 256;  // odpowiednik 16×16 w CUDA
    int num_teams = (n * n + threads_per_team - 1) / threads_per_team;

    double start = omp_get_wtime();

    #pragma omp target teams distribute parallel for \
        num_teams(num_teams) thread_limit(threads_per_team) \
        map(to: A[0:n*n], B[0:n*n]) map(from: C[0:n*n])
    for (int idx = 0; idx < n * n; idx++) {
        int row = idx / n;
        int col = idx % n;
        
        float sum = 0.0f;
        for (int k = 0; k < n; k++) {
            sum += A[row * n + k] * B[k * n + col];
        }
        C[idx] = sum;
    }

    double end = omp_get_wtime();
    double time_ms = (end - start) * 1000.0;

    double checksum = 0.0;
    for (int idx = 0; idx < n * n; idx++) {
        checksum += C[idx];
    }

    printf("Matrix multiply on GPU (OpenMP offload): %dx%d\n", n, n);
    printf("Kernel time: %.3f ms\n", time_ms);
    printf("C[0][0] = %.1f\n", C[0]);
    printf("C[%d][%d] = %.1f\n", n - 1, n - 1, C[n * n - 1]);
    printf("Checksum = %.3f\n", checksum);

    printf("matrix_multiply_omp_gpu,%d,1,%.6f,%.6f\n", n, time_ms, checksum);

    free(A);
    free(B);
    free(C);

    return EXIT_SUCCESS;
}