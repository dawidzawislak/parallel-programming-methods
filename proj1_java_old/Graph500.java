import org.pcj.PCJ;
import org.pcj.RegisterStorage;
import org.pcj.StartPoint;
import org.pcj.Storage;

import java.io.File;
import java.util.*;

@RegisterStorage(Graph500.Shared.class)
public class Graph500 implements StartPoint {

    @Storage(Graph500.class)
    enum Shared {
        inboxes, activeThreads
    }

    // Skrzynki pocztowe na wierzchołki odbierane od innych wątków. inboxes[nadawca] = tablica wierzchołków.
    int[][] inboxes;
    
    // Tablica używana do sprawdzania, czy globalnie przeszukiwanie BFS jeszcze trwa
    boolean[] activeThreads;

    public static int scale;
    public static int edgeFactor;

    public static void main(String[] args) throws Throwable {
        if (args.length < 3) {
            System.out.println("Użycie: java Graph500 <plik_nodes.txt> <scale> <edge_factor>");
            return;
        }
        String nodesFile = args[0];
        scale = Integer.parseInt(args[1]);
        edgeFactor = Integer.parseInt(args[2]);

        PCJ.executionBuilder(Graph500.class).addNodes(new File(nodesFile)).start();
    }

    @Override
    public void main() throws Throwable {
        int myId = PCJ.myId();
        int numThreads = PCJ.threadCount();
        
        int N = 1 << scale; // Liczba wierzchołków w grafie = 2^scale
        long numEdges = (long) N * edgeFactor;

        inboxes = new int[numThreads][];
        activeThreads = new boolean[numThreads];

        // Struktura grafu (lokalna część wierzchołków)
        Map<Integer, List<Integer>> localGraph = new HashMap<>();

        if (myId == 0) System.out.println("Generowanie krawędzi (Scale: " + scale + ", Vertices: " + N + ")...");
        PCJ.barrier();

        // 1. GENEROWANIE GRAFU (Kronecker R-MAT) - Każdy wątek generuje fragment i wysyła krawędzie
        long edgesPerThread = numEdges / numThreads;
        Random rand = new Random(12345 + myId); // deterministyczny seed ułatwia porównania

        for (long e = 0; e < edgesPerThread; e++) {
            int u = 0, v = 0;
            int step = N / 2;
            
            // Standardowe parametry R-MAT
            double A = 0.57, B = 0.19, C = 0.19; 
            
            while (step > 0) {
                double r = rand.nextDouble();
                if (r > A) {
                    if (r <= A + B) { v += step; } 
                    else if (r <= A + B + C) { u += step; } 
                    else { u += step; v += step; }
                }
                step /= 2;
            }
            
            // Krawędzie są nieskierowane. Zapisujemy w lokalnym słowniku u własciwego "właściciela"
            // Optymalizacja warta prawdziwego HPC polegałaby na wysłaniu ich przez sieć w fazie generowania.
            // Tutaj symulujemy, że wątek po prostu wstawia "swoje" własności.
            if (u % numThreads == myId) {
                localGraph.computeIfAbsent(u, k -> new ArrayList<>()).add(v);
            }
            if (v % numThreads == myId) {
                localGraph.computeIfAbsent(v, k -> new ArrayList<>()).add(u);
            }
        }

        PCJ.barrier();
        if (myId == 0) System.out.println("Generowanie zakonczone. Rozpoczynam propagacje BFS.");

        long startTime = System.nanoTime();

        // 2. PRZESZUKIWANIE BFS (Level-synchronous)
        Set<Integer> visitedLocal = new HashSet<>();
        Queue<Integer> localFrontier = new LinkedList<>();

        // Znajdźmy wierzchołek startowy. Wybieramy wierzchołek 0 (jeśli należy do nas).
        if (0 % numThreads == myId) {
            localFrontier.add(0);
            visitedLocal.add(0);
        }

        int level = 0;
        boolean globalRunning = true;

        while (globalRunning) {
            // Bufory wysyłkowe na ten krok BFS
            List<Integer>[] outboxes = new ArrayList[numThreads];
            for (int i = 0; i < numThreads; i++) outboxes[i] = new ArrayList<>();

            // A) Przetwarzanie lokalnej kolejki zadań
            while (!localFrontier.isEmpty()) {
                int u = localFrontier.poll();
                List<Integer> neighbors = localGraph.getOrDefault(u, Collections.emptyList());
                
                for (int v : neighbors) {
                    int ownerId = v % numThreads;
                    outboxes[ownerId].add(v); // Przydziel węzeł do wiadomości dla właściciela
                }
            }

            // B) Komunikacja - Wymiana nowych wierzchołków do sprawdzenia
            for (int p = 0; p < numThreads; p++) {
                int[] message = outboxes[p].stream().mapToInt(i -> i).toArray();
                // Wysłanie tablicy wierzchołków do skrzynki odbiorczej węzła 'p', pod indeks 'myId'
                PCJ.put(message, p, Shared.inboxes, myId);
            }
            
            // Czekamy na odebranie wiadomości w skrzynkach od wszystkich
            PCJ.barrier();

            // C) Przeniesienie otrzymanych wiadomości do kolejki na następny poziom
            boolean imActive = false;
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

            // D) Sprawdzanie warunku stopu (rozgłoszenie stanu aktywności)
            for (int p = 0; p < numThreads; p++) {
                PCJ.put(imActive, p, Shared.activeThreads, myId);
            }
            PCJ.barrier();

            // Ocena, czy ktokolwiek w klastrze ma jeszcze cokolwiek w kolejce
            globalRunning = false;
            for (int p = 0; p < numThreads; p++) {
                if (activeThreads[p]) {
                    globalRunning = true;
                    break;
                }
            }

            level++;
            if (myId == 0) System.out.println(" Zakończono BFS poziom " + level);
        }

        long endTime = System.nanoTime();
        if (myId == 0) {
            System.out.printf("Graph500 Zakonczony! Poziomow: %d. Czas: %.3f s\n", level, (endTime - startTime) / 1e9);
        }
    }
}