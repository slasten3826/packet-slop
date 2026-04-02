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

enum L2Kind : int { OBSERVE = 0, CHOOSE = 1, ENCODE = 2, RUNTIME = 3 };
enum L3Mode : int { M_RUNTIME = 0, M_CYCLE = 1, M_LOGIC = 2, M_MANIFEST = 3 };

struct L3Cell {
    float activation;
    float next_activation;
    float charge;
    float left_w;
    float right_w;
    float self_w;
    float gate;
    int mode;
};

struct Crystal {
    int mode;
    int target;
    int span;
    float energy;
    float pu_stock;
    float pu_initial;
};

struct TickMetrics {
    int collapse;
    int encoded;
    int spawned_runtime;
    int spawned_cycle;
    int spawned_logic;
    int spawned_manifest;
    int l3_exhausted;
    float l3_burned;
    float manifest;
};

static int wrap_host(int v, int n) {
    return (v % n + n) % n;
}

static unsigned int lcg_step(unsigned int& state) {
    state = state * 1664525u + 1013904223u;
    return state;
}

static float randf(unsigned int& state) {
    return (lcg_step(state) & 0x00ffffff) / (float)0x01000000;
}

static void derive_l2_shape(int l1_ring, int l1_cw, int& width, int& height) {
    double base = std::max(8.0, std::floor(std::sqrt((double)l1_ring) / 2.0));
    double pressure_factor = 1.0 + std::log2((double)std::max(1, l1_cw)) / 8.0;
    width = std::max(12, (int)std::floor(base * pressure_factor));
    height = std::max(10, (int)std::floor(width * 0.85));
}

static int derive_l3_length(int l2_width, int l2_height, int l1_cw) {
    int area = l2_width * l2_height;
    double base = std::max(24.0, std::floor(std::sqrt((double)area) * 1.8));
    double pressure = 1.0 + std::log2((double)std::max(1, l1_cw)) / 16.0;
    return std::max(24, (int)std::floor(base * pressure));
}

