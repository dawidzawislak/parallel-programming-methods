import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.Arrays;
import java.util.BitSet;
import java.util.StringTokenizer;

@RegisterStorage(Graph500FromFile.Shared.class)
public class Graph500FromFile implements StartPoint {

    private static final int[] EMPTY_INT_ARRAY = new int[0];

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

        if (myId == 0) {
            System.out.println("Wczytywanie grafu z pliku: " + graphFilePath);
        }
        PCJ.barrier();

        GraphData graphData = loadGraphPartition(graphFilePath, myId, numThreads);

        PCJ.barrier();
        if (myId == 0) {
            System.out.println("Wczytywanie zakonczone. Vertices: " + graphData.vertices + ", Edges: " + graphData.edges);
            System.out.println("Rozpoczynam propagacje BFS od wierzcholka: " + bfsSource);
        }

        long startTime = System.nanoTime();

        BitSet visitedLocal = new BitSet(graphData.localVertexCount);
        IntArrayQueue localFrontier = new IntArrayQueue(Math.max(16, graphData.localVertexCount / 8));

        if (bfsSource >= 0 && bfsSource < graphData.vertices && ownerId(bfsSource, numThreads) == myId) {
            int sourceLocalIndex = localIndex(bfsSource, myId, numThreads);
            visitedLocal.set(sourceLocalIndex);
            localFrontier.add(bfsSource);
        }

        int level = 0;
        boolean globalRunning = true;

        while (globalRunning) {
            IntArrayList[] outboxes = new IntArrayList[numThreads];
            for (int i = 0; i < numThreads; i++) {
                outboxes[i] = new IntArrayList();
            }

            boolean imActive = !localFrontier.isEmpty();

            while (!localFrontier.isEmpty()) {
                int u = localFrontier.poll();
                int uLocalIndex = localIndex(u, myId, numThreads);
                if (uLocalIndex < 0 || uLocalIndex >= graphData.localVertexCount) {
                    continue;
                }

                int start = graphData.offsets[uLocalIndex];
                int end = graphData.offsets[uLocalIndex + 1];

                for (int idx = start; idx < end; idx++) {
                    int v = graphData.adjacency[idx];
                    int vOwnerId = ownerId(v, numThreads);

                    if (vOwnerId == myId) {
                        int vLocalIndex = localIndex(v, myId, numThreads);
                        if (vLocalIndex >= 0 && vLocalIndex < graphData.localVertexCount && !visitedLocal.get(vLocalIndex)) {
                            visitedLocal.set(vLocalIndex);
                            localFrontier.add(v);
                            imActive = true;
                        }
                    } else {
                        outboxes[vOwnerId].add(v);
                    }
                }
            }

            for (int p = 0; p < numThreads; p++) {
                int[] message = outboxes[p].toArray();
                PCJ.put(message, p, Shared.inboxes, myId);
            }

            PCJ.barrier();

            for (int p = 0; p < numThreads; p++) {
                int[] incoming = inboxes[p];
                if (incoming != null && incoming.length > 0) {
                    for (int v : incoming) {
                        if (v < 0 || v >= graphData.vertices || ownerId(v, numThreads) != myId) {
                            continue;
                        }

                        int localV = localIndex(v, myId, numThreads);
                        if (!visitedLocal.get(localV)) {
                            visitedLocal.set(localV);
                            localFrontier.add(v);
                            imActive = true;
                        }
                    }
                }
                inboxes[p] = null;
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

    private static GraphData loadGraphPartition(String path,
                                                int myId,
                                                int numThreads) throws IOException {
        GraphMetadata metadata = readMetadata(path);
        int localVertexCount = localVertexCount(metadata.vertices, myId, numThreads);
        int[] degree = new int[localVertexCount];

        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            reader.readLine();

            String line;
            while ((line = reader.readLine()) != null) {
                int[] edge = parseEdge(line);
                if (edge == null) {
                    continue;
                }

                int u = edge[0];
                int v = edge[1];
                if (u < 0 || v < 0 || u >= metadata.vertices || v >= metadata.vertices) {
                    continue;
                }

                if (ownerId(u, numThreads) == myId) {
                    degree[localIndex(u, myId, numThreads)]++;
                }
                if (ownerId(v, numThreads) == myId) {
                    degree[localIndex(v, myId, numThreads)]++;
                }
            }
        }

        int[] offsets = new int[localVertexCount + 1];
        for (int i = 0; i < localVertexCount; i++) {
            offsets[i + 1] = offsets[i] + degree[i];
        }

        int[] adjacency = new int[offsets[localVertexCount]];
        int[] writePos = Arrays.copyOf(offsets, localVertexCount);

        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            reader.readLine();

            String line;
            while ((line = reader.readLine()) != null) {
                int[] edge = parseEdge(line);
                if (edge == null) {
                    continue;
                }

                int u = edge[0];
                int v = edge[1];
                if (u < 0 || v < 0 || u >= metadata.vertices || v >= metadata.vertices) {
                    continue;
                }

                if (ownerId(u, numThreads) == myId) {
                    int uLocal = localIndex(u, myId, numThreads);
                    adjacency[writePos[uLocal]++] = v;
                }
                if (ownerId(v, numThreads) == myId) {
                    int vLocal = localIndex(v, myId, numThreads);
                    adjacency[writePos[vLocal]++] = u;
                }
            }
        }

        return new GraphData(metadata.vertices, metadata.edges, localVertexCount, offsets, adjacency);
    }

