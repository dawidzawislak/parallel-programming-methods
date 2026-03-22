#include <stdio.h>
#include <mpi.h>
#include <omp.h>
#include <sched.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    int rank, size, len;
    char hostname[MPI_MAX_PROCESSOR_NAME];

    MPI_Init(&argc, &argv);

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(hostname, &len);

    #pragma omp parallel
    {
        int thread = omp_get_thread_num();
        int threads = omp_get_num_threads();
        int cpu = sched_getcpu();

        printf(
            "node=%s | rank=%d/%d | thread=%d/%d | cpu=%d\n",
            hostname, rank+1, size, thread+1, threads, cpu
        );
    }

    MPI_Finalize();
    return 0;
}