static int kind_for_position(int x, int y) {
    int phase = (x + 2 * y) % 4;
    if (phase == 0) return OBSERVE;
    if (phase == 1) return CHOOSE;
    if (phase == 2) return ENCODE;
    return RUNTIME;
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

__device__ int l2_neighbor_index(int x, int y, int dir, int width, int height) {
    bool even = (y % 2 == 0);
    int nx = x;
    int ny = y;
    if (dir == 0) nx = wrap_dev(x + 1, width);
    else if (dir == 1) nx = wrap_dev(x - 1, width);
    else if (dir == 2) { nx = wrap_dev(x + (even ? 1 : 0), width); ny = wrap_dev(y - 1, height); }
    else if (dir == 3) { nx = wrap_dev(x + (even ? 0 : -1), width); ny = wrap_dev(y - 1, height); }
    else if (dir == 4) { nx = wrap_dev(x + (even ? 1 : 0), width); ny = wrap_dev(y + 1, height); }
    else { nx = wrap_dev(x + (even ? 0 : -1), width); ny = wrap_dev(y + 1, height); }
    return ny * width + nx;
}

__device__ int l2_to_l3_mode_dev(int stability, float raw, float neigh, int y, int height, float threshold) {
    float topness = y / fmaxf(1.0f, (float)(height - 1));
    float conflict = fabsf(raw - neigh);
    float surplus = raw - threshold;
    if (topness > 0.76f && surplus > 0.18f) return M_MANIFEST;
    if (stability >= 5 && surplus > 0.12f) return M_RUNTIME;
    if (conflict < 0.11f && surplus > 0.06f) return M_CYCLE;
    if (conflict > 0.24f) return M_LOGIC;
    return M_CYCLE;
}

__global__ void tick_l2_kernel(
    const int* kinds,
    const float* activation,
    float* next_activation,
    int* stability,
    const float* threshold,
    const float* decay,
    const float* weights,
    int width,
    int height,
    int tick,
    int seed,
    float l1_gain,
    float l3_feedback_ceiling,
    float manifest_feedback,
    int* candidate_spawn,
    int* candidate_mode,
    float* candidate_energy,
    TickMetrics* metrics
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int total = width * height;
    if (idx >= total) return;

    int y = idx / width;
    int x = idx % width;
    int kind = kinds[idx];

    float neigh = 0.0f;
    bool has_runtime = false;
    bool has_choose = false;
    for (int dir = 0; dir < 6; ++dir) {
        int nidx = l2_neighbor_index(x, y, dir, width, height);
        neigh += activation[nidx] * weights[idx * 6 + dir];
        int nk = kinds[nidx];
        if (nk == RUNTIME) has_runtime = true;
        if (nk == CHOOSE) has_choose = true;
    }
    neigh /= 6.0f;

    float from_l1 = 0.0f;
    if (kind != RUNTIME) {
        float depth = 1.0f - (y / fmaxf(1.0f, (float)(height - 1)));
        float n = hash_noise_dev(x + 1, y + 1, tick, seed);
        float spike = n > 0.86f ? (n - 0.86f) * 1.6f : 0.0f;
        float base = depth * l1_gain;
        if (kind == OBSERVE) from_l1 = base + spike;
        else if (kind == CHOOSE || kind == ENCODE) from_l1 = base * 0.55f + spike * 0.6f;
        else from_l1 = base * 0.12f;
    }

    float from_l3 = 0.0f;
    float topness = y / fmaxf(1.0f, (float)(height - 1));
    from_l3 = topness * fminf(l3_feedback_ceiling, manifest_feedback / 200.0f);

    float raw = activation[idx] * decay[idx] + neigh + from_l1 + from_l3;
    float next = raw;

    candidate_spawn[idx] = 0;
    candidate_mode[idx] = -1;
    candidate_energy[idx] = 0.0f;

    if (kind == OBSERVE) {
        next = raw * 0.90f;
    } else if (kind == CHOOSE) {
        next = raw - fmaxf(0.0f, neigh * 0.38f);
        if (next > threshold[idx]) atomicAdd(&metrics->collapse, 1);
    } else if (kind == ENCODE) {
        int st = stability[idx];
        if (raw > threshold[idx]) st += 1;
        else st = st > 0 ? st - 1 : 0;
        stability[idx] = st;
        if (st >= 3 && raw > threshold[idx] + 0.04f && has_runtime && has_choose && ((tick + x + y) % 3 == 0)) {
            int mode = l2_to_l3_mode_dev(st, raw, neigh, y, height, threshold[idx]);
            candidate_spawn[idx] = 1;
            candidate_mode[idx] = mode;
            candidate_energy[idx] = raw;
            atomicAdd(&metrics->encoded, 1);
            if (mode == M_RUNTIME) atomicAdd(&metrics->spawned_runtime, 1);
            else if (mode == M_CYCLE) atomicAdd(&metrics->spawned_cycle, 1);
            else if (mode == M_LOGIC) atomicAdd(&metrics->spawned_logic, 1);
            else if (mode == M_MANIFEST) atomicAdd(&metrics->spawned_manifest, 1);
            stability[idx] = 0;
        }
        next = raw;
    } else if (kind == RUNTIME) {
        next = raw * 0.93f + fminf(0.08f, manifest_feedback * 0.0012f);
    }

    next_activation[idx] = clamp_dev(next, 0.0f, 1.25f);
}

__global__ void commit_l2_kernel(float* activation, const float* next_activation, int total) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= total) return;
    activation[idx] = next_activation[idx];
}

