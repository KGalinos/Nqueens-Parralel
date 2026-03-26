NVCC = nvcc
CFLAGS = -O3 -arch=sm_89

TARGET = nqueens_cuda
SRC = nqueens_cuda.cu

all: $(TARGET)

$(TARGET): $(SRC)
	$(NVCC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)