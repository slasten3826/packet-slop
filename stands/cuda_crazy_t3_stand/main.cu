#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <string>
#include <vector>
#include <unordered_set>
#include <cuda_runtime.h>

static constexpr int MOD = 59049;

static void check_cuda(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        std::fprintf(stderr, "cuda error at %s: %s\n", what, cudaGetErrorString(err));
        std::exit(1);
    }
}

__host__ __device__ static int crazy(int a, int d) {
    static const int table3[3][3] = {
        {1, 0, 0},
        {1, 0, 2},
        {2, 2, 1},
    };

    int result = 0;
    int power = 1;
    int aa = a;
    int dd = d;

    for (int i = 0; i < 10; ++i) {
        const int ax = aa % 3;
        const int dx = dd % 3;
        result += table3[dx][ax] * power;
        aa /= 3;
        dd /= 3;
        power *= 3;
    }

    return result % MOD;
}

struct State {
    int ring_size;
    int trace_count;
    std::vector<int> core;
    std::vector<int> phase;
    std::vector<std::vector<int>> traces;
    std::vector<int> carries;
    std::vector<int> positions;
};

static void seed_ring(State& state, int seed) {
    state.core.resize(state.ring_size);
    state.phase.resize(state.ring_size);
    state.traces.assign(state.trace_count, std::vector<int>(state.ring_size, 0));
    state.carries.resize(state.trace_count);
    state.positions.resize(state.trace_count);

    for (int i = 0; i < state.ring_size; ++i) {
        state.phase[i] = i % 3;
    }

    state.core[0] = seed % MOD;
    state.core[1] = crazy(state.core[0], seed % MOD);
    for (int i = 2; i < state.ring_size; ++i) {
        state.core[i] = crazy(state.core[i - 2], state.core[i - 1]);
    }

    for (int t = 0; t < state.trace_count; ++t) {
        state.positions[t] = ((state.ring_size * t) / state.trace_count) % state.ring_size;
        if (t == 0) {
            state.carries[t] = seed % MOD;
        } else {
            state.carries[t] = crazy(seed % MOD, t);
        }
        for (int i = 0; i < state.ring_size; ++i) {
            state.traces[t][i] = crazy(state.core[i], (state.phase[i] + t) % 3);
        }
    }
}

static void tick_multi(State& state) {
    const bool exact_t3 = state.trace_count == 3;

    for (int idx = 0; idx < state.trace_count; ++idx) {
        const int p = state.positions[idx];
        const int q = (p + 1) % state.ring_size;

        const int bias = exact_t3
            ? crazy(state.phase[p], p % MOD)
            : crazy(state.phase[p], (p + idx + 1) % MOD);
        const int operand = crazy(crazy(state.core[p], state.traces[idx][p]), bias);
        const int res = crazy(state.carries[idx], operand);

        state.carries[idx] = res;
        state.core[p] = crazy(res, state.traces[idx][p]);
        state.traces[idx][p] = crazy(state.traces[idx][p], bias);
        state.positions[idx] = q;
    }
}

static int merged_trace_value(const State& state, int index) {
    int acc = state.traces[0][index];
    for (int t = 1; t < state.trace_count; ++t) {
        acc = crazy(acc, state.traces[t][index]);
    }
    return acc;
}

static int merged_carry(const State& state) {
    int acc = state.carries[0];
    for (int t = 1; t < state.trace_count; ++t) {
        acc = crazy(acc, state.carries[t]);
    }
    return acc;
}

static int fingerprint(const State& state) {
    const int pos = state.positions[0];
    int h = merged_carry(state) % MOD;
    h = crazy(h, state.core[pos]);
    h = crazy(h, merged_trace_value(state, pos));
    h = crazy(h, pos);
    return h;
}

static int distinct_core(const State& state) {
    std::unordered_set<int> seen;
    for (int value : state.core) {
        seen.insert(value);
    }
    return static_cast<int>(seen.size());
}

static int distinct_trace(const State& state) {
    std::unordered_set<int> seen;
    for (int i = 0; i < state.ring_size; ++i) {
        seen.insert(merged_trace_value(state, i));
    }
    return static_cast<int>(seen.size());
}

static int trace_density(const State& state) {
    int active = 0;
    for (int i = 0; i < state.ring_size; ++i) {
        if (merged_trace_value(state, i) != 0) {
            active += 1;
        }
    }
    return active;
}

