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

enum L3Mode : int { M_RUNTIME = 0, M_CYCLE = 1, M_LOGIC = 2, M_MANIFEST = 3 };

struct EncodeProcess {
    int id;
    int x;
    int y;
    int age;
    int alive;
    int success;
    int emitted;

    float pu;
    float burn;

    float connect_strength;
    float chaos_flux;
    float raw_mass;
    float raw_noise;

    float calm_mass;
    float calm_coherence;

    int observe_raw_calls;
    int observe_calm_calls;
    int choose_raw_calls;
    int choose_calm_calls;
    int runtime_calls;
};

struct Crystal {
    int pocket;
    int mode;
    int target;
    int span;
    float energy;
    float pu_stock;
    float pu_initial;
};

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

struct Summary {
    int alive;
    int success;
    int failed;
    int emitted;
    int observe_raw;
    int observe_calm;
    int choose_raw;
    int choose_calm;
    int runtime;
    float age_sum;
    float burn_sum;
    float coherence_sum;
};

struct PocketStats {
    int incoming[4];
    int exhausted;
    float manifest;
    float burned;
    float readout;
    int active_modes[4];
    int active_count;
};

static constexpr int DEFAULT_TICKS = 128;
static constexpr int DEFAULT_PROCESS_COUNT = 1024;
static constexpr int DEFAULT_SEED = 12345;
static constexpr int DEFAULT_L3_COUNT = 3;
static constexpr int DEFAULT_L3_LENGTH = 72;

static constexpr float COST_CONNECT = 1.4f;
static constexpr float COST_OBSERVE_RAW = 0.5f;
static constexpr float COST_OBSERVE_CALM = 1.0f;
static constexpr float COST_CHOOSE_RAW = 0.5f;
static constexpr float COST_CHOOSE_CALM = 1.0f;
static constexpr float COST_ENCODE = 1.8f;
static constexpr float COST_RUNTIME = 0.75f;

