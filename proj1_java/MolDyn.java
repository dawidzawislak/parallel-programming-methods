import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;
import java.io.File;

@RegisterStorage(MolDyn.Shared.class)
public class MolDyn implements StartPoint {

    @Storage(MolDyn.class)
    enum Shared {
        partsX, partsY, partsZ
    }

    double[][] partsX;
    double[][] partsY;
    double[][] partsZ;

    public static int N;
    public static int iterations;

    public static void main(String[] args) throws Throwable {
        if (args.length < 3) {
            System.out.println("Usage: java MolDyn <nodes.txt> <N> <iterations>");
            return;
        }

        String nodesFile = args[0];
        N = Integer.parseInt(args[1]);
        iterations = Integer.parseInt(args[2]);

        PCJ.executionBuilder(MolDyn.class)
                .addNodes(new File(nodesFile))
                .start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        int baseChunk = N / numThreads;
        int startIdx = myId * baseChunk;
        int endIdx = (myId == numThreads - 1) ? N : startIdx + baseChunk;
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

        for (int i = 0; i < N; i++) {
            X[i] = Math.random() * 10;
            Y[i] = Math.random() * 10;
            Z[i] = Math.random() * 10;
        }

        PCJ.barrier();

        if (myId == 0) {
            System.out.println("MolDyn: N=" + N + ", threads=" + numThreads + ", iter=" + iterations);
        }

        double dt = 0.001;
        long startTime = System.nanoTime();

        for (int iter = 0; iter < iterations; iter++) {

            double[] FX = new double[localSize];
            double[] FY = new double[localSize];
            double[] FZ = new double[localSize];

            // --- FORCES ---
            for (int i = startIdx; i < endIdx; i++) {
                int li = i - startIdx;

                for (int j = 0; j < N; j++) {
                    if (i == j) continue;

                    double dx = X[i] - X[j];
                    double dy = Y[i] - Y[j];
                    double dz = Z[i] - Z[j];

                    double distSq = dx*dx + dy*dy + dz*dz;
                    if (distSq < 0.1) distSq = 0.1;

                    double inv = 1.0 / distSq;
                    double inv6 = inv * inv * inv;
                    double force = 24.0 * (2 * inv6 * inv6 - inv6) * inv;

                    FX[li] += force * dx;
                    FY[li] += force * dy;
                    FZ[li] += force * dz;
                }
            }

            // --- INTEGRATION ---
            double[] myX = new double[localSize];
            double[] myY = new double[localSize];
            double[] myZ = new double[localSize];

            for (int i = startIdx; i < endIdx; i++) {
                int li = i - startIdx;

                VX[i] += FX[li] * dt;
                VY[i] += FY[li] * dt;
                VZ[i] += FZ[li] * dt;

                X[i] += VX[i] * dt;
                Y[i] += VY[i] * dt;
                Z[i] += VZ[i] * dt;

                myX[li] = X[i];
                myY[li] = Y[i];
                myZ[li] = Z[i];
            }

            // --- SEND ---
            for (int p = 0; p < numThreads; p++) {
                PCJ.put(myX, p, Shared.partsX, myId);
                PCJ.put(myY, p, Shared.partsY, myId);
                PCJ.put(myZ, p, Shared.partsZ, myId);
            }

            PCJ.barrier();
            PCJ.waitFor(Shared.partsX);
            PCJ.waitFor(Shared.partsY);
            PCJ.waitFor(Shared.partsZ);

            // --- MERGE ---
            for (int p = 0; p < numThreads; p++) {
                int pStart = p * baseChunk;

                System.arraycopy(partsX[p], 0, X, pStart, partsX[p].length);
                System.arraycopy(partsY[p], 0, Y, pStart, partsY[p].length);
                System.arraycopy(partsZ[p], 0, Z, pStart, partsZ[p].length);
            }

            PCJ.barrier();

            if (myId == 0 && iter % 10 == 0) {
                System.out.println("Iter " + iter);
            }
        }

        long endTime = System.nanoTime();

        if (myId == 0) {
            System.out.printf("MolDyn DONE: %.3f s\n", (endTime - startTime) / 1e9);
        }
    }
}