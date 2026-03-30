import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;

import java.io.File;
import java.util.Random;

@RegisterStorage(MonteCarlo.Shared.class)
public class MonteCarlo implements StartPoint {

    @Storage(MonteCarlo.class)
    enum Shared {
        partialCounts, partialPoints
    }

    long[] partialCounts;
    long[] partialPoints;

    public static long totalPoints;

    public static void main(String[] args) throws Throwable {
        if (args.length < 2) {
            System.out.println("Użycie: java MonteCarlo <plik_nodes.txt> <liczba_punktow>");
            return;
        }

        String nodesFile = args[0];
        totalPoints = Long.parseLong(args[1]);

        PCJ.executionBuilder(MonteCarlo.class).addNodes(new File(nodesFile)).start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        partialCounts = new long[numThreads];
        partialPoints = new long[numThreads];

        long pointsPerThread = totalPoints / numThreads;
        long remainder = totalPoints % numThreads;
        long myPoints = pointsPerThread + (myId < remainder ? 1 : 0);

        PCJ.barrier();
        if (myId == 0) {
            System.out.println("MonteCarlo: Estymacja PI dla " + totalPoints + " punktow na " + numThreads + " watkach.");
        }

        long startTime = System.nanoTime();

        Random rand = new Random(1234567L + 9973L * myId);
        long localInside = 0L;

        for (long i = 0; i < myPoints; i++) {
            double x = rand.nextDouble();
            double y = rand.nextDouble();
            if (x * x + y * y <= 1.0) {
                localInside++;
            }
        }

        PCJ.put(localInside, 0, Shared.partialCounts, myId);
        PCJ.put(myPoints, 0, Shared.partialPoints, myId);

        PCJ.barrier();

        if (myId == 0) {
            long globalInside = 0L;
            long globalPoints = 0L;
            for (int p = 0; p < numThreads; p++) {
                globalInside += partialCounts[p];
                globalPoints += partialPoints[p];
            }

            double pi = 4.0 * globalInside / globalPoints;
            long endTime = System.nanoTime();
            double elapsed = (endTime - startTime) / 1e9;

            System.out.printf("Estimated Pi = %.12f\n", pi);
            System.out.printf("Total points = %d\n", globalPoints);
            System.out.printf("Elapsed time = %.6f s\n", elapsed);
            System.out.printf("Throughput = %.2f million points/s\n", globalPoints / elapsed / 1e6);
        }
    }
}