__global__ void apply_l3_crystals_kernel(L3Cell* cells, int length, Crystal* crystals, int active_count, float phase, float* manifest_delta, float* burned_out) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= active_count) return;
    Crystal& crystal = crystals[idx];
    if (crystal.pu_stock <= 0.0f) return;

    float strength = clamp_dev(crystal.pu_stock / fmaxf(1.0f, crystal.pu_initial), 0.12f, 1.0f);
    int targets[2] = {crystal.target, -1};
    if (crystal.span >= 2) targets[1] = wrap_dev(crystal.target + 1, length);

    for (int i = 0; i < 2; ++i) {
        if (targets[i] < 0) continue;
        L3Cell& cell = cells[targets[i]];
        float e = crystal.energy * strength;
        cell.mode = crystal.mode;
        if (crystal.mode == M_RUNTIME) {
            atomicAdd(&cell.charge, e * 0.90f);
            atomicAdd(&cell.self_w, e * 0.015f);
        } else if (crystal.mode == M_CYCLE) {
            atomicAdd(&cell.charge, sinf(phase + targets[i] * 0.07f) * e * 0.55f);
            atomicAdd(&cell.gate, e * 0.18f);
        } else if (crystal.mode == M_LOGIC) {
            cell.charge = cell.charge * (1.0f - e * 0.22f);
            atomicAdd(&cell.left_w, -e * 0.012f);
            atomicAdd(&cell.right_w, -e * 0.012f);
        } else if (crystal.mode == M_MANIFEST) {
            atomicAdd(&cell.charge, e * 0.30f);
            atomicAdd(&cell.gate, e * 0.35f);
            atomicAdd(manifest_delta, e * 0.14f);
        }
    }

    float burn = 0.18f + crystal.span * 0.05f;
    burn += (crystal.mode == M_RUNTIME ? 0.18f : crystal.mode == M_CYCLE ? 0.20f : crystal.mode == M_LOGIC ? 0.24f : 0.30f);
    burn += crystal.energy * 0.35f;
    crystal.pu_stock -= burn;
    atomicAdd(burned_out, burn);
}

__global__ void update_l3_kernel(L3Cell* cells, int length, float phase) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;
    L3Cell c = cells[idx];
    L3Cell l = cells[wrap_dev(idx - 1, length)];
    L3Cell r = cells[wrap_dev(idx + 1, length)];
    float cycle_gain = 1.0f + 0.16f * sinf(phase);
    float decay = 0.88f + 0.03f * cosf(phase * 0.7f);
    float raw = l.activation * c.left_w + r.activation * c.right_w + c.activation * c.self_w + c.charge * cycle_gain;
    if (c.mode == M_LOGIC) raw = raw * 0.78f;
    else if (c.mode == M_MANIFEST) raw = raw + c.gate * 0.10f;
    else if (c.mode == M_CYCLE) raw = raw + sinf(phase + idx * 0.11f) * 0.08f;
    cells[idx].next_activation = clamp_dev(raw * decay, 0.0f, 1.0f);
    cells[idx].charge *= 0.78f;
    cells[idx].gate *= 0.86f;
    cells[idx].left_w = clamp_dev(cells[idx].left_w, 0.05f, 0.60f);
    cells[idx].right_w = clamp_dev(cells[idx].right_w, 0.05f, 0.60f);
    cells[idx].self_w = clamp_dev(cells[idx].self_w, 0.30f, 0.88f);
}

__global__ void commit_l3_kernel(L3Cell* cells, int length) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;
    cells[idx].activation = cells[idx].next_activation;
}

