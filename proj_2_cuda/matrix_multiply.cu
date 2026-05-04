#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>

#define CUDA_CHECK(call)                                                     \
    do {                                                                     \
        cudaError_t error = (call);                                          \
        if (error != cudaSuccess) {                                          \
            std::fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__,        \
                         __LINE__, cudaGetErrorString(error));               \
            std::exit(EXIT_FAILURE);                                         \
        }                                                                    \
    } while (0)

__global__ void matrixMultiply(const float *a,
                               const float *b,
                               float *c,
                               int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row >= n || col >= n) {
        return;
    }

    float sum = 0.0f;
    for (int k = 0; k < n; ++k) {
        sum += a[row * n + k] * b[k * n + col];
    }
    c[row * n + col] = sum;
}

int main(int argc, char **argv) {
    int n = 512;
    if (argc > 1) {
        n = std::atoi(argv[1]);
        if (n <= 0) {
            std::fprintf(stderr, "Invalid matrix size '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }
    constexpr std::size_t elem_size = sizeof(float);
    std::size_t bytes = static_cast<std::size_t>(n) * n * elem_size;

    float *host_a = static_cast<float *>(std::malloc(bytes));
    float *host_b = static_cast<float *>(std::malloc(bytes));
    float *host_c = static_cast<float *>(std::malloc(bytes));

    if (host_a == nullptr || host_b == nullptr || host_c == nullptr) {
        std::fprintf(stderr, "Host allocation failed\n");
        std::free(host_a);
        std::free(host_b);
        std::free(host_c);
        return EXIT_FAILURE;
    }

    for (int row = 0; row < n; ++row) {
        for (int col = 0; col < n; ++col) {
            host_a[row * n + col] = 1.0f + static_cast<float>((row + col) % 7);
            host_b[row * n + col] = 1.0f + static_cast<float>((row * 2 + col) % 5);
            host_c[row * n + col] = 0.0f;
        }
    }

    float *device_a = nullptr;
    float *device_b = nullptr;
    float *device_c = nullptr;

    CUDA_CHECK(cudaMalloc(&device_a, bytes));
    CUDA_CHECK(cudaMalloc(&device_b, bytes));
    CUDA_CHECK(cudaMalloc(&device_c, bytes));

    CUDA_CHECK(cudaMemcpy(device_a, host_a, bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_b, host_b, bytes, cudaMemcpyHostToDevice));

    dim3 threads_per_block(16, 16);
    dim3 blocks_per_grid((n + threads_per_block.x - 1) / threads_per_block.x,
                         (n + threads_per_block.y - 1) / threads_per_block.y);

    cudaEvent_t start = nullptr;
    cudaEvent_t stop = nullptr;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    CUDA_CHECK(cudaEventRecord(start));
    matrixMultiply<<<blocks_per_grid, threads_per_block>>>(device_a, device_b, device_c, n);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float kernel_ms = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&kernel_ms, start, stop));

    CUDA_CHECK(cudaMemcpy(host_c, device_c, bytes, cudaMemcpyDeviceToHost));

    double checksum = 0.0;
    for (int idx = 0; idx < n * n; ++idx) {
        checksum += host_c[idx];
    }

    // Human-friendly output
    std::printf("Matrix multiply on GPU: %dx%d\n", n, n);
    std::printf("Kernel time: %.3f ms\n", kernel_ms);
    std::printf("C[0][0] = %.1f\n", host_c[0]);
    std::printf("C[%d][%d] = %.1f\n", n - 1, n - 1, host_c[n * n - 1]);
    std::printf("Checksum = %.3f\n", checksum);

    // CSV-friendly single-line output: benchmark,problem_size,gpu_count,time_ms,checksum
    std::printf("matrix_multiply,%d,1,%.6f,%.6f\n", n, static_cast<double>(kernel_ms), checksum);

    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    CUDA_CHECK(cudaFree(device_a));
    CUDA_CHECK(cudaFree(device_b));
    CUDA_CHECK(cudaFree(device_c));

    std::free(host_a);
    std::free(host_b);
    std::free(host_c);

    return EXIT_SUCCESS;
}