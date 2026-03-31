#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

static void check_cuda(cudaError_t err, const char* what) {
    if (err != cudaSuccess) {
        std::fprintf(stderr, "cuda error at %s: %s\n", what, cudaGetErrorString(err));
        std::exit(1);
    }
}

enum Kind : int {
    OBSERVE = 0,
    CHOOSE = 1,
    ENCODE = 2,
    RUNTIME = 3,
};

struct Metrics {
    int collapse = 0;
    int encode = 0;
    int runtime_hits = 0;
    int calm = 0;
    int pending = 0;
    int active_nodes = 0;
    int pu_spent[4] = {0, 0, 0, 0};
};

static int wrap_host(int v, int n) {
    return (v % n + n) % n;
}

static int kind_for_position(int x, int y) {
    int phase = (x + 2 * y) % 4;
    if (phase == 0) return OBSERVE;
    if (phase == 1) return CHOOSE;
    if (phase == 2) return ENCODE;
    return RUNTIME;
}

static void derive_l2_shape(int l1_ring, int l1_cw, int& width, int& height) {
    double base = std::max(8.0, std::floor(std::sqrt((double)l1_ring) / 2.0));
    double pressure_factor = 1.0 + std::log2((double)std::max(1, l1_cw)) / 8.0;
    width = std::max(12, (int)std::floor(base * pressure_factor));
    height = std::max(10, (int)std::floor(width * 0.85));
}

static int derive_pu_capacity(int width, int height) {
    return width * height;
}

static float derive_l1_gain(int l1_cw) {
    return 0.22f + std::log2((float)std::max(1, l1_cw)) * 0.015f;
}

static float derive_l3_feedback_ceiling(int l1_ring, int l1_cw) {
    float ring_term = std::log2((float)std::max(1, l1_ring)) * 0.004f;
    float cw_term = std::log2((float)std::max(1, l1_cw)) * 0.006f;
    return 0.08f + ring_term + cw_term;
}

static unsigned int lcg_step(unsigned int& state) {
    state = state * 1664525u + 1013904223u;
    return state;
}

static float randf(unsigned int& state) {
    return (lcg_step(state) & 0x00ffffff) / (float)0x01000000;
}

static float hash_noise_host(int x, int y, int tick, int seed) {
    unsigned int v = (unsigned int)(x * 92821 + y * 68917 + tick * 1237 + seed * 17);
    v ^= v << 13;
    v ^= v >> 17;
    v ^= v << 5;
    return (v % 1000) / 1000.0f;
}

__device__ int wrap_dev(int v, int n) {
    int r = v % n;
    return r < 0 ? r + n : r;
}

