#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>

/*
 * KEY CHANGE: stack arrays moved to __shared__ memory.
 *
 * Memory hierarchy on RTX 4050:
 *   Registers:      ~1  cycle  (best, but limited — ~65K regs per SM)
 *   Shared memory:  ~4  cycles (on-chip SRAM, 48KB per SM)
 *   L1 cache:       ~30 cycles
 *   Local memory:   ~500 cycles (physically global memory, thread-private)
 *   Global memory:  ~500 cycles
 *
 * Variable-indexed arrays like s_avail[depth] where depth is a runtime
 * value CANNOT be kept in registers — the compiler has no choice but to
 * put them in local memory. That's why all our previous fixes failed:
 * every stack access was paying 500 cycle penalty regardless of MAX_DEPTH.
 *
 * Solution: declare the stack in __shared__ memory instead.
 * Shared memory is indexed as [threadIdx.x][depth] — each thread owns
 * its own column, and accesses stay on-chip at ~4 cycles.
 *
 * Shared memory budget per block:
 *   4 arrays × MAX_DEPTH × THREADS_BLOCK × 4 bytes
 *   = 4 × 14 × 128 × 4 = 28,672 bytes = 28KB
 *   RTX 4050 has 48KB shared/SM → fits with room to spare ✓
 */

#define THREADS_BLOCK 64
#define MAX_DEPTH     14    /* max remaining rows = n - pregen_depth
                            //  n=20, depth=6 → 14. Increase if needed. */

#define CUDA_CHECK(call)                                          \
    do {                                                          \
        cudaError_t _e = (call);                                  \
        if (_e != cudaSuccess) {                                  \
            fprintf(stderr, "CUDA error line %d: %s\n",          \
                    __LINE__, cudaGetErrorString(_e));            \
            exit(1);                                              \
        }                                                         \
    } while (0)

__launch_bounds__(THREADS_BLOCK)
__global__ void queens_kernel(
    const int *cols_arr, const int *ld_arr,
    const int *rd_arr,   const int *mult_arr,
    int np, int n, int start_row, long long *results)
{
    /* Stack in shared memory — on-chip, ~4 cycle access */
    /* Transposed layout [depth][tid] eliminates bank conflicts.
     * Warp accesses sh_cols[depth][0..31] = consecutive addresses = bank 0..31
     * Old layout sh_cols[0..31][depth] = strided by MAX_DEPTH = many conflicts */
    __shared__ int sh_cols [MAX_DEPTH][THREADS_BLOCK];
    __shared__ int sh_ld   [MAX_DEPTH][THREADS_BLOCK];
    __shared__ int sh_rd   [MAX_DEPTH][THREADS_BLOCK];
    __shared__ int sh_avail[MAX_DEPTH][THREADS_BLOCK];

    int i   = blockIdx.x * blockDim.x + threadIdx.x;
    int tid = threadIdx.x;

    if (i >= np) return;

    int full_mask = (1 << n) - 1;
    int init_cols = cols_arr[i];
    int init_ld   = ld_arr[i];
    int init_rd   = rd_arr[i];

    long long count = 0;
    int depth = 0;

    sh_cols [0][tid] = init_cols;
    sh_ld   [0][tid] = init_ld;
    sh_rd   [0][tid] = init_rd;
    sh_avail[0][tid] = full_mask & ~(init_cols | init_ld | init_rd);

    while (depth >= 0) {
        int avail = sh_avail[depth][tid];

        if (avail == 0) { depth--; continue; }

        int pos = avail & (-avail);
        sh_avail[depth][tid] = avail & (avail - 1);

        int row = start_row + depth;
        if (row == n - 1) { count++; continue; }

        int nc = sh_cols[depth][tid] | pos;
        int nl = (sh_ld  [depth][tid] | pos) >> 1;
        int nr = (sh_rd  [depth][tid] | pos) << 1;
        depth++;
        sh_cols [depth][tid] = nc;
        sh_ld   [depth][tid] = nl;
        sh_rd   [depth][tid] = nr;
        sh_avail[depth][tid] = full_mask & ~(nc | nl | nr);
    }

    results[i] = count * (long long)mult_arr[i];
}

/* ── Partial list ─────────────────────────────────────────────────── */
typedef struct { int *cols,*ld,*rd,*mult,count,capacity; } PL;

static void pl_init(PL *pl, int cap) {
    pl->cols=(int*)malloc(cap*4); pl->ld=(int*)malloc(cap*4);
    pl->rd  =(int*)malloc(cap*4); pl->mult=(int*)malloc(cap*4);
    pl->count=0; pl->capacity=cap;
}
static void pl_free(PL *pl){free(pl->cols);free(pl->ld);free(pl->rd);free(pl->mult);}
static void pl_add(PL *pl, int cols, int ld, int rd, int mult) {
    if (pl->count==pl->capacity) {
        pl->capacity*=2;
        pl->cols=(int*)realloc(pl->cols,pl->capacity*4);
        pl->ld  =(int*)realloc(pl->ld,  pl->capacity*4);
        pl->rd  =(int*)realloc(pl->rd,  pl->capacity*4);
        pl->mult=(int*)realloc(pl->mult,pl->capacity*4);
    }
    int i=pl->count++;
    pl->cols[i]=cols; pl->ld[i]=ld; pl->rd[i]=rd; pl->mult[i]=mult;
}

