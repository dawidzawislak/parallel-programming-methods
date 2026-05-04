#include <cuda_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <cstdint>

#define CUDA_CHECK(call)                                                     \
    do {                                                                     \
        cudaError_t error = (call);                                          \
        if (error != cudaSuccess) {                                          \
            std::fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__,       \
                         __LINE__, cudaGetErrorString(error));               \
            std::exit(EXIT_FAILURE);                                         \
        }                                                                    \
    } while (0)

// Simple 32-bit xorshift32 RNG
__device__ unsigned int xorshift32(unsigned int &state) {
    unsigned int x = state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state = x;
    return x;
}

__global__ void monteCarloKernel(unsigned long long points_per_thread,
                                 unsigned long long *inside_count,
                                 unsigned long long seed_base) {
    unsigned int tid = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int state = static_cast<unsigned int>((seed_base ^ tid) + 0x9e3779b9u);

    unsigned long long local_count = 0ULL;
    for (unsigned long long i = 0; i < points_per_thread; ++i) {
        unsigned int r1 = xorshift32(state);
        unsigned int r2 = xorshift32(state);
        // map to [0,1)
        float x = (r1 / 4294967296.0f) * 2.0f - 1.0f;
        float y = (r2 / 4294967296.0f) * 2.0f - 1.0f;
        if (x * x + y * y <= 1.0f) {
            ++local_count;
        }
    }

    if (local_count > 0) {
        atomicAdd(inside_count, local_count);
    }
}

int main(int argc, char **argv) {
    unsigned long long total_points = 10000000ULL; // default 10M
    if (argc > 1) {
        total_points = std::strtoull(argv[1], nullptr, 10);
        if (total_points == 0ULL) {
            std::fprintf(stderr, "Invalid total points '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }

    int threads_per_block = 256;
    int device = 0;
    CUDA_CHECK(cudaSetDevice(device));

    int device_count = 1;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));

    // choose number of threads to cover workload
    unsigned long long threads = 1024ULL * 64ULL; // default 65536 threads
    if (threads > total_points) threads = total_points;

    unsigned long long points_per_thread = total_points / threads;
    if (points_per_thread == 0ULL) {
        points_per_thread = 1ULL;
        threads = total_points;
    }

    int blocks = static_cast<int>((threads + threads_per_block - 1) / threads_per_block);
    int threads_block = threads_per_block;

    unsigned long long *d_inside = nullptr;
    CUDA_CHECK(cudaMalloc(&d_inside, sizeof(unsigned long long)));
    CUDA_CHECK(cudaMemset(d_inside, 0, sizeof(unsigned long long)));

    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    unsigned long long seed_base = 123456789ULL;

    CUDA_CHECK(cudaEventRecord(start));
    monteCarloKernel<<<blocks, threads_block>>>(points_per_thread, d_inside, seed_base);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float kernel_ms = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&kernel_ms, start, stop));

    unsigned long long inside = 0ULL;
    CUDA_CHECK(cudaMemcpy(&inside, d_inside, sizeof(unsigned long long), cudaMemcpyDeviceToHost));

    unsigned long long produced = points_per_thread * static_cast<unsigned long long>(blocks) * static_cast<unsigned long long>(threads_block);
    // produced may exceed requested total_points if rounding; cap for estimate
    if (produced > total_points) produced = total_points;

    double pi_est = 4.0 * static_cast<double>(inside) / static_cast<double>(produced);

    std::printf("Monte Carlo Pi on GPU: requested=%llu produced=%llu\n", total_points, produced);
    std::printf("Kernel time: %.3f ms\n", kernel_ms);
    std::printf("Inside = %llu\n", inside);
    std::printf("Pi estimate = %.8f\n", pi_est);

    // CSV-friendly single-line output: benchmark,points,gpu_count,time_ms,pi_estimate,inside
    std::printf("monte_carlo_pi,%llu,1,%.6f,%.8f,%llu\n", total_points, static_cast<double>(kernel_ms), pi_est, inside);

    CUDA_CHECK(cudaFree(d_inside));
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));

    return EXIT_SUCCESS;
}
