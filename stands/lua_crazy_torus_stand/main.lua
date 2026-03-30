local DEFAULT_RING_SIZE = 64
local DEFAULT_TICKS = 512
local DEFAULT_VARIANT = "A"
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

local function snapshot(core, trace, carry, pos)
  return {
    fingerprint = fingerprint(core, trace, carry, pos),
    trace_density = trace_density(trace),
    distinct_core = distinct_count(core),
    distinct_trace = distinct_count(trace),
  }
end

local function snapshot_t3(core, traces, carries, positions)
  local merged_trace = {}
  for i = 1, #core do
    local acc = traces[1][i]
    acc = crazy(acc, traces[2][i])
    acc = crazy(acc, traces[3][i])
    merged_trace[i] = acc
  end

  local merged_carry = crazy(crazy(carries[1], carries[2]), carries[3])
  local merged_pos = positions[1]

  return {
    fingerprint = fingerprint(core, merged_trace, merged_carry, merged_pos),
    trace_density = trace_density(merged_trace),
    distinct_core = distinct_count(core),
    distinct_trace = distinct_count(merged_trace),
    merged_carry = merged_carry,
    merged_pos = merged_pos,
  }
end

local function snapshot_multi(core, traces, carries, positions)
  local merged_trace = {}
  for i = 1, #core do
    local acc = traces[1][i]
    for t = 2, #traces do
      acc = crazy(acc, traces[t][i])
    end
    merged_trace[i] = acc
  end

  local merged_carry = carries[1]
  for t = 2, #carries do
    merged_carry = crazy(merged_carry, carries[t])
  end

  return {
    fingerprint = fingerprint(core, merged_trace, merged_carry, positions[1]),
    trace_density = trace_density(merged_trace),
    distinct_core = distinct_count(core),
    distinct_trace = distinct_count(merged_trace),
    merged_carry = merged_carry,
    merged_pos = positions[1],
  }
end

local function tick_variant_a(state)
  local p = state.pos
  local q = (p % state.ring_size) + 1

  local operand = state.core[q]
  local res = crazy(state.carry, operand)

  state.carry = res
  state.core[p] = res
  state.trace[p] = crazy(state.trace[p], res)
  state.pos = q
end

local function tick_variant_b(state)
  local p = state.pos
  local q = (p % state.ring_size) + 1

  local operand = crazy(state.core[p], state.trace[p])
  local res = crazy(state.carry, operand)

  state.carry = res
  state.core[p] = crazy(state.core[p], res)
  state.trace[p] = res
  state.pos = q
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

local function tick_variant_t3(state)
  for idx = 1, 3 do
    local p = state.positions[idx]
    local q = (p % state.ring_size) + 1

    local bias = crazy(state.phase[p], (p - 1) % MOD)
    local operand = crazy(crazy(state.core[p], state.traces[idx][p]), bias)
    local res = crazy(state.carries[idx], operand)

    state.carries[idx] = res
    state.core[p] = crazy(res, state.traces[idx][p])
    state.traces[idx][p] = crazy(state.traces[idx][p], bias)
    state.positions[idx] = q
  end
end

local function tick_variant_multi(state)
  for idx = 1, #state.traces do
    local p = state.positions[idx]
    local q = (p % state.ring_size) + 1

    local bias = crazy(state.phase[p], ((p - 1) + idx) % MOD)
    local operand = crazy(crazy(state.core[p], state.traces[idx][p]), bias)
    local res = crazy(state.carries[idx], operand)

    state.carries[idx] = res
    state.core[p] = crazy(res, state.traces[idx][p])
    state.traces[idx][p] = crazy(state.traces[idx][p], bias)
    state.positions[idx] = q
  end
end

local function tick(state)
  if state.variant == "B" then
    tick_variant_b(state)
  elseif state.variant == "C" then
    tick_variant_c(state)
  elseif state.variant == "T3" then
    tick_variant_t3(state)
  elseif state.variant == "T10" then
    tick_variant_multi(state)
  else
    tick_variant_a(state)
  end
end

