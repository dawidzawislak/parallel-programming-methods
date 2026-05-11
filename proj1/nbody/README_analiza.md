# Dokumentacja analizy wyników N-body

Ten katalog zawiera gotowe sekcje do sprawozdania w LaTeX z analizą wydajności różnych konfiguracji równoległych symulacji N-body.

## Pliki

1. **analiza_wynikow.tex** - Główna sekcja z pełną analizą wyników
   - Tabele z wynikami
   - Analiza punktu przejścia
   - Wyjaśnienia techniczne z fragmentami kodu
   - Wnioski

2. **wykres_wydajnosci.tex** - Wykresy (opcjonalne)
   - Wykres przepustowości
   - Wykres przyspieszenia (speedup)

## Jak użyć

### Minimalna konfiguracja (bez wykresów)

W preambule dokumentu:
```latex
\usepackage{listings}  % dla fragmentów kodu
\usepackage{amsmath}   % dla równań

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
\input{analiza_wynikow.tex}
```

### Pełna konfiguracja (z wykresami)

W preambule dokumentu dodaj:
```latex
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usepackage{tikz}
```

W treści dokumentu:
```latex
\input{analiza_wynikow.tex}
\input{wykres_wydajnosci.tex}
```

## Wyniki

Dane pochodzą z rzeczywistych pomiarów dla konfiguracji:
- **n1c8**: 1 węzeł, 8 wątków OpenMP (czysty OpenMP)
- **n2c4**: 2 węzły, 4 wątki/węzeł (hybrid)
- **n4c2**: 4 węzły, 2 wątki/węzeł (hybrid)
- **n8c1**: 8 węzłów, 1 wątek/węzeł (czysty MPI)

Każda konfiguracja używa łącznie 8 rdzeni procesora.
Testy przeprowadzono dla N ∈ {50, 80, 110, 140, 170, 200, 230, 260, 290, 320, 350, 380} cząstek
przy 5000 iteracjach.

## Główne wnioski zawarte w analizie

1. **Punkt przejścia**: N ≈ 80-140, poniżej którego OpenMP jest szybszy, powyżej dominuje MPI
2. **Maksymalna przewaga OpenMP**: 2.96× dla N=50
3. **Maksymalna przewaga MPI**: 7.09× dla N=380
4. **Optymalne konfiguracje**:
   - N < 100: n1c8 (czysty OpenMP)
   - 100 ≤ N < 150: n2c4 (hybrid 2×4)
   - N ≥ 150: n8c1 (czysty MPI)

## Techniczne wyjaśnienia

Analiza zawiera szczegółowe wyjaśnienia:
- Cache coherence protocol overhead w OpenMP
- False sharing problem
- Overhead komunikacji MPI międzywęzłowej
- Fragmenty kodu C z MPI+OpenMP
- Matematyczne uzasadnienie punktu przejścia

## Kompilacja

```bash
pdflatex dokument.tex
pdflatex dokument.tex  # drugi raz dla referencji
```

Jeśli używasz wykresów, może być potrzebna opcja `--shell-escape` dla niektórych kompilatorów.
