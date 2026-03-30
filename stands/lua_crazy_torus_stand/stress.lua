local lua_dir = (... and debug.getinfo(1, "S").source:match("^@(.*/)")) or "./"
package.path = lua_dir .. "?.lua;" .. package.path

local ring_sizes = {32, 64, 128, 256}
local seeds = {12345, 22222, 33333}
local variant = "C"

local MOD = 59049

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

local function build_phase(ring_size)
  local phase = {}
  for i = 1, ring_size do
    phase[i] = (i - 1) % 3
  end
  return phase
end

local function seed_ring(ring_size, seed)
  local core = {}
  local trace = {}
  local phase = build_phase(ring_size)

  core[1] = seed % MOD
  core[2] = crazy(core[1], seed % MOD)

  local fill = 3
  while fill <= ring_size do
    core[fill] = crazy(core[fill - 2], core[fill - 1])
    fill = fill + 1
  end

  for i = 1, ring_size do
    trace[i] = crazy(core[i], phase[i])
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

local function tick_variant_c(state)
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

local function run(ring_size, ticks, seed)
  local core, trace, phase = seed_ring(ring_size, seed)
  local state = {
    ring_size = ring_size,
    core = core,
    trace = trace,
    phase = phase,
    carry = seed % MOD,
    pos = 1,
  }

  for _ = 1, ticks do
    tick_variant_c(state)
  end

  return {
    carry = state.carry,
    fp = fingerprint(state.core, state.trace, state.carry, state.pos),
    trace_density = trace_density(state.trace),
    distinct_core = distinct_count(state.core),
    distinct_trace = distinct_count(state.trace),
  }
end

print("variant,ring,seed,ticks,carry,fp,trace_density,distinct_core,distinct_trace")
for _, ring in ipairs(ring_sizes) do
  local ticks = ring * 8
  for _, seed in ipairs(seeds) do
    local result = run(ring, ticks, seed)
    print(table.concat({
      variant,
      tostring(ring),
      tostring(seed),
      tostring(ticks),
      tostring(result.carry),
      tostring(result.fp),
      tostring(result.trace_density),
      tostring(result.distinct_core),
      tostring(result.distinct_trace),
    }, ","))
  end
end
