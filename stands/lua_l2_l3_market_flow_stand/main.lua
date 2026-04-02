local DEFAULT_TICKS = 96
local DEFAULT_IDEAS_PER_TICK = 64
local DEFAULT_SEED = 12345

local COST = {
  observe_chaos = 1,
  choose_chaos = 2,
  encode = 10,
  observe_calm = 6,
  choose_calm = 7,
  runtime_raw = 5,
  runtime_calm = 7,
}

local L3_MODES = { "RUNTIME", "CYCLE", "LOGIC", "MANIFEST" }

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

local function observe_chaos(rng)
  return {
    raw_signal = randf(rng),
    novelty = randf(rng),
    coherence = randf(rng),
  }
end

local function choose_chaos(idea)
  local score = idea.raw_signal * 0.45 + idea.novelty * 0.35 + idea.coherence * 0.20
  return score, score > 0.42
end

local function encode(idea, rng)
  local encoded_density = clamp(
    idea.raw_signal * 0.40 +
    idea.coherence * 0.45 +
    randf(rng) * 0.20,
    0.0,
    1.0
  )
  return {
    calm_density = encoded_density,
    calm_structure = clamp((idea.coherence + encoded_density) * 0.5, 0.0, 1.0),
    calm_risk = clamp((1.0 - idea.coherence) * 0.7 + randf(rng) * 0.2, 0.0, 1.0),
    source_novelty = idea.novelty,
  }
end

local function observe_calm(calm)
  return calm.calm_density * 0.55 + calm.calm_structure * 0.45
end

local function choose_calm(calm)
  local score = calm.calm_density * 0.35 + calm.calm_structure * 0.50 - calm.calm_risk * 0.20
  return score, score > 0.48
end

local function runtime_raw_quality(idea)
  return clamp(idea.raw_signal * 0.45 + idea.novelty * 0.15, 0.0, 1.0)
end

local function runtime_calm_quality(calm)
  return clamp(calm.calm_density * 0.40 + calm.calm_structure * 0.60 - calm.calm_risk * 0.10, 0.0, 1.0)
end

local function raw_to_mode(idea, score)
  if idea.novelty > 0.72 and score > 0.74 then
    return "CYCLE"
  elseif idea.coherence > 0.66 then
    return "RUNTIME"
  end
  return "LOGIC"
end

local function calm_to_mode(calm, score)
  if score > 0.78 and calm.calm_structure > 0.72 then
    return "MANIFEST"
  elseif calm.calm_risk > 0.58 then
    return "LOGIC"
  elseif calm.source_novelty > 0.68 then
    return "CYCLE"
  end
  return "RUNTIME"
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

local function crystal_target(rng, length)
  return 1 + math.floor(randf(rng) * length)
end

local function crystal_from_raw(idea, score, quality, rng, length)
  return {
    origin = "raw",
    mode = raw_to_mode(idea, score),
    quality = quality,
    energy = 0.20 + quality * 0.35,
    pu_stock = 4.0 + quality * 8.0,
    pu_initial = 4.0 + quality * 8.0,
    target = crystal_target(rng, length),
    span = 1,
  }
end

local function crystal_from_calm(calm, score, quality, rng, length)
  return {
    origin = "calm",
    mode = calm_to_mode(calm, score),
    quality = quality,
    energy = 0.35 + quality * 0.55,
    pu_stock = 8.0 + quality * 14.0,
    pu_initial = 8.0 + quality * 14.0,
    target = crystal_target(rng, length),
    span = quality > 0.72 and 2 or 1,
  }
end

