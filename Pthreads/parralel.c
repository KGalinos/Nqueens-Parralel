#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

int canplace(int board[], int row, int col);
int placequeens(int board[], int row, int N);

typedef struct {
    int n;
    int start_cols[20];  
    int num_cols;
    int count;
} thread_args;

//checks diagonal and column no need to check for row since we place one queen per row

int canplace(int board[], int row, int col) {
    for (int i = 0; i < row; i++) {
        int diff = row - i;
        if (board[i] == col || board[i] == col - diff || board[i] == col + diff)
            return 0;
    }
    return 1;
}

//recursive fuckfest that took me too more time than i'd like to admit
int placequeens(int board[], int row, int N) {
    if (row == N) return 1;

    int count = 0;
    for (int col = 0; col < N; col++) {
        if (canplace(board, row, col)) {
            board[row] = col;
            count += placequeens(board, row + 1, N);
        }
    }
    return count;
}


void* thread_function(void* arg) {
    thread_args* args = (thread_args*)arg;
    int board[20]; //local bord for each thread bec when i had a global one it fucked me up

    for (int i = 0; i < args->num_cols; i++) {
        int col = args->start_cols[i];
        board[0] = col; 
        args->count += placequeens(board, 1, args->n);//no race condition thankfully bec args[] is not shared
    }
    return NULL;
}
//eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
int main(int argc, char* argv[]) {
    //clock_t start = clock();

    if (argc != 3) {
        fprintf(stderr, "Usage: %s <N> <num_threads>\n", argv[0]);
        return 1;
    }
    int N = atoi(argv[1]);
    int num_threads = atoi(argv[2]);
    pthread_t threads[num_threads];
    thread_args args[num_threads];

    if (N <= 0 || N > 20) {
        fprintf(stderr, "N must be between 1 and 20\n");
        return 1;
    }

    for (int t = 0; t < num_threads; t++) {
        args[t].n = N;
        args[t].num_cols = 0;
        args[t].count = 0;
    }

    for (int col = 0; col < N; col++) {
        int t = col % num_threads;
        args[t].start_cols[args[t].num_cols] = col;
        args[t].num_cols++;
    }

    for (int i = 0; i < num_threads; i++)
        pthread_create(&threads[i], NULL, thread_function, &args[i]);

    for (int t = 0; t < num_threads; t++)
        pthread_join(threads[t], NULL);

    int total_count = 0;
    for (int t = 0; t < num_threads; t++)
        total_count += args[t].count;

    printf("Solutions for N=%d: %d\n", N, total_count);
    
    
    // clock_t end = clock();
    //double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    //printf("CPU time: %.4f seconds\n", elapsed);

    return 0;
}