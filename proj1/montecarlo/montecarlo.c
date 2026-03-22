#include <stdio.h>
#include <stdlib.h>
#include <mpi.h>
#include <omp.h>
#include <unistd.h>
#include <sched.h>
#include <time.h>

double monte_carlo_pi(long num_points) {
    long count = 0;

    #pragma omp parallel
    {
        unsigned int seed = (unsigned int)time(NULL) ^ omp_get_thread_num();
        long local_count = 0;

        #pragma omp for
        for (long i = 0; i < num_points; i++) {
            double x = (double)rand_r(&seed) / RAND_MAX;
            double y = (double)rand_r(&seed) / RAND_MAX;
            if (x*x + y*y <= 1.0) local_count++;
        }

        #pragma omp atomic
        count += local_count;
    }

    return 4.0 * count / num_points;
}

int main(int argc, char *argv[]) {
    int rank, size, len;
    char hostname[MPI_MAX_PROCESSOR_NAME];
    long total_points = 100000000; // 100 mln punktów, można zmieniać

    if (argc > 1) total_points = atol(argv[1]);

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(hostname, &len);

    double points_per_rank = total_points / size;
    double start_time = MPI_Wtime();

    double local_pi = monte_carlo_pi(points_per_rank);

    double global_pi;
    MPI_Reduce(&local_pi, &global_pi, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    global_pi /= size; // średnia z ranków

    double end_time = MPI_Wtime();

    if (rank == 0) {
        printf("Estimated Pi = %.12f\n", global_pi);
        printf("Total points = %ld\n", total_points);
        printf("Elapsed time = %.6f s\n", end_time - start_time);
        printf("Throughput = %.2f million points/s\n", total_points / (end_time - start_time) / 1e6);
    }

    // Dodatkowe info o wątkach i CPU
    // #pragma omp parallel
    // {
    //     int thread = omp_get_thread_num();
    //     int threads = omp_get_num_threads();
    //     int cpu = sched_getcpu();
    //     printf("node=%s | rank=%d/%d | thread=%d/%d | cpu=%d\n",
    //            hostname, rank+1, size, thread+1, threads, cpu);
    // }

    MPI_Finalize();
    return 0;
}