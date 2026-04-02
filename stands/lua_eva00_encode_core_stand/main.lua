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
  local intensity = hash_noise(p.x, p.y, tick, seed)
  local variance = hash_noise(p.y, p.id, tick * 3, seed + 11)
  local fingerprint = math.floor(hash_noise(p.id, p.x * 7, p.y * 13, seed + tick) * 65535)
  return {
    intensity = intensity,
    variance = variance,
    fingerprint = fingerprint,
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
  if not p.alive then return end

  p.age = p.age + 1
  local chaos = sample_chaos(p, tick, seed)

  connect_tick(p, chaos)

  local want_observe_raw = p.raw_noise > 0.62 or p.raw_mass < 0.22
  local want_choose_raw = p.raw_mass > 1.10 or p.raw_noise > 0.78
  local want_observe_calm = p.calm_mass > 0.30
  local want_choose_calm = p.calm_mass > 1.40 or p.calm_coherence < 0.26

  if want_observe_raw then
    observe_raw_tick(p, chaos)
  end
  if want_choose_raw then
    choose_raw_tick(p)
  end

  encode_tick(p)

  if want_observe_calm then
    observe_calm_tick(p)
  end
  if want_choose_calm then
    choose_calm_tick(p)
  end

  if runtime_gate_tick(p) then
    return
  end

  if p.pu <= 0 or p.connect_strength <= 0.03 or (p.age > 28 and p.calm_mass < 0.20) then
    p.alive = false
    p.success = false
  end
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

  for tick = 1, ticks do
    for i = 1, process_count do
      tick_process(processes[i], tick, seed)
    end
  end

  local alive = 0
  local success = 0
  local failed = 0
  local total_age = 0.0
  local total_burn = 0.0
  local total_coherence = 0.0
  local obs_raw = 0
  local obs_calm = 0
  local choose_raw = 0
  local choose_calm = 0
  local runtime_calls = 0

  for _, p in ipairs(processes) do
    if p.alive then alive = alive + 1 end
    if p.success then success = success + 1 end
    if not p.alive and not p.success then failed = failed + 1 end
    total_age = total_age + p.age
    total_burn = total_burn + p.burn
    total_coherence = total_coherence + p.calm_coherence
    obs_raw = obs_raw + p.observe_raw_calls
    obs_calm = obs_calm + p.observe_calm_calls
    choose_raw = choose_raw + p.choose_raw_calls
    choose_calm = choose_calm + p.choose_calm_calls
    runtime_calls = runtime_calls + p.runtime_calls
  end

  print(string.format(
    "Eva.00 encode core stand :: ticks=%d processes=%d seed=%d",
    ticks, process_count, seed
  ))
  print(string.format(
    "alive=%d success=%d failed=%d",
    alive, success, failed
  ))
  print(string.format(
    "avg_age=%.2f avg_burn=%.2f avg_calm_coherence=%.4f",
    total_age / process_count,
    total_burn / process_count,
    total_coherence / process_count
  ))
  print(string.format(
    "calls :: observe_raw=%d choose_raw=%d observe_calm=%d choose_calm=%d runtime=%d",
    obs_raw, choose_raw, obs_calm, choose_calm, runtime_calls
  ))
end

main()
