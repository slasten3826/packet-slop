local MOD = 59049
local L2_DIRS = { "E", "W", "NE", "NW", "SE", "SW" }

local function crazy(a, d)
  local table3 = {
    {1, 0, 0},
    {1, 0, 2},
    {2, 2, 1},
  }
  local result = 0
  local power = 1
  local aa = a
  local dd = d
  for _ = 1, 10 do
    local ax = aa % 3
    local dx = dd % 3
    result = result + table3[dx + 1][ax + 1] * power
    aa = math.floor(aa / 3)
    dd = math.floor(dd / 3)
    power = power * 3
  end
  return result % MOD
end

local function wrap(v, n)
  return ((v - 1) % n) + 1
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function build_phase(ring_size)
  local phase = {}
  for i = 1, ring_size do
    phase[i] = (i - 1) % 3
  end
  return phase
end

local function rotate_tokens(token_ids, offset)
  local n = #token_ids
  local rotated = {}
  for i = 1, n do
    local src = ((i - 1 + offset) % n) + 1
    rotated[i] = token_ids[src]
  end
  return rotated
end

local function seed_ring_from_tokens(token_ids, core_idx)
  local ring_size = #token_ids
  local core = {}
  local trace = {}
  local phase = build_phase(ring_size)
  local offset = (core_idx - 1) * math.max(1, math.floor(ring_size / 17))
  local rotated = rotate_tokens(token_ids, offset)
  for i = 1, ring_size do
    local v = (rotated[i] + (core_idx - 1)) % MOD
    core[i] = v
    trace[i] = crazy(v, (phase[i] + core_idx - 1) % 3)
  end
  return core, trace, phase
end

local function fingerprint(core, trace, carry, pos)
  local h = carry % MOD
  h = crazy(h, core[pos])
  h = crazy(h, trace[pos])
  h = crazy(h, pos - 1)
  return h
end

local function distinct_count(arr)
  local seen = {}
  local count = 0
  for i = 1, #arr do
    local v = arr[i]
    if not seen[v] then
      seen[v] = true
      count = count + 1
    end
  end
  return count
end

local function trace_density(trace)
  local active = 0
  for i = 1, #trace do
    if trace[i] ~= 0 then
      active = active + 1
    end
  end
  return active
end

local function snapshot_l1(state)
  return {
    fp = fingerprint(state.core, state.trace, state.carry, state.pos),
    distinct_core = distinct_count(state.core),
    distinct_trace = distinct_count(state.trace),
    trace_density = trace_density(state.trace),
  }
end

local function tick_l1_c(state)
  local p = state.pos
  local q = (p % state.ring_size) + 1
  local bias = crazy(state.phase[p], (p - 1) % MOD)
  local operand = crazy(crazy(state.core[p], state.trace[p]), bias)
  local res = crazy(state.carry, operand)
  state.carry = res
  state.core[p] = crazy(res, state.trace[p])
  state.trace[p] = crazy(state.trace[p], bias)
  state.pos = q
end

local function build_l1_states(token_ids, m)
  local states = {}
  local ring_size = #token_ids
  for idx = 1, m do
    local core, trace, phase = seed_ring_from_tokens(token_ids, idx)
    states[idx] = {
      ring_size = ring_size,
      core = core,
      trace = trace,
      phase = phase,
      carry = (token_ids[1] + idx - 1) % MOD,
      pos = 1,
      idx = idx,
    }
  end
  return states
end

local function derive_l2_shape(l1_ring, l1_cw)
  local base = math.max(8, math.floor(math.sqrt(l1_ring) / 2))
  local pressure_factor = 1.0 + math.log(math.max(1, l1_cw), 2) / 8.0
  local width = math.max(12, math.floor(base * pressure_factor))
  local height = math.max(10, math.floor(width * 0.85))
  return width, height
end

local function derive_shared_l3_length(l2_width, l2_height, l1_cw, m)
  local area = l2_width * l2_height
  local base = math.max(24, math.floor(math.sqrt(area) * 1.8))
  local pressure = 1.0 + math.log(math.max(1, l1_cw), 2) / 16.0
  return math.max(24, math.floor(base * pressure) * m)
end

local function make_rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = 1 end
  return function()
    state = (state * 48271) % 2147483647
    return state
  end
end

local function randf(rng)
  return rng() / 2147483647
end

local function hash_noise(x, y, tick, seed)
  local v = x * 92821 + y * 68917 + tick * 1237 + seed * 17
  v = (v ~ (v << 13)) & 0x7fffffff
  v = (v ~ (v >> 17)) & 0x7fffffff
  v = (v ~ (v << 5)) & 0x7fffffff
  return (v % 1000) / 1000.0
