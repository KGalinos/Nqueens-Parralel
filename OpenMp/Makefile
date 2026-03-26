CC = gcc
CFLAGS = -O3 -march=native -fopenmp
TARGET = OnpNqueens

all: $(TARGET)

$(TARGET): OnpNqueens.c
	$(CC) $(CFLAGS) -o $(TARGET) OnpNqueens.c

clean:
	rm -f $(TARGET)