local function run(ring_size, ticks, seed, variant)
  local core, trace, phase = seed_ring(ring_size, seed)

  local state = {
    ring_size = ring_size,
    core = core,
    trace = trace,
    phase = phase,
    carry = seed % MOD,
    pos = 1,
    variant = variant,
  }

  if variant == "T3" then
    state.traces = {
      trace,
      {},
      {},
    }
    state.positions = {
      1,
      math.floor(ring_size / 3) + 1,
      math.floor((ring_size * 2) / 3) + 1,
    }
    state.carries = {
      seed % MOD,
      crazy(seed % MOD, 1),
      crazy(seed % MOD, 2),
    }

    for i = 1, ring_size do
      state.traces[2][i] = crazy(core[i], (phase[i] + 1) % 3)
      state.traces[3][i] = crazy(core[i], (phase[i] + 2) % 3)
    end
  elseif variant == "T10" then
    state.traces = {}
    state.positions = {}
    state.carries = {}

    for idx = 1, 10 do
      state.traces[idx] = {}
      state.positions[idx] = ((math.floor((ring_size * (idx - 1)) / 10)) % ring_size) + 1
      state.carries[idx] = crazy(seed % MOD, idx - 1)
      for i = 1, ring_size do
        state.traces[idx][i] = crazy(core[i], (phase[i] + idx - 1) % 3)
      end
    end
  end

  local logs = {}
  local checkpoints = {}

  for t = 1, ticks do
    tick(state)

    if t == 1 or t % ring_size == 0 or t == ticks then
      local snap
      if variant == "T3" then
        snap = snapshot_t3(state.core, state.traces, state.carries, state.positions)
      elseif variant == "T10" then
        snap = snapshot_multi(state.core, state.traces, state.carries, state.positions)
      else
        snap = snapshot(state.core, state.trace, state.carry, state.pos)
      end
      snap.tick = t
      snap.pos = variant == "T3" and state.positions[1] or state.pos
      snap.carry = variant == "T3" and state.carries[1] or state.carry
      checkpoints[#checkpoints + 1] = snap
    end

      if variant == "T3" then
        local snap = snapshot_t3(state.core, state.traces, state.carries, state.positions)
        logs[#logs + 1] = snap.fingerprint
      elseif variant == "T10" then
        local snap = snapshot_multi(state.core, state.traces, state.carries, state.positions)
        logs[#logs + 1] = snap.fingerprint
      else
        logs[#logs + 1] = fingerprint(state.core, state.trace, state.carry, state.pos)
      end
  end

  return state, logs, checkpoints
end

local function print_usage()
  io.write("usage: lua main.lua [ring_size] [ticks] [seed] [variant]\n")
end

local ring_size = tonumber(arg[1] or DEFAULT_RING_SIZE)
local ticks = tonumber(arg[2] or DEFAULT_TICKS)
local seed = tonumber(arg[3] or 12345)
local variant = tostring(arg[4] or DEFAULT_VARIANT):upper()

if not ring_size or ring_size < 3 then
  print_usage()
  os.exit(1)
end

if not ticks or ticks < 1 then
  print_usage()
  os.exit(1)
end

if variant ~= "A" and variant ~= "B" and variant ~= "C" and variant ~= "T3" and variant ~= "T10" then
  print_usage()
  os.exit(1)
end

local state, logs, checkpoints = run(ring_size, ticks, seed, variant)

print("crazy torus baseline")
print(string.format("ring_size=%d ticks=%d seed=%d variant=%s", ring_size, ticks, seed, variant))

for _, snap in ipairs(checkpoints) do
  local carry_value = snap.carry
  local pos_value = snap.pos
  if snap.merged_carry then
    carry_value = snap.merged_carry
  end
  if snap.merged_pos then
    pos_value = snap.merged_pos
  end
  print(string.format(
    "tick=%d pos=%d carry=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d",
    snap.tick,
    pos_value,
    carry_value,
    snap.fingerprint,
    snap.trace_density,
    snap.distinct_core,
    snap.distinct_trace
  ))
end

local preview = {}
for i = 1, math.min(12, #state.core) do
  preview[#preview + 1] = tostring(state.core[i])
end
print("core_preview=" .. table.concat(preview, ","))

preview = {}
local trace_view = state.trace
if variant == "T3" then
  trace_view = state.traces[1]
elseif variant == "T10" then
  trace_view = state.traces[1]
end
for i = 1, math.min(12, #trace_view) do
  preview[#preview + 1] = tostring(trace_view[i])
end
print("trace_preview=" .. table.concat(preview, ","))

preview = {}
for i = 1, math.min(24, #logs) do
  preview[#preview + 1] = tostring(logs[i])
end
print("fp_preview=" .. table.concat(preview, ","))
