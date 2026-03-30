import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;

import java.io.File;
import java.util.Random;

@RegisterStorage(MolDyn.Shared.class)
public class MolDyn implements StartPoint {

    @Storage(MolDyn.class)
    enum Shared {
        partsX, partsY, partsZ,
        N, iterations
    }

    double[][] partsX;
    double[][] partsY;
    double[][] partsZ;

    int N;
    int iterations;

    private static int argN;
    private static int argIterations;

    public static void main(String[] args) throws Throwable {
        if (args.length < 3) {
            System.out.println("Użycie: java MolDyn <plik_nodes.txt> <liczba_atomow> <liczba_iteracji>");
            return;
        }
        String nodesFile = args[0];
        argN = Integer.parseInt(args[1]);
        argIterations = Integer.parseInt(args[2]);

        // Nazwa klasy przekazana do Buildera
        PCJ.executionBuilder(MolDyn.class).addNodes(new File(nodesFile)).start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        // 1. Inicjalizacja stałych z Węzła 0 do pozostałych
        if (myId == 0) {
            this.N = argN;
            this.iterations = argIterations;
            for (int p = 1; p < numThreads; p++) {
                PCJ.put(this.N, p, Shared.N);
                PCJ.put(this.iterations, p, Shared.iterations);
            }
        }
        PCJ.barrier(); // Czekamy aż wszyscy pobiorą N i iterations

        int chunk = N / numThreads;
        int startIdx = myId * chunk;
        int endIdx = (myId == numThreads - 1) ? N : startIdx + chunk;
        int localSize = endIdx - startIdx;

        double[] X = new double[N];
        double[] Y = new double[N];
        double[] Z = new double[N];
        double[] VX = new double[N];
        double[] VY = new double[N];
        double[] VZ = new double[N];

        partsX = new double[numThreads][];
        partsY = new double[numThreads][];
        partsZ = new double[numThreads][];

        // Stały seed, żeby pozycje atomów na każdym węźle na starcie były identyczne
        Random rnd = new Random(42);
        for (int i = 0; i < N; i++) {
            X[i] = rnd.nextDouble() * 10.0;
            Y[i] = rnd.nextDouble() * 10.0;
            Z[i] = rnd.nextDouble() * 10.0;
        }

        PCJ.barrier(); 

        long startTime = System.nanoTime();
        if (myId == 0) System.out.println("MolDyn: Symulacja " + N + " czastek na " + numThreads + " watkach przez " + iterations + " iteracji.");

        double dt = 0.001;

        for (int iter = 0; iter < iterations; iter++) {
            
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
                    
                    if (distSq < 0.1) distSq = 0.1;

                    double invDistSq = 1.0 / distSq;
                    double invDist6 = invDistSq * invDistSq * invDistSq;
                    double force = 24.0 * (2.0 * invDist6 * invDist6 - invDist6) * invDistSq;

                    FX[localI] += force * dx;
                    FY[localI] += force * dy;
                    FZ[localI] += force * dz;
                }
            }

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

            // 2. KOMUNIKACJA PIERŚCIENIOWA (Ring Staggered Communication)
            // Synchronizuje przepływ i zdejmuje obciążenie z buforów i wątków
            for (int step = 1; step < numThreads; step++) {
                int targetId = (myId + step) % numThreads;
                PCJ.put(myNewX, targetId, Shared.partsX, myId);
                PCJ.put(myNewY, targetId, Shared.partsY, myId);
                PCJ.put(myNewZ, targetId, Shared.partsZ, myId);
            }
            
            // 3. Każdy node przypisuje swoje własne policzone wyniki do tablicy
            partsX[myId] = myNewX;
            partsY[myId] = myNewY;
            partsZ[myId] = myNewZ;

            // 4. Bariera po bezpiecznej komunikacji
            PCJ.barrier();

            // 5. Złożenie całości u każdego
            for (int p = 0; p < numThreads; p++) {
                int pChunk = N / numThreads;
                int pStart = p * pChunk;
                if (partsX[p] != null) {
                    int pSize = partsX[p].length;
                    System.arraycopy(partsX[p], 0, X, pStart, pSize);
                    System.arraycopy(partsY[p], 0, Y, pStart, pSize);
                    System.arraycopy(partsZ[p], 0, Z, pStart, pSize);
                }
            }
            
            PCJ.barrier();
        }

        long endTime = System.nanoTime();
        if (myId == 0) {
            System.out.printf("MolDyn Zakonczony! Czas calkowity: %.3f s\n", (endTime - startTime) / 1e9);
        }
    }
}