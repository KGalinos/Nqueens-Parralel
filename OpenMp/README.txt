HY342 - Parallel Programming 
Assignment 1 - N-Queens with pthreads 5582 Konstantinos Galinos

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
    - i didnt optimize it fully for the competition because it took me extra time to figure out the backtracking 
      and the logic
    -but the next one ill make the fastest i can