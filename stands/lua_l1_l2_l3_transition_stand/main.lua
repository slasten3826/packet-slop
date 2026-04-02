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

local function seed_ring_from_tokens(token_ids)
  local ring_size = #token_ids
  local core = {}
  local trace = {}
  local phase = build_phase(ring_size)
  local rotated = rotate_tokens(token_ids, math.max(1, math.floor(ring_size / 17)))
  for i = 1, ring_size do
    local v = rotated[i] % MOD
    core[i] = v
    trace[i] = crazy(v, phase[i])
  end
  return core, trace, phase
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

local function fingerprint(core, trace, carry, pos)
  local h = carry % MOD
  h = crazy(h, core[pos])
  h = crazy(h, trace[pos])
  h = crazy(h, pos - 1)
  return h
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

local function derive_l2_shape(l1_ring, l1_cw)
  local base = math.max(8, math.floor(math.sqrt(l1_ring) / 2))
  local pressure_factor = 1.0 + math.log(math.max(1, l1_cw), 2) / 8.0
  local width = math.max(12, math.floor(base * pressure_factor))
  local height = math.max(10, math.floor(width * 0.85))
  return width, height
end

local function derive_l3_length(l2_width, l2_height, l1_cw)
  local area = l2_width * l2_height
  local base = math.max(24, math.floor(math.sqrt(area) * 2.1))
  local pressure = 1.0 + math.log(math.max(1, l1_cw), 2) / 16.0
  return math.max(24, math.floor(base * pressure))
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
  local phase = (x + 2 * y) % 3
  if phase == 0 then
    return "OBSERVE"
  elseif phase == 1 then
    return "CHOOSE"
  end
  return "ENCODE"
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
          CHOOSE = 0.46,
          ENCODE = 0.56,
        })[kind],
        decay = ({
          OBSERVE = 0.84,
          CHOOSE = 0.81,
          ENCODE = 0.88,
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
      mode = "CYCLE",
      gate = 0.0,
      history = 0.0,
      shop_stock = 0.0,
      age = 0,
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

local function l1_pressure(state, x, y, tick)
  local depth = 1.0 - ((y - 1) / math.max(1, state.l2_height - 1))
  local noise = hash_noise(x, y, tick, state.seed)
  local spike = noise > 0.86 and (noise - 0.86) * 1.6 or 0.0
  return depth * state.l1_gain + spike
end

local function l3_feedback(state, y)
  local topness = (y - 1) / math.max(1, state.l2_height - 1)
  return topness * math.min(state.feedback_ceiling, state.manifest / 250.0)
end

local function choose_l3_mode(raw, neigh, surplus)
  local conflict = math.abs(raw - neigh)
  if surplus > 0.22 then
    return "RUNTIME"
  elseif conflict > 0.18 then
    return "LOGIC"
  end
  return "CYCLE"
end

local function spawn_encoded_crystal(state, tick, x, y, mode, raw, coherence)
  local target = ((x * 11 + y * 7 + tick * 3) % state.l3_length) + 1
  local energy = clamp(raw, 0.20, 1.30)
  local pu_stock = math.floor(5 + energy * 12 + coherence * 4)
  state.l3_active[#state.l3_active + 1] = {
    mode = mode,
    target = target,
    energy = energy,
    pu_stock = pu_stock,
    pu_initial = pu_stock,
    coherence = coherence,
    age = 0,
  }
  state.metrics.spawned = state.metrics.spawned + 1
  state.metrics.spawn_modes[mode] = state.metrics.spawn_modes[mode] + 1
end

local function step_l2(state, tick)
  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      local cell = state.l2[y][x]
      local neigh = l2_neighbor_sum(state, x, y)
      local raw = cell.activation * cell.decay + neigh + l1_pressure(state, x, y, tick) + l3_feedback(state, y)
      local next_act = raw

      if cell.kind == "OBSERVE" then
        next_act = raw * 0.91
      elseif cell.kind == "CHOOSE" then
        next_act = raw - math.max(0.0, neigh * 0.35)
        if next_act > cell.threshold then
          state.metrics.collapse = state.metrics.collapse + 1
        end
      elseif cell.kind == "ENCODE" then
        if raw > cell.threshold then
          cell.stability = cell.stability + 1
        else
          cell.stability = math.max(0, cell.stability - 1)
        end
        next_act = raw
        local surplus = raw - cell.threshold
        if cell.stability >= 3 and surplus > 0.05 then
          local mode = choose_l3_mode(raw, neigh, surplus)
          local coherence = clamp(cell.stability / 6.0, 0.0, 1.0)
          spawn_encoded_crystal(state, tick, x, y, mode, raw, coherence)
          cell.stability = 1
          cell.encoded = cell.encoded + 1
          state.metrics.encoded = state.metrics.encoded + 1
          next_act = raw * 0.70
        end
      end

      cell.next_activation = clamp(next_act, 0.0, 1.2)
    end
  end

  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      state.l2[y][x].activation = state.l2[y][x].next_activation
    end
  end
end

local function l3_burn_cost(crystal)
  local base = 0.18 + crystal.energy * 0.30
  local mode_cost = ({
    CYCLE = 0.18,
    LOGIC = 0.24,
    RUNTIME = 0.28,
  })[crystal.mode]
  return base + mode_cost
end

local function apply_l3_crystal(state, crystal)
  local cell = state.l3[crystal.target]
  local strength = clamp(crystal.pu_stock / math.max(1.0, crystal.pu_initial), 0.10, 1.0)
  local e = crystal.energy * strength
  cell.mode = crystal.mode
  cell.age = cell.age + 1

  if crystal.mode == "CYCLE" then
    cell.charge = cell.charge + math.sin(state.l3_phase + crystal.target * 0.09) * e * 0.60
    cell.history = cell.history + e * 0.04
  elseif crystal.mode == "LOGIC" then
    cell.charge = cell.charge + e * 0.12
    cell.gate = clamp(cell.gate + e * 0.20, 0.0, 1.0)
  elseif crystal.mode == "RUNTIME" then
    cell.shop_stock = cell.shop_stock + e * 0.70
    cell.history = cell.history + e * 0.10
    cell.gate = clamp(cell.gate + e * 0.28, 0.0, 1.0)
  end
end

local function runtime_maintenance_cost(cell)
  -- Runtime is a paid storage/vitrine mode, not a free default life mode.
  local base = 0.56
  local stock_cost = math.min(0.42, cell.shop_stock * 0.010)
  local history_cost = math.min(0.18, cell.history * 0.004)
  return base + stock_cost + history_cost
end

local function step_l3(state)
  state.l3_phase = state.l3_phase + state.l3_cycle_speed

  local survivors = {}
  for _, crystal in ipairs(state.l3_active) do
    apply_l3_crystal(state, crystal)
    local burn = l3_burn_cost(crystal)
    crystal.pu_stock = crystal.pu_stock - burn
    crystal.age = crystal.age + 1
    state.metrics.burned = state.metrics.burned + burn
    if crystal.pu_stock > 0 then
      survivors[#survivors + 1] = crystal
    else
      state.l3_exhausted[#state.l3_exhausted + 1] = crystal
    end
  end
  state.l3_active = survivors

  local cycle_gain = 1.0 + 0.16 * math.sin(state.l3_phase)
  local decay = 0.89 + 0.03 * math.cos(state.l3_phase * 0.7)
  local runtime_cells_now = 0

  for i = 1, state.l3_length do
    local cell = state.l3[i]
    local left = state.l3[wrap(i - 1, state.l3_length)]
    local right = state.l3[wrap(i + 1, state.l3_length)]
    local raw =
      left.activation * cell.left_w +
      right.activation * cell.right_w +
      cell.activation * cell.self_w +
      cell.charge * cycle_gain

    if cell.mode == "CYCLE" then
      raw = raw + math.sin(state.l3_phase + i * 0.11) * 0.08
    elseif cell.mode == "LOGIC" then
      raw = (raw * (0.74 + cell.gate * 0.08)) + cell.gate * 0.03
    elseif cell.mode == "RUNTIME" then
      runtime_cells_now = runtime_cells_now + 1
      raw = raw * 0.92 + math.min(0.20, cell.shop_stock * 0.02) + math.min(0.10, cell.history * 0.01)
      state.manifest = state.manifest + math.min(0.05, cell.shop_stock * 0.003)
    end

    cell.next_activation = clamp(raw * decay, 0.0, 1.0)
    cell.charge = cell.charge * 0.80
    cell.gate = cell.gate * 0.88
    cell.history = cell.history * 0.98
    cell.shop_stock = cell.shop_stock * 0.985
  end

  for i = 1, state.l3_length do
    state.l3[i].activation = state.l3[i].next_activation
  end

  state.metrics.runtime_cells = runtime_cells_now
  for i = 1, state.l3_length do
    local cell = state.l3[i]
    if cell.mode == "RUNTIME" and cell.shop_stock > 0.0 then
      local cost = runtime_maintenance_cost(cell)
      cell.shop_stock = math.max(0.0, cell.shop_stock - cost)
      state.metrics.runtime_burned = state.metrics.runtime_burned + cost
      if cell.shop_stock <= 0.0 and cell.history < 0.02 then
        cell.mode = "CYCLE"
      end
    end
  end
end

local function l3_readout(state)
  local start_idx = math.max(1, state.l3_length - math.max(4, math.floor(state.l3_length * 0.1)) + 1)
  local sum = 0.0
  local n = 0
  for i = start_idx, state.l3_length do
    sum = sum + state.l3[i].activation
    n = n + 1
  end
  return sum / math.max(1, n)
end

local function l3_energy(state)
  local sum = 0.0
  for i = 1, state.l3_length do
    local cell = state.l3[i]
    sum = sum + math.abs(cell.activation) + math.abs(cell.charge) + math.abs(cell.shop_stock)
  end
  return sum
end

local function runtime_cells(state)
  local count = 0
  for i = 1, state.l3_length do
    if state.l3[i].mode == "RUNTIME" then
      count = count + 1
    end
  end
  return count
end

local function build_state(l1_ring, l1_cw, seed)
  local l2_width, l2_height = derive_l2_shape(l1_ring, l1_cw)
  local l3_length = derive_l3_length(l2_width, l2_height, l1_cw)
  return {
    seed = seed,
    l1_ring = l1_ring,
    l1_cw = l1_cw,
    l1_gain = 0.20 + math.log(math.max(1, l1_cw), 2) * 0.014,
    feedback_ceiling = 0.05 + math.log(math.max(1, l1_cw), 2) * 0.005,
    l2_width = l2_width,
    l2_height = l2_height,
    l3_length = l3_length,
    l2 = build_l2(l2_width, l2_height, seed),
    l3 = build_l3(l3_length, seed),
    l3_active = {},
    l3_exhausted = {},
    l3_phase = 0.0,
    l3_cycle_speed = 0.11,
    manifest = 0.0,
    metrics = {
      collapse = 0,
      encoded = 0,
      spawned = 0,
      burned = 0.0,
      runtime_burned = 0.0,
      runtime_cells = 0,
      spawn_modes = {
        CYCLE = 0,
        LOGIC = 0,
        RUNTIME = 0,
      },
    },
  }
end

local function print_usage()
  io.write("usage: lua main.lua <bootstrap_dump.lua> [l1_ticks] [l23_ticks]\n")
end

local dump_path = arg[1]
if not dump_path then
  print_usage()
  os.exit(1)
end

local ok, bootstrap = pcall(dofile, dump_path)
if not ok then
  io.stderr:write("failed to load bootstrap dump: " .. tostring(bootstrap) .. "\n")
  os.exit(1)
end

local ring = #bootstrap.token_ids
local l1_ticks = tonumber(arg[2] or tostring(ring * 2))
local l23_ticks = tonumber(arg[3] or "160")
local l1_cw = 1
local core, trace, phase = seed_ring_from_tokens(bootstrap.token_ids)
local l1 = {
  ring_size = ring,
  core = core,
  trace = trace,
  phase = phase,
  carry = bootstrap.token_ids[1] % MOD,
  pos = 1,
}

for _ = 1, l1_ticks do
  tick_l1_c(l1)
end

local l1_fp = fingerprint(l1.core, l1.trace, l1.carry, l1.pos)
local state = build_state(ring, l1_cw, l1_fp)

print("l1_l2_l3_transition stand")
print(string.format("model=%s", tostring(bootstrap.model_path)))
print(string.format("ring=%d l1_ticks=%d l23_ticks=%d l1_cw=%d", ring, l1_ticks, l23_ticks, l1_cw))
print(string.format("l1_fp=%d l2=%dx%d l3=%d", l1_fp, state.l2_width, state.l2_height, state.l3_length))

for tick = 1, l23_ticks do
  step_l2(state, tick)
  step_l3(state)
  if tick == 1 or tick == l23_ticks or tick % 16 == 0 then
    print(string.format(
      "tick=%d encoded=%d active=%d exhausted=%d runtime_cells=%d readout=%.4f energy=%.2f manifest=%.3f",
      tick,
      state.metrics.encoded,
      #state.l3_active,
      #state.l3_exhausted,
      state.metrics.runtime_cells,
      l3_readout(state),
      l3_energy(state),
      state.manifest
    ))
  end
end

print("")
print(string.format(
  "Totals :: collapse=%d encoded=%d spawned=%d exhausted=%d burned=%.1f runtime_burned=%.1f readout=%.4f manifest=%.3f runtime_cells=%d",
  state.metrics.collapse,
  state.metrics.encoded,
  state.metrics.spawned,
  #state.l3_exhausted,
  state.metrics.burned,
  state.metrics.runtime_burned,
  l3_readout(state),
  state.manifest,
  state.metrics.runtime_cells
))
print(string.format(
  "spawn_modes :: CYCLE=%d LOGIC=%d RUNTIME=%d",
  state.metrics.spawn_modes.CYCLE,
  state.metrics.spawn_modes.LOGIC,
  state.metrics.spawn_modes.RUNTIME
))
