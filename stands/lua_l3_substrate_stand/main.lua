local DEFAULT_L1_RING = 4096
local DEFAULT_L1_CW = 256
local DEFAULT_TICKS = 96
local DEFAULT_SEED = 12345

local CRYSTAL_TYPES = { "EXCITE", "INHIBIT", "CONNECT", "RELEASE" }

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

local function derive_l2_shape(l1_ring, l1_cw)
  local base = math.max(8, math.floor(math.sqrt(l1_ring) / 2))
  local pressure_factor = 1.0 + math.log(math.max(1, l1_cw), 2) / 8.0
  local width = math.max(12, math.floor(base * pressure_factor))
  local height = math.max(10, math.floor(width * 0.85))
  return width, height
end

local function derive_pu_capacity(l2_width, l2_height)
  return l2_width * l2_height
end

local function derive_tape_length(l2_width, l2_height, l1_cw)
  local area = l2_width * l2_height
  local base = math.max(24, math.floor(math.sqrt(area) * 2.2))
  local pressure = 1.0 + math.log(math.max(1, l1_cw), 2) / 14.0
  return math.max(24, math.floor(base * pressure))
end

local function derive_queue_length(l2_width, l2_height, l1_cw)
  local area = l2_width * l2_height
  local base = math.max(8, math.floor(math.sqrt(area) / 2.6))
  local pressure = math.max(2, math.floor(math.log(math.max(2, l1_cw), 2)))
  return base + pressure
end

local function build_cells(length, seed)
  local rng = make_rng(seed)
  local cells = {}
  for i = 1, length do
    cells[i] = {
      activation = 0.0,
      next_activation = 0.0,
      left_w = 0.18 + randf(rng) * 0.16,
      right_w = 0.18 + randf(rng) * 0.16,
      self_w = 0.52 + randf(rng) * 0.12,
      bias = (randf(rng) - 0.5) * 0.04,
      charge = 0.0,
      cooldown = 0.0,
    }
  end
  return cells
end

local function crystal_nominal_stock(kind, energy, span)
  local base = {
    EXCITE = 8.0,
    INHIBIT = 8.0,
    CONNECT = 11.0,
    RELEASE = 11.0,
  }
  return base[kind] + energy * 16.0 + span * 2.5
end

