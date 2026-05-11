# Analiza BFS - OpenMP vs MPI

Ten katalog zawiera analizę wydajności dla algorytmu BFS (Breadth-First Search).

## Plik

**analiza_bfs.tex** - Analiza pokazująca dominację OpenMP nad MPI dla algorytmów wymagających synchronizacji.

## Jak użyć

W preambule dokumentu:
```latex
\usepackage{listings}
\usepackage{amsmath}

\lstset{
    basicstyle=\ttfamily\small,
    breaklines=true,
    frame=single,
    numbers=left,
    numberstyle=\tiny
}
```

W treści dokumentu:
```latex
\input{analiza_bfs.tex}
```

## Kluczowe wyniki

BFS pokazuje **dramatyczne różnice** między architekturami:

### Graph1 (100K węzłów, 40M krawędzi)
| Konfiguracja | Wydajność | Różnica od OpenMP |
|--------------|-----------|-------------------|
| n1c8 (OpenMP) | **117.95 Medges/s** | 0% (baseline) |
| n2c4 (hybrid) | 102.20 Medges/s | -13% |
| n4c2 (hybrid) | 98.65 Medges/s | -16% |
| n8c1 (MPI) | 102.23 Medges/s | -13% |

### Graph4 (2M węzłów, 800M krawędzi)
| Konfiguracja | Wydajność | Różnica od OpenMP |
|--------------|-----------|-------------------|
| n1c8 (OpenMP) | **103.20 Medges/s** | 0% (baseline) |
| n2c4 (hybrid) | 92.07 Medges/s | -11% |
| n4c2 (hybrid) | 84.83 Medges/s | -18% |
| n8c1 (MPI) | **19.17 Medges/s** | **-81% (!!)** |

## Główne wnioski

1. **OpenMP zawsze najlepsze** - dla wszystkich rozmiarów grafów
2. **Katastrofalna degradacja MPI** - dla graph4 czysty MPI jest **5.4× wolniejszy**!
3. **Overhead synchronizacji** - BFS wymaga synchronizacji między poziomami
4. **Słaba równoległość** - algorytm inherentnie sekwencyjny w wymiarze poziomów
5. **Rekomendacja**: Zawsze używaj OpenMP dla algorytmów grafowych wymagających synchronizacji

## Dlaczego MPI przegrywa?

### Struktura BFS - poziomy wymagają synchronizacji:
```
Poziom 0:  [źródło]           ← 1 węzeł
           ↓ synchronizacja
Poziom 1:  [sąsiedzi]         ← 10 węzłów
           ↓ synchronizacja
Poziom 2:  [sąsiedzi 2-go]    ← 100 węzłów
           ↓ synchronizacja
...
```

Każda synchronizacja w MPI = MPI_Allgather + MPI_Allreduce = latencja sieci!

### Porównanie kosztów:
- **OpenMP**: Bariera w pamięci współdzielonej ~100 ns
- **MPI**: Komunikacja zbiorowa przez sieć ~1-10 μs + transfer danych

Dla graph4 z ~setkami poziomów: setki operacji MPI → gigantyczny overhead!

## Kontrast z Monte Carlo

| Aspekt | Monte Carlo | BFS |
|--------|-------------|-----|
| Typ problemu | Embarrassingly parallel | Synchronizacja poziomowa |
| Różnica n1c8 vs n8c1 | 1% | **439%** (graph4) |
| Komunikacja | Raz na końcu | Co poziom (setki razy) |
| Najlepsza konfiguracja | Wszystkie równe | **Tylko OpenMP** |
| Skalowalność | Idealna | Bardzo słaba |

## Dane źródłowe

Wyniki z plików:
- c_grn1c8.out (1 węzeł × 8 wątków)
- c_grn2c4.out (2 węzły × 4 wątki)
- c_grn4c2.out (4 węzły × 2 wątki)
- c_grn8c1.out (8 węzłów × 1 wątek)

Katalog: `mpr/proj1_results/run_at_2026-03-30_15-07-58-423/jobs/`