static int g_N, g_FULL_MASK, g_DEPTH;

static void gen(PL *pl, int row, int cols, int ld, int rd, int mult) {
    if (row==g_DEPTH) { pl_add(pl,cols,ld,rd,mult); return; }
    int available = g_FULL_MASK & ~(cols|ld|rd);
    if (row==0) {
        for (int c=0; c<=g_N/2; c++) {
            if (g_N%2==0 && c==g_N/2) break;
            int pos=1<<c;
            if (!(available&pos)) continue;
            gen(pl,1,pos,pos>>1,pos<<1,(c<g_N/2)?2:1);
        }
    } else {
        while (available) {
            int pos=available&(-available); available&=available-1;
            gen(pl,row+1,cols|pos,(ld|pos)>>1,(rd|pos)<<1,mult);
        }
    }
}

static int choose_depth(int n) {
    if (n <= 12) return 4;
    if (n <= 15) return 5;
    return 6;   /* n=16-22: remaining rows = n-6 ≤ 16 ≤ MAX_DEPTH */
}

int main(void) {
    int n;
    printf("Enter n: ");
    scanf("%d", &n);
    if (n<1||n>20){printf("n must be 1-20\n");return 1;}

    g_N=n; g_FULL_MASK=(1<<n)-1;
    g_DEPTH=choose_depth(n);

    int remaining = n - g_DEPTH;
    if (remaining > MAX_DEPTH) {
        fprintf(stderr,"Error: remaining=%d > MAX_DEPTH=%d. Increase MAX_DEPTH.\n",
                remaining, MAX_DEPTH);
        return 1;
    }

    long long cap=1;
    for(int i=0;i<g_DEPTH;i++) cap*=n;
    cap=cap/2+64;
    if(cap>4000000) cap=4000000;

    PL pl; pl_init(&pl,(int)cap);
    gen(&pl,0,0,0,0,0);
    int np=pl.count;

    /* Shared memory per block */
    int smem_bytes = 4 * MAX_DEPTH * THREADS_BLOCK * 4;
    printf("Partials: %d  depth: %d  remaining rows/thread: %d\n",
           np, g_DEPTH, remaining);
    printf("Shared mem/block: %d KB (limit: 48 KB)\n", smem_bytes/1024);

    int *d_cols,*d_ld,*d_rd,*d_mult; long long *d_results;
    long long *h_results=(long long*)malloc(np*sizeof(long long));

    CUDA_CHECK(cudaMalloc(&d_cols,   np*4));
    CUDA_CHECK(cudaMalloc(&d_ld,     np*4));
    CUDA_CHECK(cudaMalloc(&d_rd,     np*4));
    CUDA_CHECK(cudaMalloc(&d_mult,   np*4));
    CUDA_CHECK(cudaMalloc(&d_results,np*8));

    CUDA_CHECK(cudaMemcpy(d_cols,pl.cols,np*4,cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_ld,  pl.ld,  np*4,cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_rd,  pl.rd,  np*4,cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_mult,pl.mult,np*4,cudaMemcpyHostToDevice));

    int blocks=(np+THREADS_BLOCK-1)/THREADS_BLOCK;
    printf("Blocks: %d  threads/block: %d\n", blocks, THREADS_BLOCK);

    cudaEvent_t t0,t1;
    CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
    CUDA_CHECK(cudaEventRecord(t0));

    queens_kernel<<<blocks,THREADS_BLOCK>>>(
        d_cols,d_ld,d_rd,d_mult,np,n,g_DEPTH,d_results);

    CUDA_CHECK(cudaEventRecord(t1));
    CUDA_CHECK(cudaEventSynchronize(t1));
    CUDA_CHECK(cudaGetLastError());

    float gpu_ms;
    CUDA_CHECK(cudaEventElapsedTime(&gpu_ms,t0,t1));

    CUDA_CHECK(cudaMemcpy(h_results,d_results,np*8,cudaMemcpyDeviceToHost));

    long long total=0;
    for(int i=0;i<np;i++) total+=h_results[i];

    printf("N = %d  ->  %lld solutions\n", n, total);
    printf("GPU time: %.1f ms\n", gpu_ms);

    cudaFree(d_cols);cudaFree(d_ld);cudaFree(d_rd);
    cudaFree(d_mult);cudaFree(d_results);
    free(h_results); pl_free(&pl);
    return 0;
}