    private static GraphMetadata readMetadata(String path) throws IOException {
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            String header = reader.readLine();
            if (header == null) {
                throw new IOException("Plik grafu jest pusty: " + path);
            }

            StringTokenizer tokenizer = new StringTokenizer(header);
            if (tokenizer.countTokens() < 2) {
                throw new IOException("Nieprawidlowy naglowek grafu (oczekiwano: <V> <E>): " + header);
            }

            int vertices = Integer.parseInt(tokenizer.nextToken());
            long edges = Long.parseLong(tokenizer.nextToken());
            return new GraphMetadata(vertices, edges);
        }
    }

    private static int[] parseEdge(String line) {
        if (line == null) {
            return null;
        }

        String trimmed = line.trim();
        if (trimmed.isEmpty()) {
            return null;
        }

        StringTokenizer tokenizer = new StringTokenizer(trimmed);
        if (tokenizer.countTokens() < 2) {
            return null;
        }

        int u = Integer.parseInt(tokenizer.nextToken());
        int v = Integer.parseInt(tokenizer.nextToken());
        return new int[] {u, v};
    }

    private static int ownerId(int vertex, int numThreads) {
        return Math.floorMod(vertex, numThreads);
    }

    private static int localIndex(int vertex, int myId, int numThreads) {
        return Math.floorDiv(vertex - myId, numThreads);
    }

    private static int localVertexCount(int vertices, int myId, int numThreads) {
        if (myId >= vertices) {
            return 0;
        }
        return ((vertices - 1 - myId) / numThreads) + 1;
    }

    private static class GraphMetadata {
        final int vertices;
        final long edges;

        GraphMetadata(int vertices, long edges) {
            this.vertices = vertices;
            this.edges = edges;
        }
    }

    private static class GraphData {
        final int vertices;
        final long edges;
        final int localVertexCount;
        final int[] offsets;
        final int[] adjacency;

        GraphData(int vertices, long edges, int localVertexCount, int[] offsets, int[] adjacency) {
            this.vertices = vertices;
            this.edges = edges;
            this.localVertexCount = localVertexCount;
            this.offsets = offsets;
            this.adjacency = adjacency;
        }
    }

    private static class IntArrayList {
        private int[] data;
        private int size;

        IntArrayList() {
            this.data = new int[16];
            this.size = 0;
        }

        void add(int value) {
            if (size == data.length) {
                data = Arrays.copyOf(data, data.length * 2);
            }
            data[size++] = value;
        }

        int[] toArray() {
            if (size == 0) {
                return EMPTY_INT_ARRAY;
            }
            return Arrays.copyOf(data, size);
        }
    }

    private static class IntArrayQueue {
        private int[] data;
        private int head;
        private int tail;
        private int size;

        IntArrayQueue(int initialCapacity) {
            int capacity = Math.max(4, initialCapacity);
            this.data = new int[capacity];
            this.head = 0;
            this.tail = 0;
            this.size = 0;
        }

        void add(int value) {
            if (size == data.length) {
                grow();
            }

            data[tail] = value;
            tail = (tail + 1) % data.length;
            size++;
        }

        int poll() {
            int value = data[head];
            head = (head + 1) % data.length;
            size--;
            return value;
        }

        boolean isEmpty() {
            return size == 0;
        }

        private void grow() {
            int[] expanded = new int[data.length * 2];
            for (int i = 0; i < size; i++) {
                expanded[i] = data[(head + i) % data.length];
            }
            data = expanded;
            head = 0;
            tail = size;
        }
    }
}
