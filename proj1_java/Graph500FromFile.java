import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.*;

@RegisterStorage(Graph500FromFile.Shared.class)
public class Graph500FromFile implements StartPoint {

    @Storage(Graph500FromFile.class)
    enum Shared {
        inboxes, activeThreads
    }

    int[][] inboxes;
    boolean[] activeThreads;

    public static String graphFilePath;
    public static int bfsSource;

    public static void main(String[] args) throws Throwable {
        if (args.length < 2 || args.length > 3) {
            System.out.println("Użycie: java Graph500FromFile <plik_nodes.txt> <plik_graphX.txt> [source_vertex]");
            return;
        }

        String nodesFile = args[0];
        graphFilePath = args[1];
        bfsSource = (args.length == 3) ? Integer.parseInt(args[2]) : 0;

        PCJ.executionBuilder(Graph500FromFile.class).addNodes(new File(nodesFile)).start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        inboxes = new int[numThreads][];
        activeThreads = new boolean[numThreads];

        Map<Integer, List<Integer>> localGraph = new HashMap<>();

        if (myId == 0) {
            System.out.println("Wczytywanie grafu z pliku: " + graphFilePath);
        }
        PCJ.barrier();

        GraphMetadata metadata = loadGraphPartition(graphFilePath, myId, numThreads, localGraph);

        PCJ.barrier();
        if (myId == 0) {
            System.out.println("Wczytywanie zakonczone. Vertices: " + metadata.vertices + ", Edges: " + metadata.edges);
            System.out.println("Rozpoczynam propagacje BFS od wierzcholka: " + bfsSource);
        }

        long startTime = System.nanoTime();

        Set<Integer> visitedLocal = new HashSet<>();
        Queue<Integer> localFrontier = new LinkedList<>();

        if (Math.floorMod(bfsSource, numThreads) == myId) {
            localFrontier.add(bfsSource);
            visitedLocal.add(bfsSource);
        }

        int level = 0;
        boolean globalRunning = true;

        while (globalRunning) {
            List<Integer>[] outboxes = new ArrayList[numThreads];
            for (int i = 0; i < numThreads; i++) {
                outboxes[i] = new ArrayList<>();
            }

            boolean imActive = !localFrontier.isEmpty();

            while (!localFrontier.isEmpty()) {
                int u = localFrontier.poll();
                List<Integer> neighbors = localGraph.getOrDefault(u, Collections.emptyList());

                for (int v : neighbors) {
                    int ownerId = Math.floorMod(v, numThreads);
                    outboxes[ownerId].add(v);
                }
            }

            for (int p = 0; p < numThreads; p++) {
                int[] message = outboxes[p].stream().mapToInt(i -> i).toArray();
                PCJ.put(message, p, Shared.inboxes, myId);
            }

            PCJ.barrier();

            for (int p = 0; p < numThreads; p++) {
                if (inboxes[p] != null) {
                    for (int v : inboxes[p]) {
                        if (!visitedLocal.contains(v)) {
                            visitedLocal.add(v);
                            localFrontier.add(v);
                            imActive = true;
                        }
                    }
                }
            }

            for (int p = 0; p < numThreads; p++) {
                PCJ.put(imActive, p, Shared.activeThreads, myId);
            }
            PCJ.barrier();

            globalRunning = false;
            for (int p = 0; p < numThreads; p++) {
                if (activeThreads[p]) {
                    globalRunning = true;
                    break;
                }
            }

            level++;
            if (myId == 0) {
                System.out.println("Zakonczono BFS poziom " + level);
            }
        }

        long endTime = System.nanoTime();
        if (myId == 0) {
            System.out.printf("Graph500FromFile zakonczony! Poziomow: %d. Czas: %.3f s\n", level, (endTime - startTime) / 1e9);
        }
    }

    private static GraphMetadata loadGraphPartition(String path,
                                                    int myId,
                                                    int numThreads,
                                                    Map<Integer, List<Integer>> localGraph) throws IOException {
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            String header = reader.readLine();
            if (header == null) {
                throw new IOException("Plik grafu jest pusty: " + path);
            }

            String[] headerParts = header.trim().split("\\s+");
            if (headerParts.length < 2) {
                throw new IOException("Nieprawidlowy naglowek grafu (oczekiwano: <V> <E>): " + header);
            }

            int vertices = Integer.parseInt(headerParts[0]);
            long edges = Long.parseLong(headerParts[1]);

            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) {
                    continue;
                }

                String[] parts = line.split("\\s+");
                if (parts.length < 2) {
                    continue;
                }

                int u = Integer.parseInt(parts[0]);
                int v = Integer.parseInt(parts[1]);

                if (Math.floorMod(u, numThreads) == myId) {
                    localGraph.computeIfAbsent(u, key -> new ArrayList<>()).add(v);
                }
                if (Math.floorMod(v, numThreads) == myId) {
                    localGraph.computeIfAbsent(v, key -> new ArrayList<>()).add(u);
                }
            }

            return new GraphMetadata(vertices, edges);
        }
    }

    private static class GraphMetadata {
        final int vertices;
        final long edges;

        GraphMetadata(int vertices, long edges) {
            this.vertices = vertices;
            this.edges = edges;
        }
    }
}
