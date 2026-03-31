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

enum CrystalKind : int {
    EXCITE = 0,
    INHIBIT = 1,
    CONNECT = 2,
    RELEASE = 3,
};

struct Cell {
    float activation;
    float next_activation;
    float left_w;
    float right_w;
    float self_w;
    float bias;
    float charge;
    float cooldown;
};

struct Crystal {
    int kind;
    int target;
    int span;
    float energy;
    float pu_stock;
    float pu_initial;
    int age;
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

static int derive_pu_capacity(int l2_width, int l2_height) {
    return l2_width * l2_height;
}

static int derive_tape_length(int l2_width, int l2_height, int l1_cw) {
    int area = l2_width * l2_height;
    double base = std::max(24.0, std::floor(std::sqrt((double)area) * 2.2));
    double pressure = 1.0 + std::log2((double)std::max(1, l1_cw)) / 14.0;
    return std::max(24, (int)std::floor(base * pressure));
}

static int derive_queue_length(int l2_width, int l2_height, int l1_cw) {
    int area = l2_width * l2_height;
    int base = std::max(8, (int)std::floor(std::sqrt((double)area) / 2.6));
    int pressure = std::max(2, (int)std::floor(std::log2((double)std::max(2, l1_cw))));
    return base + pressure;
}

static float crystal_nominal_stock(int kind, float energy, int span) {
    const float base[4] = {8.0f, 8.0f, 11.0f, 11.0f};
    return base[kind] + energy * 16.0f + span * 2.5f;
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

__device__ float cycle_mod(float phase) {
    return 1.0f + 0.18f * sinf(phase);
}

__device__ float logic_soft_clip(float x) {
    if (x > 1.0f) return 1.0f - (x - 1.0f) * 0.15f;
    if (x < 0.0f) return x * 0.15f;
    return x;
}

__device__ float burn_cost(const Crystal& crystal, float cycle_gain) {
    float base_cost = 0.16f + crystal.span * 0.03f;
    float influence_cost = crystal.energy * 0.42f * cycle_gain;
    float rewrite_cost = 0.0f;
    if (crystal.kind == CONNECT || crystal.kind == RELEASE) {
        rewrite_cost = 0.26f + crystal.span * 0.07f;
    }
    return base_cost + influence_cost + rewrite_cost;
}

__global__ void apply_crystals_kernel(Cell* cells, int length, Crystal* crystals, int active_count, float cycle_phase, float* burned_out) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= active_count) return;

    Crystal& crystal = crystals[idx];
    if (crystal.pu_stock <= 0.0f) return;

    float cycle_gain = cycle_mod(cycle_phase);
    float strength = clamp_dev(crystal.pu_stock / fmaxf(1.0f, crystal.pu_initial), 0.15f, 1.0f);
    int affected[3] = {crystal.target, -1, -1};
    if (crystal.span >= 2) affected[1] = wrap_dev(crystal.target + 1, length);
    if (crystal.span >= 3) affected[2] = wrap_dev(crystal.target - 1, length);

    for (int i = 0; i < 3; ++i) {
        if (affected[i] < 0) continue;
        Cell& cell = cells[affected[i]];
        float energy = crystal.energy * strength;
        if (crystal.kind == EXCITE) {
            atomicAdd(&cell.charge, energy * cycle_gain);
        } else if (crystal.kind == INHIBIT) {
            atomicAdd(&cell.charge, -energy * 0.85f * cycle_gain);
        } else if (crystal.kind == CONNECT) {
            atomicAdd(&cell.left_w, energy * 0.025f);
            atomicAdd(&cell.right_w, energy * 0.025f);
            atomicAdd(&cell.self_w, energy * 0.015f);
            atomicAdd(&cell.cooldown, 0.04f);
        } else if (crystal.kind == RELEASE) {
            atomicAdd(&cell.left_w, -energy * 0.025f);
            atomicAdd(&cell.right_w, -energy * 0.025f);
            atomicAdd(&cell.self_w, -energy * 0.015f);
            atomicAdd(&cell.cooldown, 0.04f);
        }
    }

    float burn = burn_cost(crystal, cycle_gain);
    crystal.pu_stock -= burn;
    crystal.age += 1;
    atomicAdd(burned_out, burn);
}