__device__ __host__ static float clampf(float v, float lo, float hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

__device__ __host__ static int wrapi(int v, int n) {
    int r = v % n;
    return r < 0 ? r + n : r;
}

__device__ static float hash_noise_dev(int a, int b, int c, int d) {
    unsigned int v = (unsigned int)(a * 92821 + b * 68917 + c * 1237 + d * 17);
    v ^= v << 13;
    v ^= v >> 17;
    v ^= v << 5;
    return (v % 1000) / 1000.0f;
}

static unsigned int lcg_step(unsigned int& state) {
    state = state * 1664525u + 1013904223u;
    return state;
}

static float randf(unsigned int& state) {
    return (lcg_step(state) & 0x00ffffff) / (float)0x01000000;
}

__device__ static void spend_dev(EncodeProcess& p, float amount) {
    p.pu -= amount;
    p.burn += amount;
}

__device__ static void connect_tick_dev(EncodeProcess& p, float intensity, float variance) {
    spend_dev(p, COST_CONNECT);
    float gain = intensity * 0.28f + (1.0f - variance) * 0.16f;
    p.connect_strength = clampf(p.connect_strength * 0.95f + gain, 0.0f, 1.5f);
    p.chaos_flux = intensity * p.connect_strength;
    p.raw_mass += p.chaos_flux * 0.75f;
    p.raw_noise = clampf(p.raw_noise * 0.90f + variance * 0.12f, 0.0f, 1.0f);
}

__device__ static void observe_raw_tick_dev(EncodeProcess& p, float intensity, float variance) {
    spend_dev(p, COST_OBSERVE_RAW);
    p.observe_raw_calls += 1;
    p.raw_mass += intensity * 0.10f;
    p.raw_noise = clampf(p.raw_noise * 0.86f + variance * 0.06f, 0.0f, 1.0f);
}

__device__ static void choose_raw_tick_dev(EncodeProcess& p) {
    spend_dev(p, COST_CHOOSE_RAW);
    p.choose_raw_calls += 1;
    float dissolved = p.raw_mass * (0.08f + p.raw_noise * 0.14f);
    p.raw_mass = fmaxf(0.0f, p.raw_mass - dissolved);
    p.raw_noise = clampf(p.raw_noise * 0.84f, 0.0f, 1.0f);
}

__device__ static void encode_tick_dev(EncodeProcess& p) {
    spend_dev(p, COST_ENCODE);
    float convertible = fminf(p.raw_mass * 0.28f, p.connect_strength * 0.24f);
    p.raw_mass = fmaxf(0.0f, p.raw_mass - convertible);
    p.calm_mass += convertible;
    float coherence_gain = convertible * (1.0f - p.raw_noise) * 0.65f;
    float coherence_loss = p.raw_noise * 0.03f + fmaxf(0.0f, 0.14f - p.connect_strength) * 0.05f;
    p.calm_coherence = clampf(p.calm_coherence + coherence_gain - coherence_loss, 0.0f, 1.0f);
}

__device__ static void observe_calm_tick_dev(EncodeProcess& p) {
    spend_dev(p, COST_OBSERVE_CALM);
    p.observe_calm_calls += 1;
    if (p.calm_mass > 0.0f) {
        p.calm_coherence = clampf(p.calm_coherence + 0.015f, 0.0f, 1.0f);
    }
}

__device__ static void choose_calm_tick_dev(EncodeProcess& p) {
    spend_dev(p, COST_CHOOSE_CALM);
    p.choose_calm_calls += 1;
    if (p.calm_coherence < 0.28f) {
        p.calm_mass *= 0.82f;
    } else if (p.calm_coherence > 0.62f) {
        p.calm_coherence = clampf(p.calm_coherence + 0.02f, 0.0f, 1.0f);
    }
}

__device__ static int choose_l3_mode_dev(const EncodeProcess& p, int pocket) {
    float jitter = ((pocket * 17 + p.id) % 100) / 100.0f;
    if (p.calm_coherence + jitter * 0.04f > 0.90f && p.calm_mass > 3.2f) return M_MANIFEST;
    if (p.raw_noise - jitter * 0.03f > 0.58f) return M_LOGIC;
    if (p.chaos_flux + jitter * 0.06f > 0.70f) return M_CYCLE;
    return M_RUNTIME;
}

__global__ void tick_encode_kernel(
    EncodeProcess* processes,
    int count,
    int tick,
    int seed,
    int l3_count,
    int l3_length,
    Crystal* emitted,
    int* emitted_count
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;

    EncodeProcess& p = processes[idx];
    if (!p.alive) return;

    p.age += 1;

    float intensity = hash_noise_dev(p.x, p.y, tick, seed);
    float variance = hash_noise_dev(p.y, p.id, tick * 3, seed + 11);

    connect_tick_dev(p, intensity, variance);

    bool want_observe_raw = p.raw_noise > 0.62f || p.raw_mass < 0.22f;
    bool want_choose_raw = p.raw_mass > 1.10f || p.raw_noise > 0.78f;
    bool want_observe_calm = p.calm_mass > 0.30f;
    bool want_choose_calm = p.calm_mass > 1.40f || p.calm_coherence < 0.26f;

    if (want_observe_raw) observe_raw_tick_dev(p, intensity, variance);
    if (want_choose_raw) choose_raw_tick_dev(p);
    encode_tick_dev(p);
    if (want_observe_calm) observe_calm_tick_dev(p);
    if (want_choose_calm) choose_calm_tick_dev(p);

    if (p.calm_mass > 2.2f && p.calm_coherence > 0.68f && p.connect_strength > 0.25f) {
        spend_dev(p, COST_RUNTIME);
        p.runtime_calls += 1;
        p.alive = 0;
        p.success = 1;
        p.emitted = 1;

        int pocket = ((p.id * 11 + tick * 7 + p.x * 3 + p.y) % l3_count);
        int out_idx = atomicAdd(emitted_count, 1);
        Crystal c;
        c.pocket = pocket;
        c.mode = choose_l3_mode_dev(p, pocket + 1);
        c.target = (p.id * 7 + tick * 3 + (pocket + 1) * 13) % l3_length;
        c.span = p.calm_coherence > 0.82f ? 2 : 1;
        c.energy = 0.22f + p.calm_mass * 0.11f;
        c.pu_stock = 5.0f + p.calm_mass * 3.2f + p.calm_coherence * 6.0f;
        c.pu_initial = c.pu_stock;
        emitted[out_idx] = c;
        return;
    }

    if (p.pu <= 0.0f || p.connect_strength <= 0.03f || (p.age > 28 && p.calm_mass < 0.20f)) {
        p.alive = 0;
        p.success = 0;
    }
}

__global__ void apply_l3_crystals_kernel(L3Cell* cells, int length, Crystal* crystals, int active_count, float phase, float cost_scale, float* manifest_delta, float* burned_out) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= active_count) return;
    Crystal& crystal = crystals[idx];
    if (crystal.pu_stock <= 0.0f) return;

    float strength = clampf(crystal.pu_stock / fmaxf(1.0f, crystal.pu_initial), 0.10f, 1.0f);
    int targets[2] = { crystal.target, -1 };
    if (crystal.span >= 2) targets[1] = wrapi(crystal.target + 1, length);

    for (int i = 0; i < 2; ++i) {
        if (targets[i] < 0) continue;
        L3Cell& cell = cells[targets[i]];
        float e = crystal.energy * strength;
        cell.mode = crystal.mode;
        if (crystal.mode == M_RUNTIME) {
            atomicAdd(&cell.charge, e * 0.75f);
        } else if (crystal.mode == M_CYCLE) {
            atomicAdd(&cell.charge, sinf(phase + targets[i] * 0.09f) * e * 0.45f);
            atomicAdd(&cell.gate, e * 0.12f);
        } else if (crystal.mode == M_LOGIC) {
            cell.charge = cell.charge * (1.0f - e * 0.18f);
            atomicAdd(&cell.left_w, -e * 0.01f);
            atomicAdd(&cell.right_w, -e * 0.01f);
        } else if (crystal.mode == M_MANIFEST) {
            atomicAdd(&cell.charge, e * 0.24f);
            atomicAdd(&cell.gate, e * 0.22f);
            atomicAdd(manifest_delta, e * 0.10f);
        }
    }

    float burn = 0.30f;
    burn += (crystal.mode == M_RUNTIME ? 0.14f : crystal.mode == M_CYCLE ? 0.16f : crystal.mode == M_LOGIC ? 0.18f : 0.22f);
    burn += crystal.energy * 0.20f;
    burn *= cost_scale;
    crystal.pu_stock -= burn;
    atomicAdd(burned_out, burn);
}