end

local function neighbor(x, y, dir, width, height)
  local even = (y % 2 == 0)
  if dir == "E" then
    return wrap(x + 1, width), y
  elseif dir == "W" then
    return wrap(x - 1, width), y
  elseif dir == "NE" then
    return wrap(x + (even and 1 or 0), width), wrap(y - 1, height)
  elseif dir == "NW" then
    return wrap(x + (even and 0 or -1), width), wrap(y - 1, height)
  elseif dir == "SE" then
    return wrap(x + (even and 1 or 0), width), wrap(y + 1, height)
  elseif dir == "SW" then
    return wrap(x + (even and 0 or -1), width), wrap(y + 1, height)
  end
  return x, y
end

local function l2_kind_for_position(x, y)
  local phase = (x + 2 * y) % 4
  if phase == 0 then
    return "OBSERVE"
  elseif phase == 1 then
    return "CHOOSE"
  elseif phase == 2 then
    return "ENCODE"
  end
  return "RUNTIME"
end

local function build_l2(width, height, seed)
  local rng = make_rng(seed)
  local grid = {}
  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      local kind = l2_kind_for_position(x, y)
      local weights = {}
      for _, dir in ipairs(L2_DIRS) do
        weights[dir] = 0.14 + randf(rng) * 0.42
      end
      grid[y][x] = {
        kind = kind,
        activation = 0.0,
        next_activation = 0.0,
        stability = 0,
        encoded = 0,
        threshold = ({
          OBSERVE = 0.28,
          CHOOSE = 0.48,
          ENCODE = 0.58,
          RUNTIME = 0.40,
        })[kind],
        decay = ({
          OBSERVE = 0.83,
          CHOOSE = 0.80,
          ENCODE = 0.87,
          RUNTIME = 0.91,
        })[kind],
        weights = weights,
      }
    end
  end
  return grid
end

local function build_l3(length, seed)
  local rng = make_rng(seed * 31 + 7)
  local cells = {}
  for i = 1, length do
    cells[i] = {
      activation = 0.0,
      next_activation = 0.0,
      charge = 0.0,
      left_w = 0.16 + randf(rng) * 0.14,
      right_w = 0.16 + randf(rng) * 0.14,
      self_w = 0.48 + randf(rng) * 0.14,
      mode = "RUNTIME",
      gate = 0.0,
      age = 0,
      owner = 0,
    }
  end
  return cells
end

local function l2_neighbor_sum(state, x, y)
  local total = 0.0
  local cell = state.l2[y][x]
  for _, dir in ipairs(L2_DIRS) do
    local nx, ny = neighbor(x, y, dir, state.l2_width, state.l2_height)
    total = total + state.l2[ny][nx].activation * cell.weights[dir]
  end
  return total / 6.0
end

local function l1_pressure(state, cell, x, y, tick)
  local depth = 1.0 - ((y - 1) / math.max(1, state.l2_height - 1))
  local noise = hash_noise(x, y, tick, state.seed)
  local spike = noise > 0.86 and (noise - 0.86) * 1.6 or 0.0
  local base = depth * state.l1_gain
  if cell.kind == "OBSERVE" then
    return base + spike
  elseif cell.kind == "CHOOSE" or cell.kind == "ENCODE" then
    return base * 0.55 + spike * 0.6
  end
  return base * 0.12
end

local function l3_feedback(shared, y, height)
  local topness = (y - 1) / math.max(1, height - 1)
  return topness * math.min(shared.feedback_ceiling, shared.manifest / 200.0)
end

local function l2_to_l3_mode(cell, raw, neigh, y, height)
  local topness = (y - 1) / math.max(1, height - 1)
  local conflict = math.abs(raw - neigh)
  local surplus = raw - cell.threshold
  if topness > 0.76 and surplus > 0.18 then
    return "MANIFEST"
  elseif cell.stability >= 5 and surplus > 0.12 then
    return "RUNTIME"
  elseif conflict < 0.11 and surplus > 0.06 then
    return "CYCLE"
  elseif conflict > 0.24 then
    return "LOGIC"
  end
  return "CYCLE"
end

