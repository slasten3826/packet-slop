local DEFAULT_IDEAS = 2000
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

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
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
  }
end

local function observe_calm(calm)
  return calm.calm_density * 0.55 + calm.calm_structure * 0.45
end

local function choose_calm(calm)
  local score = calm.calm_density * 0.35 + calm.calm_structure * 0.50 - calm.calm_risk * 0.20
  return score, score > 0.48
end

local function runtime_raw(idea)
  return clamp(idea.raw_signal * 0.45 + idea.novelty * 0.15, 0.0, 1.0)
end

local function runtime_calm(calm)
  return clamp(calm.calm_density * 0.40 + calm.calm_structure * 0.60 - calm.calm_risk * 0.10, 0.0, 1.0)
end

local function main()
  local ideas_total = tonumber(arg[1]) or DEFAULT_IDEAS
  local seed = tonumber(arg[2]) or DEFAULT_SEED
  local rng = make_rng(seed)

  local metrics = {
    raw_killed = 0,
    raw_runtime = 0,
    calm_encoded = 0,
    calm_runtime = 0,
    raw_quality_sum = 0.0,
    calm_quality_sum = 0.0,
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

  for _ = 1, ideas_total do
    local idea = observe_chaos(rng)
    metrics.spend.observe_chaos = metrics.spend.observe_chaos + COST.observe_chaos

    local raw_score, raw_ok = choose_chaos(idea)
    metrics.spend.choose_chaos = metrics.spend.choose_chaos + COST.choose_chaos

    if not raw_ok then
      metrics.raw_killed = metrics.raw_killed + 1
    else
      local raw_route = raw_score > 0.72 and randf(rng) > 0.55

      if raw_route then
        local q = runtime_raw(idea)
        metrics.spend.runtime_raw = metrics.spend.runtime_raw + COST.runtime_raw
        metrics.raw_runtime = metrics.raw_runtime + 1
        metrics.raw_quality_sum = metrics.raw_quality_sum + q
      else
        local calm = encode(idea, rng)
        metrics.spend.encode = metrics.spend.encode + COST.encode
        metrics.calm_encoded = metrics.calm_encoded + 1

        local calm_seen = observe_calm(calm)
        metrics.spend.observe_calm = metrics.spend.observe_calm + COST.observe_calm

        local calm_score, calm_ok = choose_calm({
          calm_density = calm.calm_density,
          calm_structure = clamp(calm.calm_structure + calm_seen * 0.08, 0.0, 1.0),
          calm_risk = calm.calm_risk,
        })
        metrics.spend.choose_calm = metrics.spend.choose_calm + COST.choose_calm

        if calm_ok and calm_score > 0.50 then
          local q = runtime_calm(calm)
          metrics.spend.runtime_calm = metrics.spend.runtime_calm + COST.runtime_calm
          metrics.calm_runtime = metrics.calm_runtime + 1
          metrics.calm_quality_sum = metrics.calm_quality_sum + q
        end
      end
    end
  end

  local spend_total = 0
  for _, v in pairs(metrics.spend) do
    spend_total = spend_total + v
  end

  local raw_avg = metrics.raw_runtime > 0 and (metrics.raw_quality_sum / metrics.raw_runtime) or 0.0
  local calm_avg = metrics.calm_runtime > 0 and (metrics.calm_quality_sum / metrics.calm_runtime) or 0.0

  print(string.format("L2 market cost stand :: ideas=%d seed=%d", ideas_total, seed))
  print(string.format("raw_killed=%d raw_runtime=%d calm_encoded=%d calm_runtime=%d", metrics.raw_killed, metrics.raw_runtime, metrics.calm_encoded, metrics.calm_runtime))
  print(string.format("avg_quality :: raw=%.4f calm=%.4f", raw_avg, calm_avg))
  print(string.format(
    "spend :: O(chaos)=%d C(chaos)=%d ENCODE=%d O(calm)=%d C(calm)=%d R(raw)=%d R(calm)=%d total=%d",
    metrics.spend.observe_chaos,
    metrics.spend.choose_chaos,
    metrics.spend.encode,
    metrics.spend.observe_calm,
    metrics.spend.choose_calm,
    metrics.spend.runtime_raw,
    metrics.spend.runtime_calm,
    spend_total
  ))
end

main()