__global__ void update_cells_kernel(Cell* cells, int length, float cycle_phase) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;

    Cell cell = cells[idx];
    Cell left = cells[wrap_dev(idx - 1, length)];
    Cell right = cells[wrap_dev(idx + 1, length)];

    float decay = 0.90f + 0.03f * cosf(cycle_phase * 0.7f);
    float cooldown_brake = 1.0f - cell.cooldown * 0.35f;
    float raw =
        left.activation * cell.left_w +
        right.activation * cell.right_w +
        cell.activation * cell.self_w +
        cell.charge * cycle_mod(cycle_phase) +
        cell.bias;

    raw = raw * decay * cooldown_brake;
    raw = logic_soft_clip(raw);
    cells[idx].next_activation = clamp_dev(raw, -1.0f, 1.0f);
}

__global__ void commit_cells_kernel(Cell* cells, int length) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;
    cells[idx].activation = cells[idx].next_activation;
    cells[idx].next_activation = 0.0f;
    cells[idx].charge *= 0.82f;
    cells[idx].cooldown *= 0.90f;
    cells[idx].left_w = clamp_dev(cells[idx].left_w, 0.05f, 0.72f);
    cells[idx].right_w = clamp_dev(cells[idx].right_w, 0.05f, 0.72f);
    cells[idx].self_w = clamp_dev(cells[idx].self_w, 0.30f, 0.80f);
}