__global__ static void tick_multi_kernel(
    int* core,
    const int* phase,
    int* traces,
    int* carries,
    int* positions,
    int ring_size,
    int trace_count
) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= trace_count) {
        return;
    }

    const bool exact_t3 = trace_count == 3;
    const int p = positions[idx];
    const int q = (p + 1) % ring_size;
    const int trace_offset = idx * ring_size + p;

    const int bias = exact_t3
        ? crazy(phase[p], p % MOD)
        : crazy(phase[p], (p + idx + 1) % MOD);
    const int operand = crazy(crazy(core[p], traces[trace_offset]), bias);
    const int res = crazy(carries[idx], operand);

    carries[idx] = res;
    core[p] = crazy(res, traces[trace_offset]);
    traces[trace_offset] = crazy(traces[trace_offset], bias);
    positions[idx] = q;
}

static void copy_device_to_state(
    State& state,
    const int* d_core,
    const int* d_phase,
    const int* d_traces,
    const int* d_carries,
    const int* d_positions
) {
    check_cuda(cudaMemcpy(state.core.data(), d_core, sizeof(int) * state.ring_size, cudaMemcpyDeviceToHost), "copy core d2h");
    check_cuda(cudaMemcpy(state.phase.data(), d_phase, sizeof(int) * state.ring_size, cudaMemcpyDeviceToHost), "copy phase d2h");
    check_cuda(cudaMemcpy(state.carries.data(), d_carries, sizeof(int) * state.trace_count, cudaMemcpyDeviceToHost), "copy carries d2h");
    check_cuda(cudaMemcpy(state.positions.data(), d_positions, sizeof(int) * state.trace_count, cudaMemcpyDeviceToHost), "copy positions d2h");

    std::vector<int> flat_traces(state.trace_count * state.ring_size, 0);
    check_cuda(cudaMemcpy(flat_traces.data(), d_traces, sizeof(int) * flat_traces.size(), cudaMemcpyDeviceToHost), "copy traces d2h");
    for (int t = 0; t < state.trace_count; ++t) {
        for (int i = 0; i < state.ring_size; ++i) {
            state.traces[t][i] = flat_traces[t * state.ring_size + i];
        }
    }
}

static long long run_gpu(State& state, int ticks, bool quiet) {
    int* d_core = nullptr;
    int* d_phase = nullptr;
    int* d_traces = nullptr;
    int* d_carries = nullptr;
    int* d_positions = nullptr;

    const size_t core_bytes = sizeof(int) * state.ring_size;
    const size_t phase_bytes = sizeof(int) * state.ring_size;
    const size_t traces_bytes = sizeof(int) * state.trace_count * state.ring_size;
    const size_t carries_bytes = sizeof(int) * state.trace_count;
    const size_t positions_bytes = sizeof(int) * state.trace_count;

    std::vector<int> flat_traces(state.trace_count * state.ring_size, 0);
    for (int t = 0; t < state.trace_count; ++t) {
        for (int i = 0; i < state.ring_size; ++i) {
            flat_traces[t * state.ring_size + i] = state.traces[t][i];
        }
    }

    check_cuda(cudaMalloc(&d_core, core_bytes), "malloc core");
    check_cuda(cudaMalloc(&d_phase, phase_bytes), "malloc phase");
    check_cuda(cudaMalloc(&d_traces, traces_bytes), "malloc traces");
    check_cuda(cudaMalloc(&d_carries, carries_bytes), "malloc carries");
    check_cuda(cudaMalloc(&d_positions, positions_bytes), "malloc positions");

    check_cuda(cudaMemcpy(d_core, state.core.data(), core_bytes, cudaMemcpyHostToDevice), "copy core h2d");
    check_cuda(cudaMemcpy(d_phase, state.phase.data(), phase_bytes, cudaMemcpyHostToDevice), "copy phase h2d");
    check_cuda(cudaMemcpy(d_traces, flat_traces.data(), traces_bytes, cudaMemcpyHostToDevice), "copy traces h2d");
    check_cuda(cudaMemcpy(d_carries, state.carries.data(), carries_bytes, cudaMemcpyHostToDevice), "copy carries h2d");
    check_cuda(cudaMemcpy(d_positions, state.positions.data(), positions_bytes, cudaMemcpyHostToDevice), "copy positions h2d");

    cudaEvent_t start, stop;
    check_cuda(cudaEventCreate(&start), "event create start");
    check_cuda(cudaEventCreate(&stop), "event create stop");
    check_cuda(cudaEventRecord(start), "event record start");

    const int threads = 256;
    const int blocks = (state.trace_count + threads - 1) / threads;

    for (int t = 1; t <= ticks; ++t) {
        tick_multi_kernel<<<blocks, threads>>>(
            d_core,
            d_phase,
            d_traces,
            d_carries,
            d_positions,
            state.ring_size,
            state.trace_count
        );
        check_cuda(cudaGetLastError(), "kernel launch");

        if (!quiet && (t == 1 || t % state.ring_size == 0 || t == ticks)) {
            check_cuda(cudaDeviceSynchronize(), "checkpoint sync");
            copy_device_to_state(state, d_core, d_phase, d_traces, d_carries, d_positions);
            std::printf(
                "tick=%d pos=%d carry=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d\n",
                t,
                state.positions[0] + 1,
                merged_carry(state),
                fingerprint(state),
                trace_density(state),
                distinct_core(state),
                distinct_trace(state)
            );
        }
    }

    check_cuda(cudaEventRecord(stop), "event record stop");
    check_cuda(cudaEventSynchronize(stop), "event sync stop");

    float elapsed_ms = 0.0f;
    check_cuda(cudaEventElapsedTime(&elapsed_ms, start, stop), "event elapsed");
    check_cuda(cudaDeviceSynchronize(), "final sync");
    copy_device_to_state(state, d_core, d_phase, d_traces, d_carries, d_positions);

    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    cudaFree(d_core);
    cudaFree(d_phase);
    cudaFree(d_traces);
    cudaFree(d_carries);
    cudaFree(d_positions);

    return static_cast<long long>(elapsed_ms * 1000.0f);
}