__global__ void update_l3_kernel(L3Cell* cells, int length, float phase, int pocket_id) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;

    L3Cell c = cells[idx];
    L3Cell l = cells[wrapi(idx - 1, length)];
    L3Cell r = cells[wrapi(idx + 1, length)];

    float cycle_gain = 1.0f + 0.14f * sinf(phase);
    float decay = 0.89f + 0.02f * cosf(phase * 0.7f);
    float raw = l.activation * c.left_w + r.activation * c.right_w + c.activation * c.self_w + c.charge * cycle_gain;

    if (c.mode == M_LOGIC) raw = raw * 0.80f;
    else if (c.mode == M_MANIFEST) raw = raw + c.gate * 0.08f;
    else if (c.mode == M_CYCLE) raw = raw + sinf(phase + idx * 0.10f + pocket_id * 0.15f) * 0.06f;

    cells[idx].next_activation = clampf(raw * decay, 0.0f, 1.0f);
    cells[idx].charge *= 0.80f;
    cells[idx].gate *= 0.84f;
    cells[idx].left_w = clampf(cells[idx].left_w, 0.06f, 0.55f);
    cells[idx].right_w = clampf(cells[idx].right_w, 0.06f, 0.55f);
    cells[idx].self_w = clampf(cells[idx].self_w, 0.50f, 0.60f);
}

__global__ void commit_l3_kernel(L3Cell* cells, int length) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= length) return;
    cells[idx].activation = cells[idx].next_activation;
}

__global__ void summarize_processes_kernel(const EncodeProcess* processes, int count, Summary* summary) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= count) return;
    const EncodeProcess& p = processes[idx];
    if (p.alive) atomicAdd(&summary->alive, 1);
    if (p.success) atomicAdd(&summary->success, 1);
    if (!p.alive && !p.success) atomicAdd(&summary->failed, 1);
    if (p.emitted) atomicAdd(&summary->emitted, 1);
    atomicAdd(&summary->observe_raw, p.observe_raw_calls);
    atomicAdd(&summary->observe_calm, p.observe_calm_calls);
    atomicAdd(&summary->choose_raw, p.choose_raw_calls);
    atomicAdd(&summary->choose_calm, p.choose_calm_calls);
    atomicAdd(&summary->runtime, p.runtime_calls);
    atomicAdd(&summary->age_sum, (float)p.age);
    atomicAdd(&summary->burn_sum, p.burn);
    atomicAdd(&summary->coherence_sum, p.calm_coherence);
}

