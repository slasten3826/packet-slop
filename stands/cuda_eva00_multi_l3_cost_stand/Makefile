CUDA_TARGET := eva00_multi_l3_gpu

NVCC ?= /opt/cuda/bin/nvcc
CCBIN ?= /usr/bin/g++-14
CFLAGS := -O2 -std=c++17

all: $(CUDA_TARGET)

$(CUDA_TARGET): main.cu
	$(NVCC) $(CFLAGS) -ccbin $(CCBIN) -o $(CUDA_TARGET) main.cu

run: $(CUDA_TARGET)
	./$(CUDA_TARGET)

clean:
	rm -f $(CUDA_TARGET)
