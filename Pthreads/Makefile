CC = gcc
CFLAGS = -O2 -pthread
TARGET = parallel
SRC = parralel.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)