static float readout_host(const std::vector<L3Cell>& cells) {
    int length = (int)cells.size();
    int out_count = std::max(4, (int)std::floor(length * 0.12f));
    int start_idx = std::max(0, length - out_count);
    float sum = 0.0f;
    for (int i = start_idx; i < length; ++i) sum += cells[i].activation;
    return sum / (float)out_count;
}

static void init_processes(std::vector<EncodeProcess>& out, int count, int seed) {
    out.resize(count);
    unsigned int rng = (unsigned int)seed;
    for (int i = 0; i < count; ++i) {
        EncodeProcess p{};
        p.id = i + 1;
        p.x = 1 + (int)std::floor(randf(rng) * 64.0f);
        p.y = 1 + (int)std::floor(randf(rng) * 64.0f);
        p.pu = 42.0f + randf(rng) * 28.0f;
        p.connect_strength = 0.12f + randf(rng) * 0.12f;
        p.raw_noise = 0.45f + randf(rng) * 0.20f;
        p.alive = 1;
        out[i] = p;
    }
}

static void init_l3(std::vector<L3Cell>& out, int length, int seed, int pocket_id) {
    out.resize(length);
    unsigned int rng = (unsigned int)(seed * 17 + pocket_id * 97 + 9);
    for (int i = 0; i < length; ++i) {
        L3Cell c{};
        c.left_w = 0.16f + randf(rng) * 0.12f;
        c.right_w = 0.16f + randf(rng) * 0.12f;
        c.self_w = 0.50f + randf(rng) * 0.10f;
        c.mode = M_RUNTIME;
        out[i] = c;
    }
}

