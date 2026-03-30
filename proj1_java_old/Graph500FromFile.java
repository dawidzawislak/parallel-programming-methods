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
            System.out.println("Usage: java Graph500FromFile <nodes.txt> <graph.txt> [source]");
            return;
        }

        String nodesFile = args[0];
        graphFilePath = args[1];
        bfsSource = (args.length == 3) ? Integer.parseInt(args[2]) : 0;

        PCJ.executionBuilder(Graph500FromFile.class)
                .addNodes(new File(nodesFile))
                .start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();

        inboxes = new int[numThreads][];
        activeThreads = new boolean[numThreads];

        if (myId == 0) {
            System.out.println("Loading graph: " + graphFilePath);
        }
        PCJ.barrier();

        GraphData graphData = loadGraphPartition(graphFilePath, myId, numThreads);

        PCJ.barrier();
        if (myId == 0) {
            System.out.println("Graph loaded. Vertices: " + graphData.vertices +
                    ", Edges: " + graphData.edges);
            System.out.println("Starting BFS from: " + bfsSource);
        }

        long startTime = System.nanoTime();

        BitSet visitedLocal = new BitSet(graphData.localVertexCount);
        IntArrayQueue localFrontier =
                new IntArrayQueue(Math.max(16, graphData.localVertexCount / 8));

        if (ownerId(bfsSource, numThreads) == myId) {
            int local = localIndex(bfsSource, myId, numThreads);
            visitedLocal.set(local);
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

            // ---- BFS expand ----
            while (!localFrontier.isEmpty()) {
                int u = localFrontier.poll();
                int uLocal = localIndex(u, myId, numThreads);

                int start = graphData.offsets[uLocal];
                int end = graphData.offsets[uLocal + 1];

                for (int idx = start; idx < end; idx++) {
                    int v = graphData.adjacency[idx];
                    int owner = ownerId(v, numThreads);

                    if (owner == myId) {
                        int vLocal = localIndex(v, myId, numThreads);
                        if (!visitedLocal.get(vLocal)) {
                            visitedLocal.set(vLocal);
                            localFrontier.add(v);
                            imActive = true;
                        }
                    } else {
                        outboxes[owner].add(v);
                    }
                }
            }

            // ---- SEND MESSAGES ----
            for (int p = 0; p < numThreads; p++) {
                PCJ.put(outboxes[p].toArray(), p, Shared.inboxes, myId);
            }

            PCJ.barrier();
            PCJ.waitFor(Shared.inboxes);

            // ---- RECEIVE ----
            for (int p = 0; p < numThreads; p++) {
                int[] incoming = inboxes[p];
                if (incoming != null) {
                    for (int v : incoming) {
                        if (ownerId(v, numThreads) != myId) continue;

                        int local = localIndex(v, myId, numThreads);
                        if (!visitedLocal.get(local)) {
                            visitedLocal.set(local);
                            localFrontier.add(v);
                            imActive = true;
                        }
                    }
                }
                inboxes[p] = null;
            }

            // ---- SEND ACTIVE FLAG ----
            for (int p = 0; p < numThreads; p++) {
                PCJ.put(imActive, p, Shared.activeThreads, myId);
            }

            PCJ.barrier();
            PCJ.waitFor(Shared.activeThreads);

            globalRunning = false;
            for (int p = 0; p < numThreads; p++) {
                if (activeThreads[p]) {
                    globalRunning = true;
                    break;
                }
            }

            level++;
            if (myId == 0) {
                System.out.println("Finished BFS level " + level);
            }
        }

        long endTime = System.nanoTime();
        if (myId == 0) {
            System.out.printf("BFS finished. Levels: %d Time: %.3f s\n",
                    level, (endTime - startTime) / 1e9);
        }
    }

    // ================= GRAPH LOADING =================

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
                int[] e = parseEdge(line);
                if (e == null) continue;

                int u = e[0];
                int v = e[1];

                if (ownerId(u, numThreads) == myId)
                    degree[localIndex(u, myId, numThreads)]++;

                if (ownerId(v, numThreads) == myId)
                    degree[localIndex(v, myId, numThreads)]++;
            }
        }

        int[] offsets = new int[localVertexCount + 1];
        for (int i = 0; i < localVertexCount; i++)
            offsets[i + 1] = offsets[i] + degree[i];

        int[] adjacency = new int[offsets[localVertexCount]];
        int[] writePos = Arrays.copyOf(offsets, localVertexCount);

        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            reader.readLine();
            String line;

            while ((line = reader.readLine()) != null) {
                int[] e = parseEdge(line);
                if (e == null) continue;

                int u = e[0];
                int v = e[1];

                if (ownerId(u, numThreads) == myId) {
                    int local = localIndex(u, myId, numThreads);
                    adjacency[writePos[local]++] = v;
                }
                if (ownerId(v, numThreads) == myId) {
                    int local = localIndex(v, myId, numThreads);
                    adjacency[writePos[local]++] = u;
                }
            }
        }

        return new GraphData(metadata.vertices, metadata.edges,
                localVertexCount, offsets, adjacency);
    }

    private static GraphMetadata readMetadata(String path) throws IOException {
        try (BufferedReader reader = new BufferedReader(new FileReader(path))) {
            String header = reader.readLine();
            StringTokenizer tok = new StringTokenizer(header);
            int vertices = Integer.parseInt(tok.nextToken());
            long edges = Long.parseLong(tok.nextToken());
            return new GraphMetadata(vertices, edges);
        }
    }

    private static int[] parseEdge(String line) {
        if (line == null || line.trim().isEmpty()) return null;
        StringTokenizer tok = new StringTokenizer(line);
        return new int[]{
                Integer.parseInt(tok.nextToken()),
                Integer.parseInt(tok.nextToken())
        };
    }

    // ================= PARTITION =================

    private static int ownerId(int vertex, int numThreads) {
        return vertex % numThreads;
    }

    private static int localIndex(int vertex, int myId, int numThreads) {
        return vertex / numThreads;
    }

    private static int localVertexCount(int vertices, int myId, int numThreads) {
        if (myId >= vertices) return 0;
        return ((vertices - 1 - myId) / numThreads) + 1;
    }

    // ================= DATA STRUCTURES =================

    private static class GraphMetadata {
        final int vertices;
        final long edges;

        GraphMetadata(int v, long e) {
            vertices = v;
            edges = e;
        }
    }

    private static class GraphData {
        final int vertices;
        final long edges;
        final int localVertexCount;
        final int[] offsets;
        final int[] adjacency;

        GraphData(int v, long e, int l, int[] o, int[] a) {
            vertices = v;
            edges = e;
            localVertexCount = l;
            offsets = o;
            adjacency = a;
        }
    }

    private static class IntArrayList {
        private int[] data = new int[16];
        private int size = 0;

        void add(int value) {
            if (size == data.length)
                data = Arrays.copyOf(data, data.length * 2);
            data[size++] = value;
        }

        int[] toArray() {
            return (size == 0) ? EMPTY_INT_ARRAY : Arrays.copyOf(data, size);
        }
    }

    private static class IntArrayQueue {
        private int[] data;
        private int head, tail, size;

        IntArrayQueue(int capacity) {
            data = new int[Math.max(4, capacity)];
        }

        void add(int v) {
            if (size == data.length) grow();
            data[tail] = v;
            tail = (tail + 1) % data.length;
            size++;
        }

        int poll() {
            int v = data[head];
            head = (head + 1) % data.length;
            size--;
            return v;
        }

        boolean isEmpty() {
            return size == 0;
        }

        private void grow() {
            int[] n = new int[data.length * 2];
            for (int i = 0; i < size; i++)
                n[i] = data[(head + i) % data.length];
            data = n;
            head = 0;
            tail = size;
        }
    }
}