local function build_crystal_schedule(queue_len, tape_len, pu_capacity, seed)
  local rng = make_rng(seed * 17 + 11)
  local queue = {}
  local t = 1
  local remaining = math.floor(pu_capacity * 0.72)

  for i = 1, queue_len do
    if remaining <= 8 then
      break
    end

    local kind = CRYSTAL_TYPES[(rng() % #CRYSTAL_TYPES) + 1]
    local target = (rng() % tape_len) + 1
    local energy = 0.10 + randf(rng) * 0.55
    local span = 1 + (rng() % 3)
    local nominal = crystal_nominal_stock(kind, energy, span)
    local pu_stock = math.min(remaining, math.floor(nominal + 0.5))

    queue[#queue + 1] = {
      tick = t,
      kind = kind,
      target = target,
      energy = energy,
      span = span,
      pu_stock = pu_stock,
      pu_initial = pu_stock,
      age = 0,
    }

    remaining = remaining - pu_stock
    t = t + 1 + (rng() % 4)
  end

  return queue, remaining
end

local function affect_indices(state, crystal)
  local affected = { crystal.target }
  if crystal.span >= 2 then
    affected[#affected + 1] = wrap(crystal.target + 1, state.length)
  end
  if crystal.span >= 3 then
    affected[#affected + 1] = wrap(crystal.target - 1, state.length)
  end
  return affected
end

local function apply_crystal_effect(state, crystal, cycle_gain)
  local strength = clamp(crystal.pu_stock / math.max(1.0, crystal.pu_initial), 0.15, 1.0)
  local affected = affect_indices(state, crystal)

  for _, idx in ipairs(affected) do
    local cell = state.cells[idx]
    local energy = crystal.energy * strength

    if crystal.kind == "EXCITE" then
      cell.charge = cell.charge + energy * cycle_gain
    elseif crystal.kind == "INHIBIT" then
      cell.charge = cell.charge - energy * 0.85 * cycle_gain
    elseif crystal.kind == "CONNECT" then
      local delta = energy * 0.025
      cell.left_w = clamp(cell.left_w + delta, 0.05, 0.72)
      cell.right_w = clamp(cell.right_w + delta, 0.05, 0.72)
      cell.self_w = clamp(cell.self_w + delta * 0.6, 0.30, 0.80)
      cell.cooldown = clamp(cell.cooldown + 0.04, 0.0, 1.0)
    elseif crystal.kind == "RELEASE" then
      local delta = energy * 0.025
      cell.left_w = clamp(cell.left_w - delta, 0.05, 0.72)
      cell.right_w = clamp(cell.right_w - delta, 0.05, 0.72)
      cell.self_w = clamp(cell.self_w - delta * 0.6, 0.30, 0.80)
      cell.cooldown = clamp(cell.cooldown + 0.04, 0.0, 1.0)
    end
  end
end

local function burn_cost(crystal, cycle_gain)
  local base_cost = 0.16 + crystal.span * 0.03
  local influence_cost = crystal.energy * 0.42 * cycle_gain
  local rewrite_cost = 0.0

  if crystal.kind == "CONNECT" or crystal.kind == "RELEASE" then
    rewrite_cost = 0.26 + crystal.span * 0.07
  end

  return base_cost + influence_cost + rewrite_cost
end

local function cycle_mod(state)
  return 1.0 + 0.18 * math.sin(state.cycle_phase)
end

local function logic_soft_clip(x)
  if x > 1.0 then
    return 1.0 - (x - 1.0) * 0.15
  elseif x < 0.0 then
    return x * 0.15
  end
  return x
end

local function readout(state)
  local start_idx = math.max(1, state.length - math.max(4, math.floor(state.length * 0.1)) + 1)
  local sum = 0.0
  local n = 0
  for i = start_idx, state.length do
    sum = sum + state.cells[i].activation
    n = n + 1
  end
  return sum / math.max(1, n)
end

local function total_energy(state)
  local sum = 0.0
  for i = 1, state.length do
    sum = sum + math.abs(state.cells[i].activation) + math.abs(state.cells[i].charge)
  end
  return sum
end

local function active_pu(state)
  local sum = 0.0
  for _, crystal in ipairs(state.active_crystals) do
    sum = sum + math.max(0.0, crystal.pu_stock)
  end
  return sum
end

local function move_arrivals(state, tick)
  while state.queue_index <= #state.queue and state.queue[state.queue_index].tick == tick do
    state.active_crystals[#state.active_crystals + 1] = state.queue[state.queue_index]
    state.crystals_activated = state.crystals_activated + 1
    state.queue_index = state.queue_index + 1
  end
end

local function step(state, tick)
  move_arrivals(state, tick)

  state.cycle_phase = state.cycle_phase + state.cycle_speed
  local cycle_gain = cycle_mod(state)
  local decay = 0.90 + 0.03 * math.cos(state.cycle_phase * 0.7)

  local exhausted_now = 0
  local survivors = {}

  for _, crystal in ipairs(state.active_crystals) do
    apply_crystal_effect(state, crystal, cycle_gain)
    local burn = burn_cost(crystal, cycle_gain)
    crystal.pu_stock = crystal.pu_stock - burn
    crystal.age = crystal.age + 1
    state.pu_burned_total = state.pu_burned_total + burn

    if crystal.pu_stock > 0 then
      survivors[#survivors + 1] = crystal
    else
      state.exhausted_pool[#state.exhausted_pool + 1] = crystal
      exhausted_now = exhausted_now + 1
    end
  end

  state.active_crystals = survivors
  state.exhausted_count = state.exhausted_count + exhausted_now

  for i = 1, state.length do
    local cell = state.cells[i]
    local left = state.cells[wrap(i - 1, state.length)]
    local right = state.cells[wrap(i + 1, state.length)]

    local cooldown_brake = 1.0 - cell.cooldown * 0.35
    local raw =
      left.activation * cell.left_w +
      right.activation * cell.right_w +
      cell.activation * cell.self_w +
      cell.charge * cycle_gain +
      cell.bias

    raw = raw * decay * cooldown_brake
    raw = logic_soft_clip(raw)
    cell.next_activation = clamp(raw, -1.0, 1.0)
  end

  for i = 1, state.length do
    local cell = state.cells[i]
    cell.activation = cell.next_activation
    cell.next_activation = 0.0
    cell.charge = cell.charge * 0.82
    cell.cooldown = cell.cooldown * 0.90
  end

  local ro = readout(state)
  if math.abs(ro - state.last_readout) < 0.015 and math.abs(ro) > 0.08 then
    state.stable_readout_ticks = state.stable_readout_ticks + 1
  else
    state.stable_readout_ticks = 0
  end
  state.last_readout = ro

  if state.stable_readout_ticks >= 3 then
    state.manifest_candidates = state.manifest_candidates + 1
    state.stable_readout_ticks = 0
  end

  return ro, total_energy(state), exhausted_now
end

local function run(l1_ring, l1_cw, ticks, seed)
  local l2_width, l2_height = derive_l2_shape(l1_ring, l1_cw)
  local pu_capacity = derive_pu_capacity(l2_width, l2_height)
  local length = derive_tape_length(l2_width, l2_height, l1_cw)
  local queue_len = derive_queue_length(l2_width, l2_height, l1_cw)
  local queue, pu_unbound = build_crystal_schedule(queue_len, length, pu_capacity, seed)

  local state = {
    l2_width = l2_width,
    l2_height = l2_height,
    length = length,
    cells = build_cells(length, seed),
    queue = queue,
    queue_index = 1,
    active_crystals = {},
    exhausted_pool = {},
    cycle_phase = 0.0,
    cycle_speed = 0.12,
    crystals_activated = 0,
    exhausted_count = 0,
    manifest_candidates = 0,
    stable_readout_ticks = 0,
    last_readout = 0.0,
    pu_capacity = pu_capacity,
    pu_unbound = pu_unbound,
    pu_burned_total = 0.0,
  }

  print(string.format(
    "L3 substrate stand :: l1_ring=%d l1_cw=%d -> l2=%dx%d pu_max=%d tape=%d scheduled_crystals=%d ticks=%d seed=%d",
    l1_ring, l1_cw, l2_width, l2_height, pu_capacity, length, #queue, ticks, seed
  ))
  print(string.format("PU :: bound=%d unbound=%d", pu_capacity - pu_unbound, pu_unbound))
  print("")
  print("First crystals:")
  for i = 1, math.min(8, #state.queue) do
    local c = state.queue[i]
    print(string.format(
      "  [%d] tick=%d kind=%s target=%d energy=%.3f span=%d pu=%d",
      i, c.tick, c.kind, c.target, c.energy, c.span, c.pu_stock
    ))
  end
  print("")

  for tick = 1, ticks do
    local ro, energy, exhausted_now = step(state, tick)
    if tick == 1 or tick % math.max(1, math.floor(ticks / 8)) == 0 or tick == ticks then
      print(string.format(
        "[tick=%d] active=%d exhausted=%d(+%d) readout=%.4f energy=%.4f manifest=%d active_pu=%.1f burned=%.1f queue_left=%d",
        tick,
        #state.active_crystals,
        state.exhausted_count,
        exhausted_now,
        ro,
        energy,
        state.manifest_candidates,
        active_pu(state),
        state.pu_burned_total,
        (#state.queue - state.queue_index + 1)
      ))
    end
  end

  print("")
  print(string.format(
    "Summary :: activated=%d exhausted=%d manifest=%d final_readout=%.4f final_energy=%.4f active_pu=%.1f burned=%.1f unbound=%d",
    state.crystals_activated,
    state.exhausted_count,
    state.manifest_candidates,
    state.last_readout,
    total_energy(state),
    active_pu(state),
    state.pu_burned_total,
    state.pu_unbound
  ))
end

local l1_ring = tonumber(arg[1]) or DEFAULT_L1_RING
local l1_cw = tonumber(arg[2]) or DEFAULT_L1_CW
local ticks = tonumber(arg[3]) or DEFAULT_TICKS
local seed = tonumber(arg[4]) or DEFAULT_SEED

run(l1_ring, l1_cw, ticks, seed)