int main(int argc, char** argv) {
    int l1_ring = argc > 1 ? std::atoi(argv[1]) : 4096;
    int l1_cw = argc > 2 ? std::atoi(argv[2]) : 256;
    int ticks = argc > 3 ? std::atoi(argv[3]) : 96;
    int seed = argc > 4 ? std::atoi(argv[4]) : 12345;

    int l2_width = 0, l2_height = 0;
    derive_l2_shape(l1_ring, l1_cw, l2_width, l2_height);
    int pu_max = derive_pu_capacity(l2_width, l2_height);
    int length = derive_tape_length(l2_width, l2_height, l1_cw);
    int queue_len = derive_queue_length(l2_width, l2_height, l1_cw);

    std::vector<Cell> h_cells(length);
    unsigned int rng = (unsigned int)seed;
    for (int i = 0; i < length; ++i) {
        h_cells[i].activation = 0.0f;
        h_cells[i].next_activation = 0.0f;
        h_cells[i].left_w = 0.18f + randf(rng) * 0.16f;
        h_cells[i].right_w = 0.18f + randf(rng) * 0.16f;
        h_cells[i].self_w = 0.52f + randf(rng) * 0.12f;
        h_cells[i].bias = (randf(rng) - 0.5f) * 0.04f;
        h_cells[i].charge = 0.0f;
        h_cells[i].cooldown = 0.0f;
    }

    struct ScheduledCrystal { int tick; Crystal crystal; };
    std::vector<ScheduledCrystal> queue;
    int remaining = (int)std::floor(pu_max * 0.72);
    int t = 1;
    for (int i = 0; i < queue_len && remaining > 8; ++i) {
        int kind = (int)(lcg_step(rng) % 4u);
        int target = (int)(lcg_step(rng) % (unsigned)length);
        float energy = 0.10f + randf(rng) * 0.55f;
        int span = 1 + (int)(lcg_step(rng) % 3u);
        int pu_stock = std::min(remaining, (int)std::floor(crystal_nominal_stock(kind, energy, span) + 0.5f));
        queue.push_back({
            t,
            {kind, target, span, energy, (float)pu_stock, (float)pu_stock, 0}
        });
        remaining -= pu_stock;
        t += 1 + (int)(lcg_step(rng) % 4u);
    }

    Cell* d_cells = nullptr;
    Crystal* d_crystals = nullptr;
    float* d_burned = nullptr;
    check_cuda(cudaMalloc(&d_cells, sizeof(Cell) * length), "malloc cells");
    check_cuda(cudaMalloc(&d_crystals, sizeof(Crystal) * std::max(1, (int)queue.size())), "malloc crystals");
    check_cuda(cudaMalloc(&d_burned, sizeof(float)), "malloc burned");
    check_cuda(cudaMemcpy(d_cells, h_cells.data(), sizeof(Cell) * length, cudaMemcpyHostToDevice), "copy cells");

    std::vector<Crystal> active;
    size_t queue_index = 0;
    float cycle_phase = 0.0f;
    float burned_total = 0.0f;
    int exhausted_total = 0;
    int manifest = 0;
    float last_readout = 0.0f;
    int stable_ticks = 0;

    int cell_threads = 256;
    int cell_blocks = (length + cell_threads - 1) / cell_threads;

    std::printf("cuda l3 substrate stand\n");
    std::printf("l1_ring=%d l1_cw=%d -> l2=%dx%d pu_max=%d tape=%d scheduled=%zu ticks=%d seed=%d\n",
        l1_ring, l1_cw, l2_width, l2_height, pu_max, length, queue.size(), ticks, seed);

    for (int tick = 1; tick <= ticks; ++tick) {
        while (queue_index < queue.size() && queue[queue_index].tick == tick) {
            active.push_back(queue[queue_index].crystal);
            queue_index++;
        }

        if (!active.empty()) {
            check_cuda(cudaMemcpy(d_crystals, active.data(), sizeof(Crystal) * active.size(), cudaMemcpyHostToDevice), "copy active crystals");
            check_cuda(cudaMemset(d_burned, 0, sizeof(float)), "memset burned");
            int crystal_blocks = ((int)active.size() + cell_threads - 1) / cell_threads;
            apply_crystals_kernel<<<crystal_blocks, cell_threads>>>(d_cells, length, d_crystals, (int)active.size(), cycle_phase, d_burned);
            check_cuda(cudaGetLastError(), "apply crystals");
            check_cuda(cudaMemcpy(active.data(), d_crystals, sizeof(Crystal) * active.size(), cudaMemcpyDeviceToHost), "copy active crystals back");
            float burned_now = 0.0f;
            check_cuda(cudaMemcpy(&burned_now, d_burned, sizeof(float), cudaMemcpyDeviceToHost), "copy burned");
            burned_total += burned_now;
        }

        cycle_phase += 0.12f;
        update_cells_kernel<<<cell_blocks, cell_threads>>>(d_cells, length, cycle_phase);
        check_cuda(cudaGetLastError(), "update cells");
        commit_cells_kernel<<<cell_blocks, cell_threads>>>(d_cells, length);
        check_cuda(cudaGetLastError(), "commit cells");
        check_cuda(cudaDeviceSynchronize(), "tick sync");

        check_cuda(cudaMemcpy(h_cells.data(), d_cells, sizeof(Cell) * length, cudaMemcpyDeviceToHost), "copy cells back");

        std::vector<Crystal> survivors;
        for (const Crystal& c : active) {
            if (c.pu_stock > 0.0f) survivors.push_back(c);
            else exhausted_total++;
        }
        active.swap(survivors);

        int out_count = std::max(4, (int)std::floor(length * 0.1f));
        int start_idx = std::max(0, length - out_count);
        float readout = 0.0f;
        float energy = 0.0f;
        float active_pu = 0.0f;
        for (int i = 0; i < length; ++i) {
            energy += std::fabs(h_cells[i].activation) + std::fabs(h_cells[i].charge);
            if (i >= start_idx) readout += h_cells[i].activation;
        }
        for (const Crystal& c : active) active_pu += std::max(0.0f, c.pu_stock);
        readout /= (float)out_count;

        if (std::fabs(readout - last_readout) < 0.015f && std::fabs(readout) > 0.08f) stable_ticks++;
        else stable_ticks = 0;
        last_readout = readout;
        if (stable_ticks >= 3) {
            manifest++;
            stable_ticks = 0;
        }

        if (tick == 1 || tick % std::max(1, ticks / 8) == 0 || tick == ticks) {
            std::printf(
                "[tick=%d] active=%zu exhausted=%d readout=%.4f energy=%.4f manifest=%d active_pu=%.1f burned=%.1f queue_left=%zu\n",
                tick, active.size(), exhausted_total, readout, energy, manifest, active_pu, burned_total, queue.size() - queue_index
            );
        }
    }

    check_cuda(cudaFree(d_cells), "free cells");
    check_cuda(cudaFree(d_crystals), "free crystals");
    check_cuda(cudaFree(d_burned), "free burned");
    return 0;
}