int main(int argc, char** argv) {
    const int ring_size = argc > 1 ? std::atoi(argv[1]) : 128;
    const int ticks = argc > 2 ? std::atoi(argv[2]) : 1024;
    const int seed = argc > 3 ? std::atoi(argv[3]) : 12345;
    const int trace_count = argc > 4 ? std::atoi(argv[4]) : 3;
    const bool quiet = argc > 5 ? std::atoi(argv[5]) != 0 : false;
    const bool use_gpu = argc > 6 ? std::atoi(argv[6]) != 0 : false;

    if (ring_size < 3 || ticks < 1 || trace_count < 1) {
        std::fprintf(stderr, "usage: ./crazy_t3 [ring_size] [ticks] [seed] [trace_count] [quiet] [use_gpu]\n");
        return 1;
    }

    State state{ring_size, trace_count};
    seed_ring(state, seed);

    if (!quiet) {
        std::printf("cuda crazy torus stand\n");
        std::printf("ring_size=%d ticks=%d seed=%d trace_count=%d use_gpu=%d\n", ring_size, ticks, seed, trace_count, use_gpu ? 1 : 0);
    }

    long long elapsed_us = 0;

    if (use_gpu) {
        elapsed_us = run_gpu(state, ticks, quiet);
    } else {
        const auto start = std::chrono::steady_clock::now();

        for (int t = 1; t <= ticks; ++t) {
            tick_multi(state);

            if (!quiet && (t == 1 || t % ring_size == 0 || t == ticks)) {
                std::printf(
                    "tick=%d pos=%d carry=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d\n",
                    t,
                    state.positions[0] + 1,
                    merged_carry(state),
                    fingerprint(state),
                    trace_density(state),
                    distinct_core(state),
                    distinct_trace(state)
                );
            }
        }

        const auto stop = std::chrono::steady_clock::now();
        elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(stop - start).count();
    }

    if (quiet) {
        std::printf(
            "ring=%d,ticks=%d,seed=%d,traces=%d,elapsed_us=%lld,carry=%d,fp=%d,trace_density=%d,distinct_core=%d,distinct_trace=%d\n",
            ring_size,
            ticks,
            seed,
            trace_count,
            static_cast<long long>(elapsed_us),
            merged_carry(state),
            fingerprint(state),
            trace_density(state),
            distinct_core(state),
            distinct_trace(state)
        );
        return 0;
    }

    std::printf("elapsed_us=%lld\n", static_cast<long long>(elapsed_us));

    std::printf("core_preview=");
    for (int i = 0; i < ring_size && i < 12; ++i) {
        if (i) std::printf(",");
        std::printf("%d", state.core[i]);
    }
    std::printf("\n");

    return 0;
}
