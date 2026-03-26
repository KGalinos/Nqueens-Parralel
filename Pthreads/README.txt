N-Queens with pthreads Konstantinos Galinos

Compile
    make

Run
    ./parallel <N> <num_threads>

Example
    ./parallel 15 4

Arguments
    N           - board size (1-15)
    num_threads - number of threads to use

Implementation:
    - Backtracking algorithm with recursive queen placement
    - Work divided across threads by round-robin column Assignment
      on the first row, each thread solves its subtrees independently
    - i didnt optimize it fully because it took me extra time to figure out the backtracking 
    -but the next one ill make the fastest i can
