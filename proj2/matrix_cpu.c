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

    float *A = (float*)malloc(bytes);
    float *B = (float*)malloc(bytes);
    float *C = (float*)malloc(bytes);

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

    double start = omp_get_wtime();

    #pragma omp parallel for collapse(2)
    for (int row = 0; row < n; row++) {
        for (int col = 0; col < n; col++) {
            float sum = 0.0f;
            for (int k = 0; k < n; k++) {
                sum += A[row * n + k] * B[k * n + col];
            }
            C[row * n + col] = sum;
        }
    }

    double end = omp_get_wtime();
    double time_ms = (end - start) * 1000.0;

    double checksum = 0.0;
    for (int idx = 0; idx < n * n; idx++) {
        checksum += C[idx];
    }

    printf("Matrix multiply on CPU (OpenMP): %dx%d\n", n, n);
    printf("Kernel time: %.3f ms\n", time_ms);
    printf("C[0][0] = %.1f\n", C[0]);
    printf("C[%d][%d] = %.1f\n", n - 1, n - 1, C[n * n - 1]);
    printf("Checksum = %.3f\n", checksum);

    printf("matrix_multiply_cpu,%d,%d,%.6f,%.6f\n", n, omp_get_max_threads(), time_ms, checksum);

    free(A);
    free(B);
    free(C);

    return EXIT_SUCCESS;
}