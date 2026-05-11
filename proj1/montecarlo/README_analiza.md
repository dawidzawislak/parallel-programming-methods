# Analiza Monte Carlo - OpenMP vs MPI

Ten katalog zawiera analizę wydajności dla problemu Monte Carlo (szacowanie wartości π).

## Plik

**analiza_montecarlo.tex** - Zwięzła analiza wyników pokazująca dlaczego dla problemów embarrassingly parallel wszystkie konfiguracje osiągają podobną wydajność (~1% różnicy).

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
\input{analiza_montecarlo.tex}
```

## Kluczowe wyniki

Dla Monte Carlo **NIE MA punktu przejścia** między architekturami:

| Konfiguracja | Wydajność | Różnica od najlepszej |
|--------------|-----------|----------------------|
| n1c8 (OpenMP) | ~625 Mpoints/s | 0% (baseline) |
| n2c4 (hybrid) | ~623 Mpoints/s | -0.3% |
| n4c2 (hybrid) | ~623 Mpoints/s | -0.3% |
| n8c1 (MPI) | ~623 Mpoints/s | -0.3% |

## Główne wnioski

1. **Wszystkie konfiguracje równoważne** - różnice < 1% (szum pomiarowy)
2. **Idealna skalowalność** - wydajność proporcjonalna do liczby rdzeni
3. **Brak cache coherence overhead** - każdy wątek generuje własne dane
4. **Minimalna komunikacja** - tylko jedna operacja MPI_Reduce na końcu
5. **Rekomendacja**: użyj czystego OpenMP dla prostoty

## Kontrast z N-body

| Aspekt | N-body | Monte Carlo |
|--------|--------|-------------|
| Typ problemu | Gęsta interakcja | Embarrassingly parallel |
| Punkt przejścia | N ≈ 100-140 | **Brak** |
| Przewaga OpenMP (małe N) | 2.96× | 1.01× |
| Przewaga MPI (duże N) | 7.09× | 1.00× |
| Cache coherence overhead | **Duży** | **Brak** |

## Dane źródłowe

Wyniki z plików:
- c_mnn1c8.out (1 węzeł × 8 wątków)
- c_mnn2c4.out (2 węzły × 4 wątki)
- c_mnn4c2.out (4 węzły × 2 wątki)
- c_mnn8c1.out (8 węzłów × 1 wątek)

Katalog: `mpr/proj1_results/run_at_2026-03-30_15-07-58-423/jobs/`
