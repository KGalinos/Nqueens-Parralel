#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

//Recursive solver using bitmasks
static long long solve(int row, int cols, int ld, int rd, int N, int FULL_MASK)
{
    if (row == N) return 1;

    long long count = 0;
    int available = FULL_MASK & ~(cols | ld | rd);

    while (available) {
        int pos = available & (-available);
        available &= available - 1;
        count += solve(row + 1, cols | pos, (ld | pos) >> 1, (rd | pos) << 1, N, FULL_MASK);
    }
    return count;
}

typedef struct {
    int cols, ld, rd, mirror;
} Partial;

int main(int argc, char *argv[])
{
    if (argc < 3) {
        printf("Usage: %s <N> <threads>\n", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]);
    int requested_threads = atoi(argv[2]);
    int FULL_MASK = (1 << N) - 1;

    //Set thread count as per OpenMP runtime routines mentioned in slides
    omp_set_num_threads(requested_threads);

    //Task Decomposition: Generate work pool (first 2 rows)
    int max_partials = (N / 2 + 1) * N;
    Partial *partials = malloc(max_partials * sizeof(Partial));
    int np = 0;

    for (int c0 = 0; c0 <= N / 2; c0++) {
        if (N % 2 == 0 && c0 == N / 2) break;
        int mirror = (N % 2 != 0 && c0 == N / 2) ? 0 : 1;

        int pos0  = 1 << c0;
        int avail1 = FULL_MASK & ~(pos0 | (pos0 >> 1) | (pos0 << 1));
        
        while (avail1) {
            int pos1 = avail1 & (-avail1);
            avail1 &= avail1 - 1;
            partials[np].cols   = pos0 | pos1;
            partials[np].ld     = ((pos0 >> 1) | pos1) >> 1;
            partials[np].rd     = ((pos0 << 1) | pos1) << 1;
            partials[np].mirror = mirror;
            np++;
        }
    }

    long long total = 0;
    int i; 

    //Parallel Region with explicit data scoping (default(none))
    #pragma omp parallel for \
        default(none) \
        shared(np, partials, N, FULL_MASK) \
        private(i) \
        reduction(+:total) \
        schedule(dynamic)
    for (i = 0; i < np; i++) {
        long long s = solve(2, partials[i].cols, partials[i].ld, partials[i].rd, N, FULL_MASK);
        total += (partials[i].mirror) ? (s * 2) : s;
    }

    printf("N=%d | Threads=%d | Solutions=%lld\n", N, requested_threads, total);

    free(partials);
    return 0;
}