__device__ float clamp_dev(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

__device__ float hash_noise_dev(int x, int y, int tick, int seed) {
    unsigned int v = (unsigned int)(x * 92821 + y * 68917 + tick * 1237 + seed * 17);
    v ^= v << 13;
    v ^= v >> 17;
    v ^= v << 5;
    return (v % 1000) / 1000.0f;
}

__device__ int neighbor_index(int x, int y, int dir, int width, int height) {
    bool even = (y % 2 == 0);
    int nx = x;
    int ny = y;
    if (dir == 0) {
        nx = wrap_dev(x + 1, width);
    } else if (dir == 1) {
        nx = wrap_dev(x - 1, width);
    } else if (dir == 2) {
        nx = wrap_dev(x + (even ? 1 : 0), width);
        ny = wrap_dev(y - 1, height);
    } else if (dir == 3) {
        nx = wrap_dev(x + (even ? 0 : -1), width);
        ny = wrap_dev(y - 1, height);
    } else if (dir == 4) {
        nx = wrap_dev(x + (even ? 1 : 0), width);
        ny = wrap_dev(y + 1, height);
    } else {
        nx = wrap_dev(x + (even ? 0 : -1), width);
        ny = wrap_dev(y + 1, height);
    }
    return ny * width + nx;
}

__global__ void tick_l2_kernel(
    const int* kinds,
    const float* activation,
    float* next_activation,
    int* stability,
    const float* threshold,
    const float* decay,
    const float* bias,
    const float* weights,
    int width,
    int height,
    int tick,
    int seed,
    float l1_gain,
    float l3_feedback_ceiling,
    Metrics* metrics
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total = width * height;
    if (idx >= total) return;

    int y = idx / width;
    int x = idx % width;
    int kind = kinds[idx];

    float neigh = 0.0f;
    for (int dir = 0; dir < 6; ++dir) {
        int nidx = neighbor_index(x, y, dir, width, height);
        neigh += activation[nidx] * weights[idx * 6 + dir];
    }
    neigh /= 6.0f;

    float from_l1 = 0.0f;
    if (kind != RUNTIME) {
        float depth = 1.0f - (y / fmaxf(1.0f, (float)(height - 1)));
        float n = hash_noise_dev(x + 1, y + 1, tick, seed);
        float spike = 0.0f;
        if (n > 0.86f) spike = (n - 0.86f) * 1.8f;
        from_l1 = depth * l1_gain + spike;
    }

    float from_l3 = 0.0f;
    if (kind == RUNTIME) {
        float topness = y / fmaxf(1.0f, (float)(height - 1));
        from_l3 = topness * fminf(l3_feedback_ceiling, metrics->calm / 4000.0f);
    }

    float raw = activation[idx] * decay[idx] + neigh + from_l1 + from_l3 + bias[idx];
    float next = raw;
    bool engaged = raw > (threshold[idx] * 0.45f) || activation[idx] > 0.05f || fabsf(from_l1) > 0.02f || fabsf(from_l3) > 0.01f;

    if (engaged) {
        const int base_costs[4] = {1, 2, 3, 2};
        atomicAdd(&metrics->pu_spent[kind], base_costs[kind]);
        atomicAdd(&metrics->active_nodes, 1);
    }

    if (kind == OBSERVE) {
        next = raw * 0.90f;
    } else if (kind == CHOOSE) {
        float sharpen = raw - fmaxf(0.0f, neigh * 0.45f);
        next = sharpen;
        if (sharpen > threshold[idx]) atomicAdd(&metrics->collapse, 1);
    } else if (kind == ENCODE) {
        int st = stability[idx];
        if (raw > threshold[idx]) st += 1;
        else st = st > 0 ? st - 1 : 0;
        stability[idx] = st;
        if (st >= 3 && raw > (threshold[idx] + 0.05f)) {
            atomicAdd(&metrics->encode, 1);
            atomicAdd(&metrics->pending, 1);
            atomicAdd(&metrics->pu_spent[ENCODE], 4);
            stability[idx] = 1;
            next = raw * 0.66f;
        }
    } else if (kind == RUNTIME) {
        int pending_before = atomicAdd(&metrics->pending, 0);
        float gain = fminf(0.15f, pending_before * 0.015f);
        next = raw + gain;
        if (pending_before > 0 && raw > threshold[idx]) {
            int old = atomicSub(&metrics->pending, 1);
            if (old > 0) {
                atomicAdd(&metrics->runtime_hits, 1);
                atomicAdd(&metrics->pu_spent[RUNTIME], 3);
                atomicAdd(&metrics->calm, 4 + (int)floorf(raw * 6.0f));
                next = raw * 0.60f;
            } else {
                atomicAdd(&metrics->pending, 1);
            }
        }
    }

    next_activation[idx] = clamp_dev(next, 0.0f, 1.0f);
}

__global__ void commit_l2_kernel(float* activation, const float* next_activation, int total) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    activation[idx] = next_activation[idx];
}

