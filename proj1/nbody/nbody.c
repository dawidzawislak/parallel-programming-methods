#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>
#include <omp.h>

#define TILE 64

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

    // --- podział danych (obsługa nierównych chunków)
    int *counts = malloc(size * sizeof(int));
    int *displs = malloc(size * sizeof(int));

    int base = N / size;
    int rem = N % size;

    for (int i = 0; i < size; i++) {
        counts[i] = base + (i < rem ? 1 : 0);
        displs[i] = (i == 0) ? 0 : displs[i-1] + counts[i-1];
    }

    int localSize = counts[rank];
    int startIdx = displs[rank];
    int endIdx = startIdx + localSize;

    // --- globalne tablice
    double *X = malloc(N * sizeof(double));
    double *Y = malloc(N * sizeof(double));
    double *Z = malloc(N * sizeof(double));

    double *VX = calloc(N, sizeof(double));
    double *VY = calloc(N, sizeof(double));
    double *VZ = calloc(N, sizeof(double));

    // --- inicjalizacja
    if (rank == 0) {
        for (int i = 0; i < N; i++) {
            X[i] = drand48() * 10.0;
            Y[i] = drand48() * 10.0;
            Z[i] = drand48() * 10.0;
        }
    }

    MPI_Bcast(X, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    MPI_Bcast(Y, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    MPI_Bcast(Z, N, MPI_DOUBLE, 0, MPI_COMM_WORLD);

    // --- lokalne bufory (RAZ!)
    double *FX = malloc(localSize * sizeof(double));
    double *FY = malloc(localSize * sizeof(double));
    double *FZ = malloc(localSize * sizeof(double));

    double *localX = malloc(localSize * sizeof(double));
    double *localY = malloc(localSize * sizeof(double));
    double *localZ = malloc(localSize * sizeof(double));

    double dt = 0.001;

    if (rank == 0)
        printf("NBody MPI+OMP: %d particles, %d iterations, %d processes\n", N, iterations, size);

    double startTime = MPI_Wtime();

    for (int iter = 0; iter < iterations; iter++) {

        memset(FX, 0, localSize * sizeof(double));
        memset(FY, 0, localSize * sizeof(double));
        memset(FZ, 0, localSize * sizeof(double));

        // --- obliczanie sił
        #pragma omp parallel
        {
            double fx, fy, fz;

            #pragma omp for schedule(static)
            for (int i = startIdx; i < endIdx; i++) {

                int localI = i - startIdx;
                fx = fy = fz = 0.0;

                for (int jj = 0; jj < N; jj += TILE) {
                    int jmax = (jj + TILE > N) ? N : jj + TILE;

                    for (int j = jj; j < jmax; j++) {
                        if (i == j) continue;

                        double dx = X[i] - X[j];
                        double dy = Y[i] - Y[j];
                        double dz = Z[i] - Z[j];

                        double distSq = dx*dx + dy*dy + dz*dz + 1e-9;

                        double invDist2 = 1.0 / distSq;
                        double invDist6 = invDist2 * invDist2 * invDist2;
                        double invDist12 = invDist6 * invDist6;

                        double force = 24.0 * (2.0 * invDist12 - invDist6) * invDist2;

                        fx += force * dx;
                        fy += force * dy;
                        fz += force * dz;
                    }
                }

                FX[localI] = fx;
                FY[localI] = fy;
                FZ[localI] = fz;
            }
        }

        // --- integracja
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

        // --- synchronizacja
        MPI_Allgatherv(localX, localSize, MPI_DOUBLE,
                       X, counts, displs, MPI_DOUBLE, MPI_COMM_WORLD);

        MPI_Allgatherv(localY, localSize, MPI_DOUBLE,
                       Y, counts, displs, MPI_DOUBLE, MPI_COMM_WORLD);

        MPI_Allgatherv(localZ, localSize, MPI_DOUBLE,
                       Z, counts, displs, MPI_DOUBLE, MPI_COMM_WORLD);
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
    free(FX); free(FY); free(FZ);
    free(localX); free(localY); free(localZ);
    free(counts); free(displs);

    MPI_Finalize();
    return 0;
}