local function build_l2_state(l1_ring, l1_cw, seed)
  local l2_width, l2_height = derive_l2_shape(l1_ring, l1_cw)
  return {
    seed = seed,
    l1_ring = l1_ring,
    l1_cw = l1_cw,
    l1_gain = 0.20 + math.log(math.max(1, l1_cw), 2) * 0.014,
    l2_width = l2_width,
    l2_height = l2_height,
    l2 = build_l2(l2_width, l2_height, seed),
    metrics = {
      l2_collapse = 0,
      l2_encoded = 0,
      l3_spawned = 0,
      spawn_modes = {
        RUNTIME = 0,
        CYCLE = 0,
        LOGIC = 0,
        MANIFEST = 0,
      },
    },
  }
end

local function build_shared_l3(l2_width, l2_height, l1_cw, m, seed)
  local l3_length = derive_shared_l3_length(l2_width, l2_height, l1_cw, m)
  return {
    seed = seed,
    l3_length = l3_length,
    l3 = build_l3(l3_length, seed),
    l3_active = {},
    l3_exhausted = {},
    l3_phase = 0.0,
    l3_cycle_speed = 0.11,
    feedback_ceiling = 0.05 + math.log(math.max(1, l1_cw), 2) * 0.005,
    manifest = 0.0,
    metrics = {
      spawned = 0,
      burned = 0.0,
      spawn_modes = {
        RUNTIME = 0,
        CYCLE = 0,
        LOGIC = 0,
        MANIFEST = 0,
      },
    },
  }
end

