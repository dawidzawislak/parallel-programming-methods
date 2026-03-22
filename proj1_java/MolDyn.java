import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;
import java.io.File;
import java.util.Arrays;

@RegisterStorage(MolDyn.Shared.class)
public class MolDyn implements StartPoint {

    // Klasa przechowująca zmienne współdzielone (widoczne dla innych wątków w klastrze)
    @Storage(MolDyn.class)
    enum Shared {
        partsX, partsY, partsZ
    }

    // Tablice, w których inni zapiszą swoje zaktualizowane fragmenty pozycji
    double[][] partsX;
    double[][] partsY;
    double[][] partsZ;

    // Zmienne konfiguracyjne z argumentów wiersza poleceń
    public static int N;
    public static int iterations;

    public static void main(String[] args) throws Throwable {
        if (args.length < 3) {
            System.out.println("Użycie: java MolDyn <plik_nodes.txt> <liczba_atomow> <liczba_iteracji>");
            return;
        }
        String nodesFile = args[0];
        N = Integer.parseInt(args[1]);
        iterations = Integer.parseInt(args[2]);

        PCJ.executionBuilder(MolDyn.class).addNodes(new File(nodesFile)).start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        // Podział cząstek na wątki
        int chunk = N / numThreads;
        int startIdx = myId * chunk;
        int endIdx = (myId == numThreads - 1) ? N : startIdx + chunk;
        int localSize = endIdx - startIdx;

        // Inicjalizacja lokalnej pamięci na całą przestrzeń
        double[] X = new double[N];
        double[] Y = new double[N];
        double[] Z = new double[N];
        double[] VX = new double[N]; // Prędkości liczymy tylko dla lokalnych cząstek
        double[] VY = new double[N];
        double[] VZ = new double[N];

        // Inicjalizacja struktur współdzielonych PCJ
        partsX = new double[numThreads][];
        partsY = new double[numThreads][];
        partsZ = new double[numThreads][];

        // Początkowe pozycje (prosta sieć krystaliczna lub wartości losowe)
        for (int i = 0; i < N; i++) {
            X[i] = Math.random() * 10.0;
            Y[i] = Math.random() * 10.0;
            Z[i] = Math.random() * 10.0;
        }

        PCJ.barrier(); // Czekamy aż wszyscy zainicjują zmienne

        long startTime = System.nanoTime();
        if (myId == 0) System.out.println("MolDyn: Symulacja " + N + " czastek na " + numThreads + " watkach przez " + iterations + " iteracji.");

        double dt = 0.001; // Krok czasowy

        // Główna pętla symulacji
        for (int iter = 0; iter < iterations; iter++) {
            
            // 1. Obliczanie sił (potencjał Lennarda-Jonesa) TYLKO dla własnej porcji cząstek
            double[] FX = new double[localSize];
            double[] FY = new double[localSize];
            double[] FZ = new double[localSize];

            for (int i = startIdx; i < endIdx; i++) {
                int localI = i - startIdx;
                for (int j = 0; j < N; j++) {
                    if (i == j) continue;
                    
                    double dx = X[i] - X[j];
                    double dy = Y[i] - Y[j];
                    double dz = Z[i] - Z[j];
                    double distSq = dx*dx + dy*dy + dz*dz;
                    
                    if (distSq < 0.1) distSq = 0.1; // Zapobieganie osobliwościom

                    double invDistSq = 1.0 / distSq;
                    double invDist6 = invDistSq * invDistSq * invDistSq;
                    // F = 24 * epsilon * (2 * sigma^12 - sigma^6) / r^2 (uproszczone)
                    double force = 24.0 * (2.0 * invDist6 * invDist6 - invDist6) * invDistSq;

                    FX[localI] += force * dx;
                    FY[localI] += force * dy;
                    FZ[localI] += force * dz;
                }
            }

            // 2. Całkowanie równań ruchu (np. prosta metoda Eulera)
            double[] myNewX = new double[localSize];
            double[] myNewY = new double[localSize];
            double[] myNewZ = new double[localSize];

            for (int i = startIdx; i < endIdx; i++) {
                int localI = i - startIdx;
                VX[i] += FX[localI] * dt;
                VY[i] += FY[localI] * dt;
                VZ[i] += FZ[localI] * dt;

                X[i] += VX[i] * dt;
                Y[i] += VY[i] * dt;
                Z[i] += VZ[i] * dt;

                myNewX[localI] = X[i];
                myNewY[localI] = Y[i];
                myNewZ[localI] = Z[i];
            }

            // 3. Komunikacja PGAS: Wysyłanie swoich nowych pozycji do reszty wątków
            for (int p = 0; p < numThreads; p++) {
                // Wrzucenie tablicy do konkretnego indeksu tablicy u docelowego wątku (p)
                PCJ.put(myNewX, p, Shared.partsX, myId);
                PCJ.put(myNewY, p, Shared.partsY, myId);
                PCJ.put(myNewZ, p, Shared.partsZ, myId);
            }

            // Oczekiwanie aż wszystkie transfery w tej iteracji dotrą na miejsce
            PCJ.barrier();

            // 4. Rekonstrukcja globalnego stanu u każdego węzła na podstawie tego co dostał
            for (int p = 0; p < numThreads; p++) {
                int pChunk = N / numThreads;
                int pStart = p * pChunk;
                int pSize = partsX[p].length;
                System.arraycopy(partsX[p], 0, X, pStart, pSize);
                System.arraycopy(partsY[p], 0, Y, pStart, pSize);
                System.arraycopy(partsZ[p], 0, Z, pStart, pSize);
            }
            
            // Synchronizacja kończąca iterację
            PCJ.barrier();
        }

        long endTime = System.nanoTime();
        if (myId == 0) {
            System.out.printf("MolDyn Zakonczony! Czas calkowity: %.3f s\n", (endTime - startTime) / 1e9);
        }
    }
}