int main(int argc, char** argv) {
    int l1_ring = argc > 1 ? std::atoi(argv[1]) : 4096;
    int l1_cw = argc > 2 ? std::atoi(argv[2]) : 256;
    int ticks = argc > 3 ? std::atoi(argv[3]) : 160;
    int seed = argc > 4 ? std::atoi(argv[4]) : 12345;

    int width = 0, height = 0;
    derive_l2_shape(l1_ring, l1_cw, width, height);
    int total = width * height;
    int pu_capacity = derive_pu_capacity(width, height);
    int pu_cycle_budget = pu_capacity * 24;
    float l1_gain = derive_l1_gain(l1_cw);
    float l3_feedback_ceiling = derive_l3_feedback_ceiling(l1_ring, l1_cw);

    std::vector<int> h_kinds(total);
    std::vector<float> h_activation(total, 0.0f);
    std::vector<float> h_next(total, 0.0f);
    std::vector<int> h_stability(total, 0);
    std::vector<float> h_threshold(total);
    std::vector<float> h_decay(total);
    std::vector<float> h_bias(total);
    std::vector<float> h_weights(total * 6);

    unsigned int rng = (unsigned int)seed;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int idx = y * width + x;
            int kind = kind_for_position(x, y);
            h_kinds[idx] = kind;
            h_threshold[idx] = kind == OBSERVE ? 0.30f : kind == CHOOSE ? 0.50f : kind == ENCODE ? 0.62f : 0.42f;
            h_decay[idx] = kind == OBSERVE ? 0.84f : kind == CHOOSE ? 0.79f : kind == ENCODE ? 0.86f : 0.90f;
            h_bias[idx] = kind == OBSERVE ? 0.01f : kind == RUNTIME ? 0.02f : 0.0f;
            for (int dir = 0; dir < 6; ++dir) {
                h_weights[idx * 6 + dir] = 0.12f + randf(rng) * 0.48f;
            }
        }
    }

    int* d_kinds = nullptr;
    float* d_activation = nullptr;
    float* d_next = nullptr;
    int* d_stability = nullptr;
    float* d_threshold = nullptr;
    float* d_decay = nullptr;
    float* d_bias = nullptr;
    float* d_weights = nullptr;
    Metrics* d_metrics = nullptr;

    check_cuda(cudaMalloc(&d_kinds, sizeof(int) * total), "malloc kinds");
    check_cuda(cudaMalloc(&d_activation, sizeof(float) * total), "malloc activation");
    check_cuda(cudaMalloc(&d_next, sizeof(float) * total), "malloc next");
    check_cuda(cudaMalloc(&d_stability, sizeof(int) * total), "malloc stability");
    check_cuda(cudaMalloc(&d_threshold, sizeof(float) * total), "malloc threshold");
    check_cuda(cudaMalloc(&d_decay, sizeof(float) * total), "malloc decay");
    check_cuda(cudaMalloc(&d_bias, sizeof(float) * total), "malloc bias");
    check_cuda(cudaMalloc(&d_weights, sizeof(float) * total * 6), "malloc weights");
    check_cuda(cudaMalloc(&d_metrics, sizeof(Metrics)), "malloc metrics");

    check_cuda(cudaMemcpy(d_kinds, h_kinds.data(), sizeof(int) * total, cudaMemcpyHostToDevice), "copy kinds");
    check_cuda(cudaMemcpy(d_activation, h_activation.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy activation");
    check_cuda(cudaMemcpy(d_next, h_next.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy next");
    check_cuda(cudaMemcpy(d_stability, h_stability.data(), sizeof(int) * total, cudaMemcpyHostToDevice), "copy stability");
    check_cuda(cudaMemcpy(d_threshold, h_threshold.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy threshold");
    check_cuda(cudaMemcpy(d_decay, h_decay.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy decay");
    check_cuda(cudaMemcpy(d_bias, h_bias.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy bias");
    check_cuda(cudaMemcpy(d_weights, h_weights.data(), sizeof(float) * total * 6, cudaMemcpyHostToDevice), "copy weights");

    Metrics metrics;
    int threads = 256;
    int blocks = (total + threads - 1) / threads;
    int pu_spent_cumulative = 0;

    std::printf("cuda l2 neural stand\n");
    std::printf("l1_ring=%d l1_cw=%d -> l2=%dx%d pu_capacity=%d pu_cycle_budget=%d ticks=%d seed=%d\n", l1_ring, l1_cw, width, height, pu_capacity, pu_cycle_budget, ticks, seed);

    for (int tick = 1; tick <= ticks; ++tick) {
        check_cuda(cudaMemset(d_metrics, 0, sizeof(Metrics)), "memset metrics");
        tick_l2_kernel<<<blocks, threads>>>(
            d_kinds, d_activation, d_next, d_stability, d_threshold, d_decay, d_bias, d_weights,
            width, height, tick, seed, l1_gain, l3_feedback_ceiling, d_metrics
        );
        check_cuda(cudaGetLastError(), "tick_l2 kernel");
        commit_l2_kernel<<<blocks, threads>>>(d_activation, d_next, total);
        check_cuda(cudaGetLastError(), "commit_l2 kernel");
        check_cuda(cudaDeviceSynchronize(), "tick sync");

        check_cuda(cudaMemcpy(&metrics, d_metrics, sizeof(Metrics), cudaMemcpyDeviceToHost), "copy metrics");
        int pu_spent_tick = metrics.pu_spent[0] + metrics.pu_spent[1] + metrics.pu_spent[2] + metrics.pu_spent[3];
        pu_spent_cumulative += pu_spent_tick;

        if (tick == 1 || tick % std::max(1, ticks / 8) == 0 || tick == ticks) {
            std::printf(
                "[tick=%d] active_nodes=%d collapse=%d encode=%d runtime=%d calm=%d pending=%d pu_tick=%d pu_total=%d/%d\n",
                tick, metrics.active_nodes, metrics.collapse, metrics.encode, metrics.runtime_hits, metrics.calm, metrics.pending, pu_spent_tick, pu_spent_cumulative, pu_cycle_budget
            );
        }

        if (pu_spent_cumulative >= pu_cycle_budget) {
            std::printf("[tick=%d] cycle PU budget exhausted, stopping\n", tick);
            break;
        }
    }

    check_cuda(cudaFree(d_kinds), "free kinds");
    check_cuda(cudaFree(d_activation), "free activation");
    check_cuda(cudaFree(d_next), "free next");
    check_cuda(cudaFree(d_stability), "free stability");
    check_cuda(cudaFree(d_threshold), "free threshold");
    check_cuda(cudaFree(d_decay), "free decay");
    check_cuda(cudaFree(d_bias), "free bias");
    check_cuda(cudaFree(d_weights), "free weights");
    check_cuda(cudaFree(d_metrics), "free metrics");
    return 0;
}
