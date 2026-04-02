local DEFAULT_TICKS = 128
local DEFAULT_PROCESS_COUNT = 256
local DEFAULT_SEED = 12345

local COST = {
  connect = 1.4,
  observe_raw = 0.5,
  observe_calm = 1.0,
  choose_raw = 0.5,
  choose_calm = 1.0,
  encode = 1.8,
  runtime = 0.75,
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

local function hash_noise(a, b, c, d)
  local v = a * 92821 + b * 68917 + c * 1237 + d * 17
  v = (v ~ (v << 13)) & 0x7fffffff
  v = (v ~ (v >> 17)) & 0x7fffffff
  v = (v ~ (v << 5)) & 0x7fffffff
  return (v % 1000) / 1000.0
end

local function sample_chaos(p, tick, seed)
  return {
    intensity = hash_noise(p.x, p.y, tick, seed),
    variance = hash_noise(p.y, p.id, tick * 3, seed + 11),
    fingerprint = math.floor(hash_noise(p.id, p.x * 7, p.y * 13, seed + tick) * 65535),
  }
end

local function new_process(id, rng)
  return {
    id = id,
    x = 1 + math.floor(randf(rng) * 64),
    y = 1 + math.floor(randf(rng) * 64),
    pu = 42.0 + randf(rng) * 28.0,
    burn = 0.0,
    age = 0,
    alive = true,
    success = false,
    emitted = false,
    connect_strength = 0.12 + randf(rng) * 0.12,
    chaos_flux = 0.0,
    raw_mass = 0.0,
    raw_noise = 0.45 + randf(rng) * 0.20,
    calm_mass = 0.0,
    calm_coherence = 0.0,
    observe_raw_calls = 0,
    observe_calm_calls = 0,
    choose_raw_calls = 0,
    choose_calm_calls = 0,
    runtime_calls = 0,
  }
end

local function spend(p, amount)
  p.pu = p.pu - amount
  p.burn = p.burn + amount
end

local function connect_tick(p, chaos)
  spend(p, COST.connect)
  local gain = chaos.intensity * 0.28 + (1.0 - chaos.variance) * 0.16
  p.connect_strength = clamp(p.connect_strength * 0.95 + gain, 0.0, 1.5)
  p.chaos_flux = chaos.intensity * p.connect_strength
  p.raw_mass = p.raw_mass + p.chaos_flux * 0.75
  p.raw_noise = clamp(p.raw_noise * 0.90 + chaos.variance * 0.12, 0.0, 1.0)
end

local function observe_raw_tick(p, chaos)
  spend(p, COST.observe_raw)
  p.observe_raw_calls = p.observe_raw_calls + 1
  p.raw_mass = p.raw_mass + chaos.intensity * 0.10
  p.raw_noise = clamp(p.raw_noise * 0.86 + chaos.variance * 0.06, 0.0, 1.0)
end

local function choose_raw_tick(p)
  spend(p, COST.choose_raw)
  p.choose_raw_calls = p.choose_raw_calls + 1
  local dissolved = p.raw_mass * (0.08 + p.raw_noise * 0.14)
  p.raw_mass = math.max(0.0, p.raw_mass - dissolved)
  p.raw_noise = clamp(p.raw_noise * 0.84, 0.0, 1.0)
end

local function encode_tick(p)
  spend(p, COST.encode)
  local convertible = math.min(p.raw_mass * 0.28, p.connect_strength * 0.24)
  p.raw_mass = math.max(0.0, p.raw_mass - convertible)
  p.calm_mass = p.calm_mass + convertible
  local coherence_gain = convertible * (1.0 - p.raw_noise) * 0.65
  local coherence_loss = p.raw_noise * 0.03 + math.max(0.0, 0.14 - p.connect_strength) * 0.05
  p.calm_coherence = clamp(p.calm_coherence + coherence_gain - coherence_loss, 0.0, 1.0)
end

local function observe_calm_tick(p)
  spend(p, COST.observe_calm)
  p.observe_calm_calls = p.observe_calm_calls + 1
  if p.calm_mass > 0 then
    p.calm_coherence = clamp(p.calm_coherence + 0.015, 0.0, 1.0)
  end
end

local function choose_calm_tick(p)
  spend(p, COST.choose_calm)
  p.choose_calm_calls = p.choose_calm_calls + 1
  if p.calm_coherence < 0.28 then
    p.calm_mass = p.calm_mass * 0.82
  elseif p.calm_coherence > 0.62 then
    p.calm_coherence = clamp(p.calm_coherence + 0.02, 0.0, 1.0)
  end
end

local function choose_l3_mode(p)
  if p.calm_coherence > 0.88 and p.calm_mass > 3.2 then
    return "MANIFEST"
  elseif p.raw_noise > 0.56 then
    return "LOGIC"
  elseif p.chaos_flux > 0.70 then
    return "CYCLE"
  end
  return "RUNTIME"
end

local function runtime_gate_tick(p)
  if p.calm_mass > 2.2 and p.calm_coherence > 0.68 and p.connect_strength > 0.25 then
    spend(p, COST.runtime)
    p.runtime_calls = p.runtime_calls + 1
    p.alive = false
    p.success = true
    return true
  end
  return false
end

local function tick_process(p, tick, seed)
  if not p.alive then return false end

  p.age = p.age + 1
  local chaos = sample_chaos(p, tick, seed)

  connect_tick(p, chaos)

  local want_observe_raw = p.raw_noise > 0.62 or p.raw_mass < 0.22
  local want_choose_raw = p.raw_mass > 1.10 or p.raw_noise > 0.78
  local want_observe_calm = p.calm_mass > 0.30
  local want_choose_calm = p.calm_mass > 1.40 or p.calm_coherence < 0.26

  if want_observe_raw then observe_raw_tick(p, chaos) end
  if want_choose_raw then choose_raw_tick(p) end
  encode_tick(p)
  if want_observe_calm then observe_calm_tick(p) end
  if want_choose_calm then choose_calm_tick(p) end

  if runtime_gate_tick(p) then
    return true
  end

  if p.pu <= 0 or p.connect_strength <= 0.03 or (p.age > 28 and p.calm_mass < 0.20) then
    p.alive = false
    p.success = false
  end
  return false
end

local function make_l3(length, seed)
  local rng = make_rng(seed * 17 + 9)
  local cells = {}
  for i = 1, length do
    cells[i] = {
      activation = 0.0,
      next_activation = 0.0,
      charge = 0.0,
      left_w = 0.16 + randf(rng) * 0.12,
      right_w = 0.16 + randf(rng) * 0.12,
      self_w = 0.50 + randf(rng) * 0.10,
      mode = "RUNTIME",
      gate = 0.0,
    }
  end
  return cells
end

local function l3_indices(state, crystal)
  local idx = { crystal.target }
  if crystal.span >= 2 then idx[#idx + 1] = wrap(crystal.target + 1, state.length) end
  return idx
end

local function apply_crystal(state, crystal)
  local strength = clamp(crystal.pu_stock / math.max(0.001, crystal.pu_initial), 0.10, 1.0)
  for _, idx in ipairs(l3_indices(state, crystal)) do
    local cell = state.cells[idx]
    local e = crystal.energy * strength
    cell.mode = crystal.mode
    if crystal.mode == "RUNTIME" then
      cell.charge = cell.charge + e * 0.75
    elseif crystal.mode == "CYCLE" then
      cell.charge = cell.charge + math.sin(state.phase + idx * 0.09) * e * 0.45
      cell.gate = clamp(cell.gate + e * 0.12, 0.0, 1.0)
    elseif crystal.mode == "LOGIC" then
      cell.charge = cell.charge * (1.0 - e * 0.18)
      cell.left_w = clamp(cell.left_w - e * 0.01, 0.06, 0.55)
      cell.right_w = clamp(cell.right_w - e * 0.01, 0.06, 0.55)
    elseif crystal.mode == "MANIFEST" then
      cell.charge = cell.charge + e * 0.24
      cell.gate = clamp(cell.gate + e * 0.22, 0.0, 1.0)
      state.manifest = state.manifest + e * 0.10
    end
  end
end

local function crystal_burn(crystal)
  local base = 0.30
  local mode = ({
    RUNTIME = 0.14,
    CYCLE = 0.16,
    LOGIC = 0.18,
    MANIFEST = 0.22,
  })[crystal.mode]
  return base + mode + crystal.energy * 0.20
end

local function l3_step(state)
  state.phase = state.phase + state.cycle_speed
  local alive = {}
  for _, crystal in ipairs(state.active) do
    apply_crystal(state, crystal)
    local burn = crystal_burn(crystal)
    crystal.pu_stock = crystal.pu_stock - burn
    state.pu_burned = state.pu_burned + burn
    if crystal.pu_stock > 0 then
      alive[#alive + 1] = crystal
    else
      state.exhausted[#state.exhausted + 1] = crystal
    end
  end
  state.active = alive

  local cycle_gain = 1.0 + 0.14 * math.sin(state.phase)
  local decay = 0.89 + 0.02 * math.cos(state.phase * 0.7)
  for i = 1, state.length do
    local c = state.cells[i]
    local l = state.cells[wrap(i - 1, state.length)]
    local r = state.cells[wrap(i + 1, state.length)]
    local raw = l.activation * c.left_w + r.activation * c.right_w + c.activation * c.self_w + c.charge * cycle_gain
    if c.mode == "LOGIC" then
      raw = raw * 0.80
    elseif c.mode == "MANIFEST" then
      raw = raw + c.gate * 0.08
    elseif c.mode == "CYCLE" then
      raw = raw + math.sin(state.phase + i * 0.10) * 0.06
    end
    c.next_activation = clamp(raw * decay, 0.0, 1.0)
    c.charge = c.charge * 0.80
    c.gate = c.gate * 0.84
  end
  for i = 1, state.length do
    state.cells[i].activation = state.cells[i].next_activation
  end
end

local function l3_readout(state)
  local from = math.max(1, state.length - math.max(4, math.floor(state.length * 0.12)) + 1)
  local sum = 0.0
  local n = 0
  for i = from, state.length do
    sum = sum + state.cells[i].activation
    n = n + 1
  end
  return sum / math.max(1, n)
end

local function active_count_by_mode(list)
  local out = { RUNTIME = 0, CYCLE = 0, LOGIC = 0, MANIFEST = 0 }
  for _, crystal in ipairs(list) do
    out[crystal.mode] = out[crystal.mode] + 1
  end
  return out
end

local function main()
  local ticks = tonumber(arg[1]) or DEFAULT_TICKS
  local process_count = tonumber(arg[2]) or DEFAULT_PROCESS_COUNT
  local seed = tonumber(arg[3]) or DEFAULT_SEED
  local rng = make_rng(seed)

  local processes = {}
  for i = 1, process_count do
    processes[i] = new_process(i, rng)
  end

  local l3 = {
    length = 72,
    cells = make_l3(72, seed),
    active = {},
    exhausted = {},
    manifest = 0.0,
    pu_burned = 0.0,
    phase = 0.0,
    cycle_speed = 0.12,
    modes = { RUNTIME = 0, CYCLE = 0, LOGIC = 0, MANIFEST = 0 },
  }

  for tick = 1, ticks do
    for i = 1, process_count do
      local p = processes[i]
      local emitted = tick_process(p, tick, seed)
      if emitted and not p.emitted then
        p.emitted = true
        local mode = choose_l3_mode(p)
        l3.modes[mode] = l3.modes[mode] + 1
        l3.active[#l3.active + 1] = {
          mode = mode,
          target = 1 + ((p.id * 7 + tick * 3) % l3.length),
          span = p.calm_coherence > 0.82 and 2 or 1,
          energy = 0.22 + p.calm_mass * 0.11,
          pu_stock = 5.0 + p.calm_mass * 3.2 + p.calm_coherence * 6.0,
          pu_initial = 5.0 + p.calm_mass * 3.2 + p.calm_coherence * 6.0,
        }
      end
    end
    l3_step(l3)
  end

  local alive = 0
  local success = 0
  local failed = 0
  local total_age = 0.0
  local total_burn = 0.0
  local total_coherence = 0.0
  local runtime_calls = 0
  for _, p in ipairs(processes) do
    if p.alive then alive = alive + 1 end
    if p.success then success = success + 1 end
    if not p.alive and not p.success then failed = failed + 1 end
    total_age = total_age + p.age
    total_burn = total_burn + p.burn
    total_coherence = total_coherence + p.calm_coherence
    runtime_calls = runtime_calls + p.runtime_calls
  end

  local active_modes = active_count_by_mode(l3.active)
  print(string.format("Eva.00 encode core + L3 stand :: ticks=%d processes=%d seed=%d", ticks, process_count, seed))
  print(string.format("processes :: alive=%d success=%d failed=%d runtime=%d", alive, success, failed, runtime_calls))
  print(string.format("process_avg :: age=%.2f burn=%.2f coherence=%.4f", total_age / process_count, total_burn / process_count, total_coherence / process_count))
  print(string.format("l3 :: active=%d exhausted=%d readout=%.4f manifest=%.3f burned=%.1f", #l3.active, #l3.exhausted, l3_readout(l3), l3.manifest, l3.pu_burned))
  print(string.format("l3_modes_incoming :: RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d", l3.modes.RUNTIME, l3.modes.CYCLE, l3.modes.LOGIC, l3.modes.MANIFEST))
  print(string.format("l3_active_modes :: RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d", active_modes.RUNTIME, active_modes.CYCLE, active_modes.LOGIC, active_modes.MANIFEST))
end

main()
