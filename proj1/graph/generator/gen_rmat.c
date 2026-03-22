#include <stdio.h>
#include <stdlib.h>
#include <time.h>

double A = 0.57, B = 0.19, C = 0.19, D = 0.05; // klasyczne parametry Graph500

int choose_quadrant(double r) {
    if (r < A) return 0;      // top-left
    else if (r < A + B) return 1; // top-right
    else if (r < A + B + C) return 2; // bottom-left
    else return 3;            // bottom-right
}

int main(int argc, char *argv[]) {
    if (argc < 4) {
        printf("Użycie: %s <num_nodes> <num_edges> <output_file>\n", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]); // liczba wierzchołków
    int E = atoi(argv[2]); // liczba krawędzi
    char *filename = argv[3];

    srand(time(NULL));

    FILE *f = fopen(filename, "w");
    if (!f) { perror("fopen"); return 1; }

    fprintf(f, "%d %d\n", N, E);

    for (int i = 0; i < E; i++) {
        int u = 0, v = 0;
        int step = N / 2;

        // generujemy krawędź R-MAT
        while (step >= 1) {
            double r = (double)rand() / RAND_MAX;
            int q = choose_quadrant(r);
            if (q == 1) v += step;       // top-right
            else if (q == 2) u += step;  // bottom-left
            else if (q == 3) { u += step; v += step; } // bottom-right
            step /= 2;
        }

        if (u == v) v = (v + 1) % N; // unikaj pętli
        fprintf(f, "%d %d\n", u, v);
    }

    fclose(f);
    printf("Wygenerowano R-MAT graf: %s (%d wierzchołków, %d krawędzi)\n", filename, N, E);
    return 0;
}