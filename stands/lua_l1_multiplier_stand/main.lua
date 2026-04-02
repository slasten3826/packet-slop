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

local function snapshot(state)
  return {
    fp = fingerprint(state.core, state.trace, state.carry, state.pos),
    distinct_core = distinct_count(state.core),
    distinct_trace = distinct_count(state.trace),
    trace_density = trace_density(state.trace),
  }
end

local function tick_c(state)
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

local function merged_fp(states)
  local acc = 0
  for i = 1, #states do
    local snap = snapshot(states[i])
    acc = crazy(acc, snap.fp)
  end
  return acc
end

local function build_states(token_ids, m)
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

local function print_usage()
  io.write("usage: lua main.lua <bootstrap_dump.lua> <multiplier> [ticks]\n")
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
local ticks = tonumber(arg[3] or tostring(ring * 2))
local states = build_states(bootstrap.token_ids, m)

print("l1 multiplier stand")
print(string.format("model=%s", tostring(bootstrap.model_path)))
print(string.format("ring=%d multiplier=%d ticks=%d variant=C", ring, m, ticks))
print(string.format("prompt_chars=%d", #tostring(bootstrap.prompt)))
print(string.format("merged_fp_tick0=%d", merged_fp(states)))

for t = 1, ticks do
  for i = 1, #states do
    tick_c(states[i])
  end

  if t == 1 or t == ring or t == ticks then
    print(string.format("tick=%d merged_fp=%d", t, merged_fp(states)))
    for i = 1, #states do
      local snap = snapshot(states[i])
      print(string.format(
        "core=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d",
        i,
        snap.fp,
        snap.trace_density,
        snap.distinct_core,
        snap.distinct_trace
      ))
    end
  end
end