local function shared_spawn_crystal(shared, core_idx, tick, x, y, width, mode, raw, stability)
  local segment = math.floor(shared.l3_length / shared.multiplier)
  local segment_start = ((core_idx - 1) * segment) + 1
  local local_target = ((x * 11 + y * 7 + tick * 3) % math.max(1, segment)) + 1
  local target = segment_start + local_target - 1
  target = wrap(target, shared.l3_length)

  local energy = clamp(raw, 0.25, 1.4)
  local pu_stock = math.floor(6 + energy * 14 + stability * 2)
  local crystal = {
    owner = core_idx,
    mode = mode,
    target = target,
    span = 1 + ((x + y + tick + core_idx) % 2),
    energy = energy,
    pu_stock = pu_stock,
    pu_initial = pu_stock,
    age = 0,
  }
  shared.l3_active[#shared.l3_active + 1] = crystal
  shared.metrics.spawned = shared.metrics.spawned + 1
  shared.metrics.spawn_modes[mode] = shared.metrics.spawn_modes[mode] + 1
end

local function step_l2_to_shared_l3(state, shared, core_idx, tick)
  local collapse = 0
  local encoded = 0

  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      local cell = state.l2[y][x]
      local neigh = l2_neighbor_sum(state, x, y)
      local raw = cell.activation * cell.decay + neigh + l1_pressure(state, cell, x, y, tick) + l3_feedback(shared, y, state.l2_height)
      local next_act = raw

      if cell.kind == "OBSERVE" then
        next_act = raw * 0.90
      elseif cell.kind == "CHOOSE" then
        next_act = raw - math.max(0.0, neigh * 0.38)
        if next_act > cell.threshold then
          collapse = collapse + 1
        end
      elseif cell.kind == "ENCODE" then
        if raw > cell.threshold then
          cell.stability = cell.stability + 1
        else
          cell.stability = math.max(0, cell.stability - 1)
        end
        next_act = raw

        if cell.stability >= 3 and raw > cell.threshold + 0.04 then
          local has_runtime = false
          local has_choose = false
          for _, dir in ipairs(L2_DIRS) do
            local nx, ny = neighbor(x, y, dir, state.l2_width, state.l2_height)
            local nk = state.l2[ny][nx].kind
            if nk == "RUNTIME" then has_runtime = true end
            if nk == "CHOOSE" then has_choose = true end
          end
          if has_runtime and has_choose and ((tick + x + y + core_idx) % 3 == 0) then
            local mode = l2_to_l3_mode(cell, raw, neigh, y, state.l2_height)
            shared_spawn_crystal(shared, core_idx, tick, x, y, state.l2_width, mode, raw, cell.stability)
            cell.stability = 0
            cell.encoded = cell.encoded + 1
            encoded = encoded + 1
            state.metrics.l3_spawned = state.metrics.l3_spawned + 1
            state.metrics.spawn_modes[mode] = state.metrics.spawn_modes[mode] + 1
          end
        end
      elseif cell.kind == "RUNTIME" then
        next_act = raw * 0.93 + math.min(0.08, shared.manifest * 0.0012)
      end

      cell.next_activation = clamp(next_act, 0.0, 1.25)
    end
  end

  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      state.l2[y][x].activation = state.l2[y][x].next_activation
    end
  end

  state.metrics.l2_collapse = state.metrics.l2_collapse + collapse
  state.metrics.l2_encoded = state.metrics.l2_encoded + encoded
end

local function l3_affect_indices(shared, crystal)
  local indices = { crystal.target }
  if crystal.span >= 2 then
    indices[#indices + 1] = wrap(crystal.target + 1, shared.l3_length)
  end
  return indices
end

local function l3_burn_cost(crystal)
  local base = 0.18 + crystal.span * 0.05
  local mode_cost = ({
    RUNTIME = 0.18,
    CYCLE = 0.20,
    LOGIC = 0.24,
    MANIFEST = 0.30,
  })[crystal.mode]
  return base + mode_cost + crystal.energy * 0.35
end

local function apply_l3_crystal(shared, crystal)
  local strength = clamp(crystal.pu_stock / math.max(1.0, crystal.pu_initial), 0.12, 1.0)
  local indices = l3_affect_indices(shared, crystal)

  for _, idx in ipairs(indices) do
    local cell = shared.l3[idx]
    local e = crystal.energy * strength
    cell.mode = crystal.mode
    cell.age = cell.age + 1
    cell.owner = crystal.owner

    if crystal.mode == "RUNTIME" then
      cell.charge = cell.charge + e * 0.90
      cell.self_w = clamp(cell.self_w + e * 0.015, 0.30, 0.88)
    elseif crystal.mode == "CYCLE" then
      cell.charge = cell.charge + math.sin(shared.l3_phase + idx * 0.07) * e * 0.55
      cell.gate = clamp(cell.gate + e * 0.18, 0.0, 1.0)
    elseif crystal.mode == "LOGIC" then
      cell.charge = cell.charge * (1.0 - e * 0.22)
      cell.left_w = clamp(cell.left_w - e * 0.012, 0.05, 0.60)
      cell.right_w = clamp(cell.right_w - e * 0.012, 0.05, 0.60)
    elseif crystal.mode == "MANIFEST" then
      cell.charge = cell.charge + e * 0.30
      cell.gate = clamp(cell.gate + e * 0.35, 0.0, 1.0)
      shared.manifest = shared.manifest + e * 0.14
    end
  end
end

local function step_shared_l3(shared)
  shared.l3_phase = shared.l3_phase + shared.l3_cycle_speed
  local survivors = {}

  for _, crystal in ipairs(shared.l3_active) do
    apply_l3_crystal(shared, crystal)
    local burn = l3_burn_cost(crystal)
    crystal.pu_stock = crystal.pu_stock - burn
    crystal.age = crystal.age + 1
    shared.metrics.burned = shared.metrics.burned + burn
    if crystal.pu_stock > 0 then
      survivors[#survivors + 1] = crystal
    else
      shared.l3_exhausted[#shared.l3_exhausted + 1] = crystal
    end
  end
  shared.l3_active = survivors

  local cycle_gain = 1.0 + 0.16 * math.sin(shared.l3_phase)
  local decay = 0.88 + 0.03 * math.cos(shared.l3_phase * 0.7)

  for i = 1, shared.l3_length do
    local cell = shared.l3[i]
    local left = shared.l3[wrap(i - 1, shared.l3_length)]
    local right = shared.l3[wrap(i + 1, shared.l3_length)]
    local raw =
      left.activation * cell.left_w +
      right.activation * cell.right_w +
      cell.activation * cell.self_w +
      cell.charge * cycle_gain

    if cell.mode == "LOGIC" then
      raw = raw * 0.78
    elseif cell.mode == "MANIFEST" then
      raw = raw + cell.gate * 0.10
    elseif cell.mode == "CYCLE" then
      raw = raw + math.sin(shared.l3_phase + i * 0.11) * 0.08
    end

    cell.next_activation = clamp(raw * decay, 0.0, 1.0)
    cell.charge = cell.charge * 0.78
    cell.gate = cell.gate * 0.86
  end

  for i = 1, shared.l3_length do
    shared.l3[i].activation = shared.l3[i].next_activation
  end
end

local function l3_readout(shared)
  local start_idx = math.max(1, shared.l3_length - math.max(4, math.floor(shared.l3_length * 0.1)) + 1)
  local sum = 0.0
  local n = 0
  for i = start_idx, shared.l3_length do
    sum = sum + shared.l3[i].activation
    n = n + 1
  end
  return sum / math.max(1, n)
end

local function l3_energy(shared)
  local sum = 0.0
  for i = 1, shared.l3_length do
    sum = sum + math.abs(shared.l3[i].activation) + math.abs(shared.l3[i].charge)
  end
  return sum
end

local function active_pu(shared)
  local sum = 0.0
  for _, crystal in ipairs(shared.l3_active) do
    sum = sum + math.max(0.0, crystal.pu_stock)
  end
  return sum
end

local function owner_counts(shared)
  local counts = {}
  for i = 1, shared.multiplier do
    counts[i] = 0
  end
  for _, crystal in ipairs(shared.l3_active) do
    counts[crystal.owner] = counts[crystal.owner] + 1
  end
  return counts
end

local function print_usage()
  io.write("usage: lua main.lua <bootstrap_dump.lua> <multiplier> [l1_ticks] [l23_ticks]\n")
end

local dump_path = arg[1]
local m = tonumber(arg[2] or "5")
if not dump_path or not m or m < 1 then
  print_usage()
  os.exit(1)
end

local ok, bootstrap = pcall(dofile, dump_path)
if not ok then
  io.stderr:write("failed to load bootstrap dump: " .. tostring(bootstrap) .. "\n")
  os.exit(1)
end

local ring = #bootstrap.token_ids
local l1_ticks = tonumber(arg[3] or tostring(ring * 2))
local l23_ticks = tonumber(arg[4] or "160")
local l1_cw = 1
local l1_states = build_l1_states(bootstrap.token_ids, m)

print("l1+l2+shared_l3 multiplier stand")
print(string.format("model=%s", tostring(bootstrap.model_path)))
print(string.format("ring=%d multiplier=%d l1_ticks=%d l23_ticks=%d l1_cw=%d", ring, m, l1_ticks, l23_ticks, l1_cw))
print(string.format("prompt_chars=%d", #tostring(bootstrap.prompt)))

for t = 1, l1_ticks do
  for i = 1, #l1_states do
    tick_l1_c(l1_states[i])
  end
end

print("")
print("L1 final snapshots:")
local l2_states = {}
for i = 1, #l1_states do
  local l1_snap = snapshot_l1(l1_states[i])
  print(string.format(
    "core=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d",
    i, l1_snap.fp, l1_snap.trace_density, l1_snap.distinct_core, l1_snap.distinct_trace
  ))
  l2_states[i] = build_l2_state(ring, l1_cw, l1_snap.fp)
end

local shared = build_shared_l3(l2_states[1].l2_width, l2_states[1].l2_height, l1_cw, m, l2_states[1].seed)
shared.multiplier = m

for tick = 1, l23_ticks do
  for i = 1, #l2_states do
    step_l2_to_shared_l3(l2_states[i], shared, i, tick)
  end
  step_shared_l3(shared)

  if tick == 1 or tick == l23_ticks or tick % 16 == 0 then
    local counts = owner_counts(shared)
    print(string.format(
      "tick=%d shared_l3 active=%d exhausted=%d active_pu=%.1f readout=%.4f energy=%.2f manifest=%.3f owners=%d,%d,%d,%d,%d",
      tick,
      #shared.l3_active,
      #shared.l3_exhausted,
      active_pu(shared),
      l3_readout(shared),
      l3_energy(shared),
      shared.manifest,
      counts[1], counts[2], counts[3], counts[4], counts[5]
    ))
  end
end

print("")
print("L2 totals:")
for i = 1, #l2_states do
  local s = l2_states[i]
  print(string.format(
    "core=%d collapse=%d encoded=%d spawned=%d R=%d C=%d L=%d M=%d",
    i,
    s.metrics.l2_collapse,
    s.metrics.l2_encoded,
    s.metrics.l3_spawned,
    s.metrics.spawn_modes.RUNTIME,
    s.metrics.spawn_modes.CYCLE,
    s.metrics.spawn_modes.LOGIC,
    s.metrics.spawn_modes.MANIFEST
  ))
end

print("")
print("Shared L3 totals:")
print(string.format(
  "l3=%d spawned=%d active=%d exhausted=%d burned=%.1f readout=%.4f manifest=%.3f",
  shared.l3_length,
  shared.metrics.spawned,
  #shared.l3_active,
  #shared.l3_exhausted,
  shared.metrics.burned,
  l3_readout(shared),
  shared.manifest
))
print(string.format(
  "spawn_modes :: RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d",
  shared.metrics.spawn_modes.RUNTIME,
  shared.metrics.spawn_modes.CYCLE,
  shared.metrics.spawn_modes.LOGIC,
  shared.metrics.spawn_modes.MANIFEST
))
