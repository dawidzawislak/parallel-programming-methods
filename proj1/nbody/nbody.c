#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <mpi.h>
#include <omp.h>

int main(int argc, char *argv[])
{
    int rank, size;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0)
            printf("Użycie: ./nbody <liczba_atomow> <liczba_iteracji>\n");
        MPI_Finalize();
        return 0;
    }

    int N = atoi(argv[1]);
    int iterations = atoi(argv[2]);

    // Podział danych między procesy
    int chunk = N / size;
    int startIdx = rank * chunk;
    int endIdx = (rank == size - 1) ? N : startIdx + chunk;
    int localSize = endIdx - startIdx;

    // Globalne tablice
    double *X = (double*) malloc(N * sizeof(double));
    double *Y = (double*) malloc(N * sizeof(double));
    double *Z = (double*) malloc(N * sizeof(double));

    double *VX = (double*) calloc(N, sizeof(double));
    double *VY = (double*) calloc(N, sizeof(double));
    double *VZ = (double*) calloc(N, sizeof(double));

    // Inicjalizacja (tylko raz na wszystkich – broadcast później)
    if (rank == 0) {
        for (int i = 0; i < N; i++) {
            X[i] = drand48() * 10.0;
            Y[i] = drand48() * 10.0;
            Z[i] = drand48() * 10.0;
        }
    }

    // Rozesłanie początkowych danych
    MPI_Bcast(X, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    MPI_Bcast(Y, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    MPI_Bcast(Z, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);

    if (rank == 0)
        printf("NBody MPI+OMP: %d cząstek, %d iteracji, %d procesów\n", N, iterations, size);

    double dt = 0.001;

    double startTime = MPI_Wtime();

    for (int iter = 0; iter < iterations; iter++) {

        double *FX = (double*) calloc(localSize, sizeof(double));
        double *FY = (double*) calloc(localSize, sizeof(double));
        double *FZ = (double*) calloc(localSize, sizeof(double));

        // --- Obliczanie sił (OpenMP)
        #pragma omp parallel for schedule(static)
        for (int i = startIdx; i < endIdx; i++) {
            int localI = i - startIdx;

            for (int j = 0; j < N; j++) {
                if (i == j) continue;

                double dx = X[i] - X[j];
                double dy = Y[i] - Y[j];
                double dz = Z[i] - Z[j];
                double distSq = dx*dx + dy*dy + dz*dz;

                if (distSq < 0.1) distSq = 0.1;

                double invDistSq = 1.0 / distSq;
                double invDist6 = invDistSq * invDistSq * invDistSq;
                double force = 24.0 * (2.0 * invDist6 * invDist6 - invDist6) * invDistSq;

                FX[localI] += force * dx;
                FY[localI] += force * dy;
                FZ[localI] += force * dz;
            }
        }

        // --- Integracja
        double *localX = (double*) malloc(localSize * sizeof(double));
        double *localY = (double*) malloc(localSize * sizeof(double));
        double *localZ = (double*) malloc(localSize * sizeof(double));

        #pragma omp parallel for
        for (int i = startIdx; i < endIdx; i++) {
            int localI = i - startIdx;

            VX[i] += FX[localI] * dt;
            VY[i] += FY[localI] * dt;
            VZ[i] += FZ[localI] * dt;

            X[i] += VX[i] * dt;
            Y[i] += VY[i] * dt;
            Z[i] += VZ[i] * dt;

            localX[localI] = X[i];
            localY[localI] = Y[i];
            localZ[localI] = Z[i];
        }

        // --- Synchronizacja globalnego stanu (MPI)
        MPI_Allgather(localX, localSize, MPI_DOUBLE, X, localSize, MPI_DOUBLE, MPI_COMM_WORLD);
        MPI_Allgather(localY, localSize, MPI_DOUBLE, Y, localSize, MPI_DOUBLE, MPI_COMM_WORLD);
        MPI_Allgather(localZ, localSize, MPI_DOUBLE, Z, localSize, MPI_DOUBLE, MPI_COMM_WORLD);

        free(FX); free(FY); free(FZ);
        free(localX); free(localY); free(localZ);
    }

    double endTime = MPI_Wtime();
    double elapsed = endTime - startTime;
    double totalPoints = (double) N * (double) N * (double) iterations;
    double throughput = totalPoints / elapsed;

    if (rank == 0) {
        printf("Total interactions = %.0f\n", totalPoints);
        printf("Elapsed time = %.6f s\n", elapsed);
        printf("Throughput = %.2f million interactions/s\n", throughput / 1e6);
    }

    free(X); free(Y); free(Z);
    free(VX); free(VY); free(VZ);

    MPI_Finalize();
    return 0;
}