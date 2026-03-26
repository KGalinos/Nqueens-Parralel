# N-Queens — Parallel Implementations

Three implementations of the N-Queens problem across different parallel architectures, 
built progressively to explore performance optimization.

**120x speedup** from baseline pthreads to CUDA on the same machine.

## Implementations

| Folder | Method | Language |
|--------|--------|----------|
| `pthreads/` | CPU multithreading, one thread per column | C |
| `openmp/` | CPU parallelism with bitmask optimization and symmetry reduction | C |
| `cuda/` | GPU acceleration with shared memory backtracking | CUDA C |

## Benchmark (same machine — Ryzen 7 7735HS / RTX 4050)

| Implementation | N=15 | N=17 | N=20 |
|----------------|-------|-------|-------|
| pthreads (4 threads) | 4.45s | — | — |
| OpenMP (4 threads) | 0.90s | 42s | — |
| CUDA (RTX 4050) | 0.037s | 0.226s | 67.4s |

## Optimization Journey

**pthreads** — baseline parallelism. Simple row-per-thread dispatch, standard recursive backtracking. Readable but limited by CPU core count and naive board representation.

**OpenMP** — bitmask board representation replaces array lookups with bitwise ops. Symmetry reduction halves the search space by only exploring the left half of first-row placements and doubling the count. Dynamic scheduling handles load imbalance.

**CUDA** — pregeneration distributes partial solutions across thousands of GPU threads simultaneously. Iterative backtracking replaces recursion (GPUs handle deep recursion poorly). Shared memory stack with transposed layout eliminates bank conflicts and memory latency.

## Build

Each folder has its own Makefile or build instructions. See the README in each subfolder.

## Requirements

- pthreads: GCC + POSIX threads
- OpenMP: `gcc -fopenmp`
- CUDA: NVIDIA GPU + CUDA toolkit
