local DEFAULT_L1_RING = 4096
local DEFAULT_L1_CW = 256
local DEFAULT_TICKS = 128
local DEFAULT_SEED = 12345

local L2_DIRS = { "E", "W", "NE", "NW", "SE", "SW" }
local L2_GLYPH = {
  OBSERVE = "O",
  CHOOSE = "C",
  ENCODE = "E",
  RUNTIME = "R",
}
local L3_GLYPH = {
  RUNTIME = "R",
  CYCLE = "Y",
  LOGIC = "L",
  MANIFEST = "M",
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function wrap(v, n)
  return ((v - 1) % n) + 1
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
  local base = math.max(24, math.floor(math.sqrt(area) * 1.8))
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
    }
  end
  return cells
end

local function render_l2_kinds(grid, width, height)
  local rows = math.min(height, 10)
  local cols = math.min(width, 24)
  for y = 1, rows do
    local line = {}
    if y % 2 == 0 then line[#line + 1] = " " end
    for x = 1, cols do
      line[#line + 1] = L2_GLYPH[grid[y][x].kind]
      line[#line + 1] = " "
    end
    if cols < width then line[#line + 1] = "..." end
    print(table.concat(line))
  end
  if rows < height then print("...") end
end

local function render_l3_modes(cells, length)
  local cols = math.min(length, 48)
  local chars = {}
  for i = 1, cols do
    chars[#chars + 1] = L3_GLYPH[cells[i].mode]
  end
  if cols < length then chars[#chars + 1] = "..." end
  print(table.concat(chars))
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

local function l3_feedback(state, y)
  local topness = (y - 1) / math.max(1, state.l2_height - 1)
  return topness * math.min(state.l3_feedback_ceiling, state.manifest / 200.0)
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

local function spawn_crystal(state, tick, x, y, mode, raw)
  local target = ((x * 11 + y * 7 + tick * 3) % state.l3_length) + 1
  local energy = clamp(raw, 0.25, 1.4)
  local pu_stock = math.floor(6 + energy * 14 + state.l2[y][x].stability * 2)
  local crystal = {
    mode = mode,
    target = target,
    span = 1 + ((x + y + tick) % 2),
    energy = energy,
    pu_stock = pu_stock,
    pu_initial = pu_stock,
    age = 0,
  }
  state.l3_active[#state.l3_active + 1] = crystal
  state.metrics.l3_spawned = state.metrics.l3_spawned + 1
  state.metrics.spawn_modes[mode] = state.metrics.spawn_modes[mode] + 1
end

local function step_l2(state, tick)
  local collapse = 0
  local encoded = 0

  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      local cell = state.l2[y][x]
      local neigh = l2_neighbor_sum(state, x, y)
      local raw = cell.activation * cell.decay + neigh + l1_pressure(state, cell, x, y, tick) + l3_feedback(state, y)
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
          if has_runtime and has_choose and ((tick + x + y) % 3 == 0) then
            local mode = l2_to_l3_mode(cell, raw, neigh, y, state.l2_height)
            spawn_crystal(state, tick, x, y, mode, raw)
            cell.stability = 0
            cell.encoded = cell.encoded + 1
            encoded = encoded + 1
          end
        end

      elseif cell.kind == "RUNTIME" then
        next_act = raw * 0.93 + math.min(0.08, state.manifest * 0.0012)
      end

      cell.next_activation = clamp(next_act, 0.0, 1.25)
    end
  end

  for y = 1, state.l2_height do
    for x = 1, state.l2_width do
      local cell = state.l2[y][x]
      cell.activation = cell.next_activation
    end
  end

  state.metrics.l2_collapse = state.metrics.l2_collapse + collapse
  state.metrics.l2_encoded = state.metrics.l2_encoded + encoded
end

local function l3_affect_indices(state, crystal)
  local indices = { crystal.target }
  if crystal.span >= 2 then
    indices[#indices + 1] = wrap(crystal.target + 1, state.l3_length)
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

local function apply_l3_crystal(state, crystal)
  local strength = clamp(crystal.pu_stock / math.max(1.0, crystal.pu_initial), 0.12, 1.0)
  local indices = l3_affect_indices(state, crystal)

  for _, idx in ipairs(indices) do
    local cell = state.l3[idx]
    local e = crystal.energy * strength
    cell.mode = crystal.mode
    cell.age = cell.age + 1

    if crystal.mode == "RUNTIME" then
      cell.charge = cell.charge + e * 0.90
      cell.self_w = clamp(cell.self_w + e * 0.015, 0.30, 0.88)
    elseif crystal.mode == "CYCLE" then
      cell.charge = cell.charge + math.sin(state.l3_phase + idx * 0.07) * e * 0.55
      cell.gate = clamp(cell.gate + e * 0.18, 0.0, 1.0)
    elseif crystal.mode == "LOGIC" then
      cell.charge = cell.charge * (1.0 - e * 0.22)
      cell.left_w = clamp(cell.left_w - e * 0.012, 0.05, 0.60)
      cell.right_w = clamp(cell.right_w - e * 0.012, 0.05, 0.60)
    elseif crystal.mode == "MANIFEST" then
      cell.charge = cell.charge + e * 0.30
      cell.gate = clamp(cell.gate + e * 0.35, 0.0, 1.0)
      state.manifest = state.manifest + e * 0.14
    end
  end
end

local function step_l3(state)
  state.l3_phase = state.l3_phase + state.l3_cycle_speed
  local survivors = {}

  for _, crystal in ipairs(state.l3_active) do
    apply_l3_crystal(state, crystal)
    local burn = l3_burn_cost(crystal)
    crystal.pu_stock = crystal.pu_stock - burn
    crystal.age = crystal.age + 1
    state.metrics.l3_burned = state.metrics.l3_burned + burn
    if crystal.pu_stock > 0 then
      survivors[#survivors + 1] = crystal
    else
      state.l3_exhausted[#state.l3_exhausted + 1] = crystal
    end
  end
  state.l3_active = survivors

  local cycle_gain = 1.0 + 0.16 * math.sin(state.l3_phase)
  local decay = 0.88 + 0.03 * math.cos(state.l3_phase * 0.7)

  for i = 1, state.l3_length do
    local cell = state.l3[i]
    local left = state.l3[wrap(i - 1, state.l3_length)]
    local right = state.l3[wrap(i + 1, state.l3_length)]
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
      raw = raw + math.sin(state.l3_phase + i * 0.11) * 0.08
    end

    cell.next_activation = clamp(raw * decay, 0.0, 1.0)
    cell.charge = cell.charge * 0.78
    cell.gate = cell.gate * 0.86
  end

  for i = 1, state.l3_length do
    local cell = state.l3[i]
    cell.activation = cell.next_activation
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
    sum = sum + math.abs(state.l3[i].activation) + math.abs(state.l3[i].charge)
  end
  return sum
end

local function active_pu(state)
  local sum = 0.0
  for _, crystal in ipairs(state.l3_active) do
    sum = sum + math.max(0.0, crystal.pu_stock)
  end
  return sum
end

local function build_state(l1_ring, l1_cw, ticks, seed)
  local l2_width, l2_height = derive_l2_shape(l1_ring, l1_cw)
  local l3_length = derive_l3_length(l2_width, l2_height, l1_cw)
  local pu_max = l2_width * l2_height

  return {
    seed = seed,
    ticks = ticks,
    l1_ring = l1_ring,
    l1_cw = l1_cw,
    l1_gain = 0.20 + math.log(math.max(1, l1_cw), 2) * 0.014,
    l3_feedback_ceiling = 0.05 + math.log(math.max(1, l1_cw), 2) * 0.005,
    l2_width = l2_width,
    l2_height = l2_height,
    l3_length = l3_length,
    pu_max = pu_max,
    l2 = build_l2(l2_width, l2_height, seed),
    l3 = build_l3(l3_length, seed),
    l3_active = {},
    l3_exhausted = {},
    l3_phase = 0.0,
    l3_cycle_speed = 0.11,
    manifest = 0.0,
    metrics = {
      l2_collapse = 0,
      l2_encoded = 0,
      l3_spawned = 0,
      l3_burned = 0.0,
      spawn_modes = {
        RUNTIME = 0,
        CYCLE = 0,
        LOGIC = 0,
        MANIFEST = 0,
      },
    },
  }
end

local function main()
  local l1_ring = tonumber(arg[1]) or DEFAULT_L1_RING
  local l1_cw = tonumber(arg[2]) or DEFAULT_L1_CW
  local ticks = tonumber(arg[3]) or DEFAULT_TICKS
  local seed = tonumber(arg[4]) or DEFAULT_SEED

  local state = build_state(l1_ring, l1_cw, ticks, seed)

  print(string.format(
    "Eva.00 stand :: l1_ring=%d l1_cw=%d -> l2=%dx%d l3=%d pu_max=%d ticks=%d seed=%d",
    l1_ring, l1_cw, state.l2_width, state.l2_height, state.l3_length, state.pu_max, ticks, seed
  ))
  print("")
  print("L2 kinds:")
  render_l2_kinds(state.l2, state.l2_width, state.l2_height)
  print("")
  print("L3 initial modes:")
  render_l3_modes(state.l3, state.l3_length)
  print("")

  for tick = 1, ticks do
    step_l2(state, tick)
    step_l3(state)

    if tick == 1 or tick == ticks or tick % 16 == 0 then
      print(string.format(
        "tick=%d l2_encoded=%d l3_active=%d l3_exhausted=%d active_pu=%.1f readout=%.4f energy=%.2f manifest=%.3f",
        tick,
        state.metrics.l2_encoded,
        #state.l3_active,
        #state.l3_exhausted,
        active_pu(state),
        l3_readout(state),
        l3_energy(state),
        state.manifest
      ))
    end
  end

  print("")
  print("Spawn modes:")
  print(string.format(
    "RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d",
    state.metrics.spawn_modes.RUNTIME,
    state.metrics.spawn_modes.CYCLE,
    state.metrics.spawn_modes.LOGIC,
    state.metrics.spawn_modes.MANIFEST
  ))
  print(string.format(
    "Totals :: collapse=%d encoded=%d spawned=%d exhausted=%d burned=%.1f final_readout=%.4f final_manifest=%.3f",
    state.metrics.l2_collapse,
    state.metrics.l2_encoded,
    state.metrics.l3_spawned,
    #state.l3_exhausted,
    state.metrics.l3_burned,
    l3_readout(state),
    state.manifest
  ))
  print("L3 final modes:")
  render_l3_modes(state.l3, state.l3_length)
end

main()