int main(int argc, char** argv) {
    int ticks = argc > 1 ? std::atoi(argv[1]) : DEFAULT_TICKS;
    int process_count = argc > 2 ? std::atoi(argv[2]) : DEFAULT_PROCESS_COUNT;
    int seed = argc > 3 ? std::atoi(argv[3]) : DEFAULT_SEED;
    int l3_count = argc > 4 ? std::atoi(argv[4]) : DEFAULT_L3_COUNT;
    int l3_length = argc > 5 ? std::atoi(argv[5]) : DEFAULT_L3_LENGTH;

    std::vector<EncodeProcess> h_processes;
    init_processes(h_processes, process_count, seed);

    EncodeProcess* d_processes = nullptr;
    Crystal* d_emitted = nullptr;
    int* d_emitted_count = nullptr;
    Summary* d_summary = nullptr;
    check_cuda(cudaMalloc(&d_processes, sizeof(EncodeProcess) * process_count), "malloc d_processes");
    check_cuda(cudaMalloc(&d_emitted, sizeof(Crystal) * process_count), "malloc d_emitted");
    check_cuda(cudaMalloc(&d_emitted_count, sizeof(int)), "malloc d_emitted_count");
    check_cuda(cudaMalloc(&d_summary, sizeof(Summary)), "malloc d_summary");
    check_cuda(cudaMemcpy(d_processes, h_processes.data(), sizeof(EncodeProcess) * process_count, cudaMemcpyHostToDevice), "copy processes");

    std::vector<L3Cell> h_l3_all((size_t)l3_count * l3_length);
    std::vector<L3Cell*> d_l3_ptrs(l3_count, nullptr);
    std::vector<std::vector<Crystal>> active(l3_count);
    std::vector<PocketStats> stats(l3_count);
    std::vector<float> phases(l3_count);

    Crystal* d_active = nullptr;
    int crystal_capacity = std::max(1, process_count * 2);
    check_cuda(cudaMalloc(&d_active, sizeof(Crystal) * crystal_capacity), "malloc d_active");
    float* d_manifest_delta = nullptr;
    float* d_burned = nullptr;
    check_cuda(cudaMalloc(&d_manifest_delta, sizeof(float)), "malloc d_manifest_delta");
    check_cuda(cudaMalloc(&d_burned, sizeof(float)), "malloc d_burned");

    for (int i = 0; i < l3_count; ++i) {
        std::vector<L3Cell> pocket;
        init_l3(pocket, l3_length, seed, i + 1);
        for (int j = 0; j < l3_length; ++j) {
            h_l3_all[(size_t)i * l3_length + j] = pocket[j];
        }
        check_cuda(cudaMalloc(&d_l3_ptrs[i], sizeof(L3Cell) * l3_length), "malloc d_l3 pocket");
        check_cuda(cudaMemcpy(d_l3_ptrs[i], pocket.data(), sizeof(L3Cell) * l3_length, cudaMemcpyHostToDevice), "copy l3 pocket");
        phases[i] = (float)i * 0.23f;
        stats[i] = {};
    }

    std::vector<Crystal> emitted(process_count);
    int threads = 256;
    int process_blocks = (process_count + threads - 1) / threads;
    int l3_blocks = (l3_length + threads - 1) / threads;
    float cost_scale = 1.0f / (float)l3_count;

    std::printf("cuda eva00 multi-l3 cost stand\n");
    std::printf("ticks=%d processes=%d l3_count=%d l3_length=%d seed=%d\n", ticks, process_count, l3_count, l3_length, seed);

    for (int tick = 1; tick <= ticks; ++tick) {
        check_cuda(cudaMemset(d_emitted_count, 0, sizeof(int)), "memset emitted_count");
        tick_encode_kernel<<<process_blocks, threads>>>(d_processes, process_count, tick, seed, l3_count, l3_length, d_emitted, d_emitted_count);
        check_cuda(cudaGetLastError(), "tick_encode_kernel");
        check_cuda(cudaDeviceSynchronize(), "sync encode");

        int emitted_count = 0;
        check_cuda(cudaMemcpy(&emitted_count, d_emitted_count, sizeof(int), cudaMemcpyDeviceToHost), "copy emitted count");
        if (emitted_count > 0) {
            check_cuda(cudaMemcpy(emitted.data(), d_emitted, sizeof(Crystal) * emitted_count, cudaMemcpyDeviceToHost), "copy emitted crystals");
            for (int i = 0; i < emitted_count; ++i) {
                const Crystal& c = emitted[i];
                active[c.pocket].push_back(c);
                stats[c.pocket].incoming[c.mode] += 1;
            }
        }

        for (int pocket = 0; pocket < l3_count; ++pocket) {
            if (!active[pocket].empty()) {
                if ((int)active[pocket].size() > crystal_capacity) {
                    std::fprintf(stderr, "active crystal overflow: %zu > %d\n", active[pocket].size(), crystal_capacity);
                    std::exit(1);
                }
                check_cuda(cudaMemcpy(d_active, active[pocket].data(), sizeof(Crystal) * active[pocket].size(), cudaMemcpyHostToDevice), "copy active crystals");
                check_cuda(cudaMemset(d_manifest_delta, 0, sizeof(float)), "memset manifest");
                check_cuda(cudaMemset(d_burned, 0, sizeof(float)), "memset burned");

                int crystal_blocks = ((int)active[pocket].size() + threads - 1) / threads;
                apply_l3_crystals_kernel<<<crystal_blocks, threads>>>(d_l3_ptrs[pocket], l3_length, d_active, (int)active[pocket].size(), phases[pocket], cost_scale, d_manifest_delta, d_burned);
                check_cuda(cudaGetLastError(), "apply_l3_crystals");
                check_cuda(cudaMemcpy(active[pocket].data(), d_active, sizeof(Crystal) * active[pocket].size(), cudaMemcpyDeviceToHost), "copy active crystals back");

                float burned_now = 0.0f;
                float manifest_now = 0.0f;
                check_cuda(cudaMemcpy(&burned_now, d_burned, sizeof(float), cudaMemcpyDeviceToHost), "copy burned");
                check_cuda(cudaMemcpy(&manifest_now, d_manifest_delta, sizeof(float), cudaMemcpyDeviceToHost), "copy manifest");
                stats[pocket].burned += burned_now;
                stats[pocket].manifest += manifest_now;
            }

            phases[pocket] += 0.12f + pocket * 0.01f;
            update_l3_kernel<<<l3_blocks, threads>>>(d_l3_ptrs[pocket], l3_length, phases[pocket], pocket + 1);
            check_cuda(cudaGetLastError(), "update_l3_kernel");
            commit_l3_kernel<<<l3_blocks, threads>>>(d_l3_ptrs[pocket], l3_length);
            check_cuda(cudaGetLastError(), "commit_l3_kernel");
            check_cuda(cudaDeviceSynchronize(), "sync l3 pocket");

            check_cuda(cudaMemcpy(h_l3_all.data() + (size_t)pocket * l3_length, d_l3_ptrs[pocket], sizeof(L3Cell) * l3_length, cudaMemcpyDeviceToHost), "copy l3 pocket back");
            std::vector<Crystal> survivors;
            survivors.reserve(active[pocket].size());
            for (const Crystal& c : active[pocket]) {
                if (c.pu_stock > 0.0f) survivors.push_back(c);
                else stats[pocket].exhausted += 1;
            }
            active[pocket].swap(survivors);
        }
    }

    check_cuda(cudaMemset(d_summary, 0, sizeof(Summary)), "memset summary");
    summarize_processes_kernel<<<process_blocks, threads>>>(d_processes, process_count, d_summary);
    check_cuda(cudaGetLastError(), "summarize_processes_kernel");
    check_cuda(cudaDeviceSynchronize(), "sync summary");

    Summary summary{};
    check_cuda(cudaMemcpy(&summary, d_summary, sizeof(Summary), cudaMemcpyDeviceToHost), "copy summary");

    int total_active = 0;
    int total_exhausted = 0;
    float total_manifest = 0.0f;
    float total_burned = 0.0f;
    float total_readout = 0.0f;
    int total_incoming[4] = {0, 0, 0, 0};

    for (int pocket = 0; pocket < l3_count; ++pocket) {
        std::vector<L3Cell> host_pocket(l3_length);
        for (int i = 0; i < l3_length; ++i) host_pocket[i] = h_l3_all[(size_t)pocket * l3_length + i];
        stats[pocket].readout = readout_host(host_pocket);
        stats[pocket].active_count = (int)active[pocket].size();
        for (const Crystal& c : active[pocket]) stats[pocket].active_modes[c.mode] += 1;

        total_active += stats[pocket].active_count;
        total_exhausted += stats[pocket].exhausted;
        total_manifest += stats[pocket].manifest;
        total_burned += stats[pocket].burned;
        total_readout += stats[pocket].readout;
        for (int m = 0; m < 4; ++m) total_incoming[m] += stats[pocket].incoming[m];

        std::printf(
            "l3[%d] :: active=%d exhausted=%d readout=%.4f manifest=%.3f burned=%.1f in=(R:%d C:%d L:%d M:%d) act=(R:%d C:%d L:%d M:%d)\n",
            pocket + 1,
            stats[pocket].active_count,
            stats[pocket].exhausted,
            stats[pocket].readout,
            stats[pocket].manifest,
            stats[pocket].burned,
            stats[pocket].incoming[M_RUNTIME],
            stats[pocket].incoming[M_CYCLE],
            stats[pocket].incoming[M_LOGIC],
            stats[pocket].incoming[M_MANIFEST],
            stats[pocket].active_modes[M_RUNTIME],
            stats[pocket].active_modes[M_CYCLE],
            stats[pocket].active_modes[M_LOGIC],
            stats[pocket].active_modes[M_MANIFEST]
        );
    }

    std::printf("summary :: alive=%d success=%d failed=%d emitted=%d\n", summary.alive, summary.success, summary.failed, summary.emitted);
    std::printf("process_avg :: age=%.2f burn=%.2f coherence=%.4f\n",
        summary.age_sum / process_count,
        summary.burn_sum / process_count,
        summary.coherence_sum / process_count
    );
    std::printf("calls :: observe_raw=%d choose_raw=%d observe_calm=%d choose_calm=%d runtime=%d\n",
        summary.observe_raw, summary.choose_raw, summary.observe_calm, summary.choose_calm, summary.runtime
    );
    std::printf(
        "l3_total :: active=%d exhausted=%d avg_readout=%.4f manifest=%.3f burned=%.1f in=(R:%d C:%d L:%d M:%d)\n",
        total_active,
        total_exhausted,
        total_readout / l3_count,
        total_manifest,
        total_burned,
        total_incoming[M_RUNTIME],
        total_incoming[M_CYCLE],
        total_incoming[M_LOGIC],
        total_incoming[M_MANIFEST]
    );

    check_cuda(cudaFree(d_processes), "free d_processes");
    check_cuda(cudaFree(d_emitted), "free d_emitted");
    check_cuda(cudaFree(d_emitted_count), "free d_emitted_count");
    check_cuda(cudaFree(d_summary), "free d_summary");
    check_cuda(cudaFree(d_active), "free d_active");
    check_cuda(cudaFree(d_manifest_delta), "free d_manifest_delta");
    check_cuda(cudaFree(d_burned), "free d_burned");
    for (int i = 0; i < l3_count; ++i) check_cuda(cudaFree(d_l3_ptrs[i]), "free d_l3 pocket");
    return 0;
}
