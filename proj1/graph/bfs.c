#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <mpi.h>

#define MAX_DEGREE 100

int main(int argc, char *argv[]) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 2) {
        if (rank == 0) printf("Usage: %s <graph.txt>\n", argv[0]);
        MPI_Finalize();
        return 0;
    }

    char *filename = argv[1];
    int N, E;

    FILE *f = fopen(filename, "r");
    if (!f) { perror("fopen"); MPI_Finalize(); return 1; }
    fscanf(f, "%d %d", &N, &E);

    // Szybsze tworzenie list sąsiedztwa
    int *adj_data = (int*) malloc(N * MAX_DEGREE * sizeof(int));
    int **adj = (int**) malloc(N * sizeof(int*));
    for (int i = 0; i < N; i++) adj[i] = &adj_data[i * MAX_DEGREE];
    int *deg = (int*) calloc(N, sizeof(int));

    // Wczytanie wszystkich krawędzi do tymczasowej tablicy
    int *edges = (int*) malloc(2 * E * sizeof(int));
    for (int i = 0; i < E; i++) fscanf(f, "%d %d", &edges[2*i], &edges[2*i+1]);
    fclose(f);

    // Równoległe wstawianie krawędzi do list sąsiedztwa
    #pragma omp parallel for
    for (int i = 0; i < E; i++) {
        int u = edges[2*i];
        int v = edges[2*i+1];

        int idx;
        #pragma omp atomic capture
        idx = deg[u]++;
        adj[u][idx] = v;
    }
    free(edges);

    if (rank == 0) 
        printf("Loaded graph with %d nodes and %d edges\n", N, E);

    int *visited = (int*) calloc(N, sizeof(int));
    int *queue = (int*) malloc(N * sizeof(int));
    int front = 0, back = 0;

    int start_node = 0;
    if (rank == 0) {
        visited[start_node] = 1;
        queue[back++] = start_node;
    }

    double t0 = MPI_Wtime();
    int global_new_nodes = 1;

    while (global_new_nodes) {
        int local_back = 0;
        int *local_queue = (int*) malloc(N * sizeof(int));

        #pragma omp parallel
        {
            int *thread_queue = (int*) malloc(N * sizeof(int));
            int thread_back = 0;

            #pragma omp for schedule(static)
            for (int i = 0; i < back; i++) {
                int u = queue[i];
                for (int j = 0; j < deg[u]; j++) {
                    int v = adj[u][j];
                    if (__sync_bool_compare_and_swap(&visited[v], 0, 1)) {
                        thread_queue[thread_back++] = v;
                    }
                }
            }

            #pragma omp critical
            {
                for (int i = 0; i < thread_back; i++) {
                    local_queue[local_back++] = thread_queue[i];
                }
            }

            free(thread_queue);
        }

        free(queue);
        queue = local_queue;
        back = local_back;

        // Rozesłanie nowych wierzchołków do wszystkich procesów
        int *global_visited = (int*) malloc(N * sizeof(int));
        MPI_Allreduce(visited, global_visited, N, MPI_INT, MPI_LOR, MPI_COMM_WORLD);
        for (int i = 0; i < N; i++) visited[i] = global_visited[i];
        free(global_visited);

        // Sprawdzenie, czy są nowe wierzchołki do przetworzenia
        global_new_nodes = (back > 0) ? 1 : 0;
        MPI_Allreduce(MPI_IN_PLACE, &global_new_nodes, 1, MPI_INT, MPI_LOR, MPI_COMM_WORLD);
    }

    double t1 = MPI_Wtime();
    double elapsed = t1 - t0;

    if (rank == 0) {
        printf("Elapsed time = %.6f s\n", elapsed);
        printf("Total edges visited = %d\n", E);
        printf("Throughput = %.2f million edges/s\n", E / elapsed / 1e6);
    }

    free(adj_data);
    free(adj);
    free(deg);
    free(queue);
    free(visited);

    MPI_Finalize();
    return 0;
}