local function l3_indices(state, crystal)
  local idx = { crystal.target }
  if crystal.span >= 2 then
    idx[#idx + 1] = wrap(crystal.target + 1, state.length)
  end
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
  local base = crystal.origin == "raw" and 0.28 or 0.42
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
    local raw =
      l.activation * c.left_w +
      r.activation * c.right_w +
      c.activation * c.self_w +
      c.charge * cycle_gain

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

local function readout(state)
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

local function push_crystal(state, crystal)
  state.active[#state.active + 1] = crystal
  state.incoming[crystal.origin] = state.incoming[crystal.origin] + 1
  state.modes[crystal.mode] = state.modes[crystal.mode] + 1
  state.quality_sum = state.quality_sum + crystal.quality
end

local function main()
  local ticks = tonumber(arg[1]) or DEFAULT_TICKS
  local ideas_per_tick = tonumber(arg[2]) or DEFAULT_IDEAS_PER_TICK
  local seed = tonumber(arg[3]) or DEFAULT_SEED
  local rng = make_rng(seed)

  local state = {
    length = 72,
    cells = make_l3(72, seed),
    active = {},
    exhausted = {},
    manifest = 0.0,
    pu_burned = 0.0,
    phase = 0.0,
    cycle_speed = 0.12,
    incoming = { raw = 0, calm = 0 },
    modes = { RUNTIME = 0, CYCLE = 0, LOGIC = 0, MANIFEST = 0 },
    quality_sum = 0.0,
    spend = {
      observe_chaos = 0,
      choose_chaos = 0,
      encode = 0,
      observe_calm = 0,
      choose_calm = 0,
      runtime_raw = 0,
      runtime_calm = 0,
    },
  }

  for _tick = 1, ticks do
    for _ = 1, ideas_per_tick do
      local idea = observe_chaos(rng)
      state.spend.observe_chaos = state.spend.observe_chaos + COST.observe_chaos

      local raw_score, raw_ok = choose_chaos(idea)
      state.spend.choose_chaos = state.spend.choose_chaos + COST.choose_chaos

      if raw_ok then
        local raw_route = raw_score > 0.72 and randf(rng) > 0.55

        if raw_route then
          state.spend.runtime_raw = state.spend.runtime_raw + COST.runtime_raw
          local quality = runtime_raw_quality(idea)
          push_crystal(state, crystal_from_raw(idea, raw_score, quality, rng, state.length))
        else
          local calm = encode(idea, rng)
          state.spend.encode = state.spend.encode + COST.encode

          local calm_seen = observe_calm(calm)
          state.spend.observe_calm = state.spend.observe_calm + COST.observe_calm

          local calm_score, calm_ok = choose_calm({
            calm_density = calm.calm_density,
            calm_structure = clamp(calm.calm_structure + calm_seen * 0.08, 0.0, 1.0),
            calm_risk = calm.calm_risk,
            source_novelty = calm.source_novelty,
          })
          state.spend.choose_calm = state.spend.choose_calm + COST.choose_calm

          if calm_ok and calm_score > 0.50 then
            state.spend.runtime_calm = state.spend.runtime_calm + COST.runtime_calm
            local quality = runtime_calm_quality(calm)
            push_crystal(state, crystal_from_calm(calm, calm_score, quality, rng, state.length))
          end
        end
      end
    end

    l3_step(state)
  end

  local spend_total = 0
  for _, v in pairs(state.spend) do
    spend_total = spend_total + v
  end
  local avg_quality = (state.incoming.raw + state.incoming.calm) > 0 and (state.quality_sum / (state.incoming.raw + state.incoming.calm)) or 0.0
  local active_modes = active_count_by_mode(state.active)

  print(string.format("L2-L3 market flow stand :: ticks=%d ideas_per_tick=%d seed=%d", ticks, ideas_per_tick, seed))
  print(string.format("incoming :: raw=%d calm=%d total=%d avg_quality=%.4f", state.incoming.raw, state.incoming.calm, state.incoming.raw + state.incoming.calm, avg_quality))
  print(string.format("modes_incoming :: RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d", state.modes.RUNTIME, state.modes.CYCLE, state.modes.LOGIC, state.modes.MANIFEST))
  print(string.format("active=%d exhausted=%d readout=%.4f manifest=%.3f burned=%.1f", #state.active, #state.exhausted, readout(state), state.manifest, state.pu_burned))
  print(string.format("active_modes :: RUNTIME=%d CYCLE=%d LOGIC=%d MANIFEST=%d", active_modes.RUNTIME, active_modes.CYCLE, active_modes.LOGIC, active_modes.MANIFEST))
  print(string.format(
    "spend :: O(chaos)=%d C(chaos)=%d ENCODE=%d O(calm)=%d C(calm)=%d R(raw)=%d R(calm)=%d total=%d",
    state.spend.observe_chaos,
    state.spend.choose_chaos,
    state.spend.encode,
    state.spend.observe_calm,
    state.spend.choose_calm,
    state.spend.runtime_raw,
    state.spend.runtime_calm,
    spend_total
  ))
end

main()
