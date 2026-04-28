#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

#define N 1024

int main() {
    float *A, *B, *C;

    A = (float*) malloc(sizeof(float) * N * N);
    B = (float*) malloc(sizeof(float) * N * N);
    C = (float*) malloc(sizeof(float) * N * N);

    for (int i = 0; i < N * N; i++) {
        A[i] = 1.0f;
        B[i] = 2.0f;
        C[i] = 0.0f;
    }

    double start = omp_get_wtime();

    #pragma omp target data map(to: A[0:N*N], B[0:N*N]) map(from: C[0:N*N])
    {
        #pragma omp target teams distribute parallel for collapse(2)
        for (int i = 0; i < N; i++) {
            for (int j = 0; j < N; j++) {
                float sum = 0.0f;
                for (int k = 0; k < N; k++) {
                    sum += A[i*N + k] * B[k*N + j];
                }
                C[i*N + j] = sum;
            }
        }
    }

    double end = omp_get_wtime();

    printf("C[0][0] = %f\n", C[0]);
    printf("Time: %f s\n", end - start);

    free(A);
    free(B);
    free(C);

    return 0;
}