int main(int argc, char** argv) {
    int l1_ring = argc > 1 ? std::atoi(argv[1]) : 4096;
    int l1_cw = argc > 2 ? std::atoi(argv[2]) : 256;
    int ticks = argc > 3 ? std::atoi(argv[3]) : 128;
    int seed = argc > 4 ? std::atoi(argv[4]) : 12345;

    int l2_width = 0, l2_height = 0;
    derive_l2_shape(l1_ring, l1_cw, l2_width, l2_height);
    int total = l2_width * l2_height;
    int l3_length = derive_l3_length(l2_width, l2_height, l1_cw);

    std::vector<int> h_kinds(total);
    std::vector<float> h_l2_activation(total, 0.0f), h_l2_next(total, 0.0f), h_threshold(total), h_decay(total), h_weights(total * 6);
    std::vector<int> h_stability(total, 0), h_candidate_spawn(total, 0), h_candidate_mode(total, -1);
    std::vector<float> h_candidate_energy(total, 0.0f);
    unsigned int rng = (unsigned int)seed;
    for (int y = 0; y < l2_height; ++y) {
        for (int x = 0; x < l2_width; ++x) {
            int idx = y * l2_width + x;
            int kind = kind_for_position(x, y);
            h_kinds[idx] = kind;
            h_threshold[idx] = kind == OBSERVE ? 0.28f : kind == CHOOSE ? 0.48f : kind == ENCODE ? 0.58f : 0.40f;
            h_decay[idx] = kind == OBSERVE ? 0.83f : kind == CHOOSE ? 0.80f : kind == ENCODE ? 0.87f : 0.91f;
            for (int d = 0; d < 6; ++d) h_weights[idx * 6 + d] = 0.14f + randf(rng) * 0.42f;
        }
    }

    std::vector<L3Cell> h_l3(l3_length);
    for (int i = 0; i < l3_length; ++i) {
        h_l3[i] = {0.0f, 0.0f, 0.0f, 0.16f + randf(rng) * 0.14f, 0.16f + randf(rng) * 0.14f, 0.48f + randf(rng) * 0.14f, 0.0f, M_RUNTIME};
    }

    int *d_kinds, *d_stability, *d_candidate_spawn, *d_candidate_mode;
    float *d_l2_activation, *d_l2_next, *d_threshold, *d_decay, *d_weights, *d_candidate_energy;
    L3Cell* d_l3;
    Crystal* d_crystals;
    TickMetrics* d_metrics;
    float *d_manifest_delta, *d_burned;
    check_cuda(cudaMalloc(&d_kinds, sizeof(int) * total), "malloc d_kinds");
    check_cuda(cudaMalloc(&d_stability, sizeof(int) * total), "malloc d_stability");
    check_cuda(cudaMalloc(&d_candidate_spawn, sizeof(int) * total), "malloc d_candidate_spawn");
    check_cuda(cudaMalloc(&d_candidate_mode, sizeof(int) * total), "malloc d_candidate_mode");
    check_cuda(cudaMalloc(&d_l2_activation, sizeof(float) * total), "malloc d_l2_activation");
    check_cuda(cudaMalloc(&d_l2_next, sizeof(float) * total), "malloc d_l2_next");
    check_cuda(cudaMalloc(&d_threshold, sizeof(float) * total), "malloc d_threshold");
    check_cuda(cudaMalloc(&d_decay, sizeof(float) * total), "malloc d_decay");
    check_cuda(cudaMalloc(&d_weights, sizeof(float) * total * 6), "malloc d_weights");
    check_cuda(cudaMalloc(&d_candidate_energy, sizeof(float) * total), "malloc d_candidate_energy");
    int crystal_capacity = std::max(1, total * ticks);
    check_cuda(cudaMalloc(&d_l3, sizeof(L3Cell) * l3_length), "malloc d_l3");
    check_cuda(cudaMalloc(&d_crystals, sizeof(Crystal) * crystal_capacity), "malloc d_crystals");
    check_cuda(cudaMalloc(&d_metrics, sizeof(TickMetrics)), "malloc d_metrics");
    check_cuda(cudaMalloc(&d_manifest_delta, sizeof(float)), "malloc d_manifest_delta");
    check_cuda(cudaMalloc(&d_burned, sizeof(float)), "malloc d_burned");

    check_cuda(cudaMemcpy(d_kinds, h_kinds.data(), sizeof(int) * total, cudaMemcpyHostToDevice), "copy kinds");
    check_cuda(cudaMemcpy(d_stability, h_stability.data(), sizeof(int) * total, cudaMemcpyHostToDevice), "copy stability");
    check_cuda(cudaMemcpy(d_l2_activation, h_l2_activation.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy activation");
    check_cuda(cudaMemcpy(d_l2_next, h_l2_next.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy next");
    check_cuda(cudaMemcpy(d_threshold, h_threshold.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy threshold");
    check_cuda(cudaMemcpy(d_decay, h_decay.data(), sizeof(float) * total, cudaMemcpyHostToDevice), "copy decay");
    check_cuda(cudaMemcpy(d_weights, h_weights.data(), sizeof(float) * total * 6, cudaMemcpyHostToDevice), "copy weights");
    check_cuda(cudaMemcpy(d_l3, h_l3.data(), sizeof(L3Cell) * l3_length, cudaMemcpyHostToDevice), "copy l3");

    std::vector<Crystal> active;
    float manifest = 0.0f;
    float l3_phase = 0.0f;
    float burned_total = 0.0f;
    int exhausted_total = 0;
    int cell_threads = 256;
    int l2_blocks = (total + cell_threads - 1) / cell_threads;
    int l3_blocks = (l3_length + cell_threads - 1) / cell_threads;

    std::printf("cuda eva00 stand\n");
    std::printf("l1_ring=%d l1_cw=%d -> l2=%dx%d l3=%d ticks=%d seed=%d\n", l1_ring, l1_cw, l2_width, l2_height, l3_length, ticks, seed);

    for (int tick = 1; tick <= ticks; ++tick) {
        check_cuda(cudaMemset(d_metrics, 0, sizeof(TickMetrics)), "memset metrics");
        tick_l2_kernel<<<l2_blocks, cell_threads>>>(
            d_kinds, d_l2_activation, d_l2_next, d_stability, d_threshold, d_decay, d_weights,
            l2_width, l2_height, tick, seed,
            0.20f + std::log2((float)std::max(1, l1_cw)) * 0.014f,
            0.05f + std::log2((float)std::max(1, l1_cw)) * 0.005f,
            manifest,
            d_candidate_spawn, d_candidate_mode, d_candidate_energy, d_metrics
        );
        check_cuda(cudaGetLastError(), "tick l2");
        commit_l2_kernel<<<l2_blocks, cell_threads>>>(d_l2_activation, d_l2_next, total);
        check_cuda(cudaGetLastError(), "commit l2");
        check_cuda(cudaMemcpy(h_candidate_spawn.data(), d_candidate_spawn, sizeof(int) * total, cudaMemcpyDeviceToHost), "copy candidate spawn");
        check_cuda(cudaMemcpy(h_candidate_mode.data(), d_candidate_mode, sizeof(int) * total, cudaMemcpyDeviceToHost), "copy candidate mode");
        check_cuda(cudaMemcpy(h_candidate_energy.data(), d_candidate_energy, sizeof(float) * total, cudaMemcpyDeviceToHost), "copy candidate energy");

        for (int idx = 0; idx < total; ++idx) {
            if (!h_candidate_spawn[idx]) continue;
            int x = idx % l2_width;
            int y = idx / l2_width;
            int target = (x * 11 + y * 7 + tick * 3) % l3_length;
            float energy = h_candidate_energy[idx];
            int st = 3;
            int pu_stock = (int)std::floor(6.0f + energy * 14.0f + st * 2.0f);
            Crystal c;
            c.mode = h_candidate_mode[idx];
            c.target = target;
            c.span = 1 + ((x + y + tick) % 2);
            c.energy = energy;
            c.pu_stock = (float)pu_stock;
            c.pu_initial = (float)pu_stock;
            active.push_back(c);
        }

        if (!active.empty()) {
            if ((int)active.size() > crystal_capacity) {
                std::fprintf(stderr, "active crystal overflow: %zu > %d\n", active.size(), crystal_capacity);
                std::exit(1);
            }
            check_cuda(cudaMemcpy(d_crystals, active.data(), sizeof(Crystal) * active.size(), cudaMemcpyHostToDevice), "copy crystals");
            check_cuda(cudaMemset(d_manifest_delta, 0, sizeof(float)), "memset manifest");
            check_cuda(cudaMemset(d_burned, 0, sizeof(float)), "memset burned");
            int crystal_blocks = ((int)active.size() + cell_threads - 1) / cell_threads;
            apply_l3_crystals_kernel<<<crystal_blocks, cell_threads>>>(d_l3, l3_length, d_crystals, (int)active.size(), l3_phase, d_manifest_delta, d_burned);
            check_cuda(cudaGetLastError(), "apply l3 crystals");
            check_cuda(cudaMemcpy(active.data(), d_crystals, sizeof(Crystal) * active.size(), cudaMemcpyDeviceToHost), "copy crystals back");
            float burned_now = 0.0f;
            float manifest_now = 0.0f;
            check_cuda(cudaMemcpy(&burned_now, d_burned, sizeof(float), cudaMemcpyDeviceToHost), "copy burned");
            check_cuda(cudaMemcpy(&manifest_now, d_manifest_delta, sizeof(float), cudaMemcpyDeviceToHost), "copy manifest");
            burned_total += burned_now;
            manifest += manifest_now;
        }

        l3_phase += 0.11f;
        update_l3_kernel<<<l3_blocks, cell_threads>>>(d_l3, l3_length, l3_phase);
        check_cuda(cudaGetLastError(), "update l3");
        commit_l3_kernel<<<l3_blocks, cell_threads>>>(d_l3, l3_length);
        check_cuda(cudaGetLastError(), "commit l3");
        check_cuda(cudaDeviceSynchronize(), "tick sync");

        check_cuda(cudaMemcpy(h_l3.data(), d_l3, sizeof(L3Cell) * l3_length, cudaMemcpyDeviceToHost), "copy l3 back");
        std::vector<Crystal> survivors;
        for (const Crystal& c : active) {
            if (c.pu_stock > 0.0f) survivors.push_back(c);
            else exhausted_total++;
        }
        active.swap(survivors);

        float readout = 0.0f, energy = 0.0f, active_pu = 0.0f;
        int out_count = std::max(4, (int)std::floor(l3_length * 0.12f));
        int start_idx = std::max(0, l3_length - out_count);
        for (int i = 0; i < l3_length; ++i) {
            energy += std::fabs(h_l3[i].activation) + std::fabs(h_l3[i].charge);
            if (i >= start_idx) readout += h_l3[i].activation;
        }
        for (const Crystal& c : active) active_pu += std::max(0.0f, c.pu_stock);
        readout /= (float)out_count;

        TickMetrics m{};
        check_cuda(cudaMemcpy(&m, d_metrics, sizeof(TickMetrics), cudaMemcpyDeviceToHost), "copy metrics");
        if (tick == 1 || tick % std::max(1, ticks / 8) == 0 || tick == ticks) {
            std::printf("[tick=%d] encoded=%d active=%zu exhausted=%d modes=(R:%d C:%d L:%d M:%d) readout=%.4f energy=%.2f manifest=%.2f active_pu=%.1f burned=%.1f\n",
                tick, m.encoded, active.size(), exhausted_total, m.spawned_runtime, m.spawned_cycle, m.spawned_logic, m.spawned_manifest,
                readout, energy, manifest, active_pu, burned_total);
        }
    }

    check_cuda(cudaFree(d_kinds), "free d_kinds");
    check_cuda(cudaFree(d_stability), "free d_stability");
    check_cuda(cudaFree(d_candidate_spawn), "free d_candidate_spawn");
    check_cuda(cudaFree(d_candidate_mode), "free d_candidate_mode");
    check_cuda(cudaFree(d_l2_activation), "free d_l2_activation");
    check_cuda(cudaFree(d_l2_next), "free d_l2_next");
    check_cuda(cudaFree(d_threshold), "free d_threshold");
    check_cuda(cudaFree(d_decay), "free d_decay");
    check_cuda(cudaFree(d_weights), "free d_weights");
    check_cuda(cudaFree(d_candidate_energy), "free d_candidate_energy");
    check_cuda(cudaFree(d_l3), "free d_l3");
    check_cuda(cudaFree(d_crystals), "free d_crystals");
    check_cuda(cudaFree(d_metrics), "free d_metrics");
    check_cuda(cudaFree(d_manifest_delta), "free d_manifest_delta");
    check_cuda(cudaFree(d_burned), "free d_burned");
    return 0;
}
