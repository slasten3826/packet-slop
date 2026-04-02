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

local function snapshot_l1(state)
  return {
    fp = fingerprint(state.core, state.trace, state.carry, state.pos),
    distinct_core = distinct_count(state.core),
    distinct_trace = distinct_count(state.trace),
    trace_density = trace_density(state.trace),
  }
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

local function build_l1_states(token_ids, m)
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

local function derive_l2_shape(l1_ring, l1_cw)
  local base = math.max(8, math.floor(math.sqrt(l1_ring) / 2))
  local pressure_factor = 1.0 + math.log(math.max(1, l1_cw), 2) / 8.0
  local width = math.max(12, math.floor(base * pressure_factor))
  local height = math.max(10, math.floor(width * 0.85))
  return width, height
end

local function derive_pu_budget(l1_ring, l1_cw, width, height)
  local area = width * height
  local pressure = 1.0 + math.log(math.max(1, l1_cw), 2) / 4.0
  local space = 1.0 + math.log(math.max(1, l1_ring), 2) / 6.0
  return math.floor(area * pressure * space * 3.5)
end

local function derive_l1_gain(l1_cw)
  return 0.22 + math.log(math.max(1, l1_cw), 2) * 0.015
end

local function derive_l3_feedback_ceiling(l1_ring, l1_cw)
  local ring_term = math.log(math.max(1, l1_ring), 2) * 0.004
  local cw_term = math.log(math.max(1, l1_cw), 2) * 0.006
  return 0.08 + ring_term + cw_term
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

local function kind_for_position(x, y)
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

local function build_grid(width, height, seed)
  local rng = make_rng(seed)
  local grid = {}
  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      local kind = kind_for_position(x, y)
      local weights = {}
      for _, dir in ipairs(L2_DIRS) do
        weights[dir] = 0.12 + randf(rng) * 0.48
      end
      grid[y][x] = {
        kind = kind,
        activation = 0.0,
        next_activation = 0.0,
        stability = 0,
        threshold = ({
          OBSERVE = 0.30,
          CHOOSE = 0.50,
          ENCODE = 0.62,
          RUNTIME = 0.42,
        })[kind],
        decay = ({
          OBSERVE = 0.84,
          CHOOSE = 0.79,
          ENCODE = 0.86,
          RUNTIME = 0.90,
        })[kind],
        bias = ({
          OBSERVE = 0.01,
          CHOOSE = 0.00,
          ENCODE = 0.00,
          RUNTIME = 0.02,
        })[kind],
        weights = weights,
        encoded = 0,
      }
    end
  end
  return grid
end

local function neighbor_sum(grid, x, y, width, height)
  local total = 0.0
  for _, dir in ipairs(L2_DIRS) do
    local nx, ny = neighbor(x, y, dir, width, height)
    total = total + grid[ny][nx].activation * grid[y][x].weights[dir]
  end
  return total / 6.0
end

local function l1_pressure(state, cell, x, y, tick)
  if cell.kind == "RUNTIME" then
    return 0.0
  end
  local depth = 1.0 - ((y - 1) / math.max(1, state.height - 1))
  local n = hash_noise(x, y, tick, state.seed)
  local spike = 0.0
  if n > 0.86 then
    spike = (n - 0.86) * 1.8
  end
  return depth * state.l1_gain + spike
end

local function l3_feedback(state, cell, y)
  if cell.kind ~= "RUNTIME" then
    return 0.0
  end
  local topness = (y - 1) / math.max(1, state.height - 1)
  return topness * math.min(state.l3_feedback_ceiling, state.calm / 4000.0)
end

local function tick_l2_neural(state, tick)
  local collapse_events = 0
  local encode_events = 0
  local runtime_hits = 0

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = state.grid[y][x]
      local base_cost = ({
        OBSERVE = 1,
        CHOOSE = 2,
        ENCODE = 3,
        RUNTIME = 2,
      })[cell.kind]

      if state.pu_remaining >= base_cost then
        state.pu_remaining = state.pu_remaining - base_cost
        state.pu_spent[cell.kind] = state.pu_spent[cell.kind] + base_cost

        local neigh = neighbor_sum(state.grid, x, y, state.width, state.height)
        local from_l1 = l1_pressure(state, cell, x, y, tick)
        local from_l3 = l3_feedback(state, cell, y)
        local raw = cell.activation * cell.decay + neigh + from_l1 + from_l3 + cell.bias
        local next_act = raw

        if cell.kind == "OBSERVE" then
          next_act = raw * 0.90
        elseif cell.kind == "CHOOSE" then
          local sharpen = raw - math.max(0.0, neigh * 0.45)
          next_act = sharpen
          if sharpen > cell.threshold then
            collapse_events = collapse_events + 1
          end
        elseif cell.kind == "ENCODE" then
          if raw > cell.threshold then
            cell.stability = cell.stability + 1
          else
            cell.stability = math.max(0, cell.stability - 1)
          end
          next_act = raw
          if cell.stability >= 3 and raw > (cell.threshold + 0.05) and state.pu_remaining >= 4 then
            state.pu_remaining = state.pu_remaining - 4
            state.pu_spent.ENCODE = state.pu_spent.ENCODE + 4
            encode_events = encode_events + 1
            cell.encoded = cell.encoded + 1
            state.pending_crystals = state.pending_crystals + 1
            cell.stability = 1
            next_act = raw * 0.66
          end
        elseif cell.kind == "RUNTIME" then
          local gain = math.min(0.15, state.pending_crystals * 0.015)
          next_act = raw + gain
          if state.pending_crystals > 0 and raw > cell.threshold then
            local accepted = math.min(state.pending_crystals, 1 + math.floor(raw))
            local max_affordable = math.floor(state.pu_remaining / 3)
            accepted = math.min(accepted, max_affordable)
            if accepted > 0 then
              local spent = accepted * 3
              state.pu_remaining = state.pu_remaining - spent
              state.pu_spent.RUNTIME = state.pu_spent.RUNTIME + spent
              state.pending_crystals = state.pending_crystals - accepted
              state.calm = state.calm + accepted * 4 + math.floor(raw * 6.0)
              runtime_hits = runtime_hits + accepted
              next_act = raw * 0.60
            end
          end
        end

        cell.next_activation = clamp(next_act, 0.0, 1.0)
      else
        cell.next_activation = 0.0
      end
    end
  end

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = state.grid[y][x]
      cell.activation = cell.next_activation
      cell.next_activation = 0.0
    end
  end

  return collapse_events, encode_events, runtime_hits
end

local function build_l2_state(l1_ring, l1_cw, ticks, seed)
  local width, height = derive_l2_shape(l1_ring, l1_cw)
  local pu_budget = derive_pu_budget(l1_ring, l1_cw, width, height)
  return {
    width = width,
    height = height,
    seed = seed,
    ticks = ticks,
    l1_ring = l1_ring,
    l1_cw = l1_cw,
    l1_gain = derive_l1_gain(l1_cw),
    l3_feedback_ceiling = derive_l3_feedback_ceiling(l1_ring, l1_cw),
    grid = build_grid(width, height, seed),
    calm = 0,
    pending_crystals = 0,
    pu_budget = pu_budget,
    pu_remaining = pu_budget,
    pu_spent = {
      OBSERVE = 0,
      CHOOSE = 0,
      ENCODE = 0,
      RUNTIME = 0,
    },
    total_collapse = 0,
    total_encode = 0,
    total_runtime = 0,
  }
end

local function print_usage()
  io.write("usage: lua main.lua <bootstrap_dump.lua> <multiplier> [l1_ticks] [l2_ticks]\n")
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
local l1_ticks = tonumber(arg[3] or tostring(ring * 2))
local l2_ticks = tonumber(arg[4] or "160")
local l1_cw = 1
local l1_states = build_l1_states(bootstrap.token_ids, m)

print("l1+l2 multiplier stand")
print(string.format("model=%s", tostring(bootstrap.model_path)))
print(string.format("ring=%d multiplier=%d l1_ticks=%d l2_ticks=%d l1_cw=%d", ring, m, l1_ticks, l2_ticks, l1_cw))
print(string.format("prompt_chars=%d", #tostring(bootstrap.prompt)))

for t = 1, l1_ticks do
  for i = 1, #l1_states do
    tick_l1_c(l1_states[i])
  end
end

print("")
print("L1 final snapshots:")
local l2_states = {}
for i = 1, #l1_states do
  local l1_snap = snapshot_l1(l1_states[i])
  print(string.format(
    "core=%d fp=%d trace_density=%d distinct_core=%d distinct_trace=%d",
    i,
    l1_snap.fp,
    l1_snap.trace_density,
    l1_snap.distinct_core,
    l1_snap.distinct_trace
  ))

  l2_states[i] = build_l2_state(ring, l1_cw, l2_ticks, l1_snap.fp)
end

for tick = 1, l2_ticks do
  for i = 1, #l2_states do
    local state = l2_states[i]
    local collapse_events, encode_events, runtime_hits = tick_l2_neural(state, tick)
    state.total_collapse = state.total_collapse + collapse_events
    state.total_encode = state.total_encode + encode_events
    state.total_runtime = state.total_runtime + runtime_hits
  end
end

print("")
print("L2 final snapshots:")
for i = 1, #l2_states do
  local state = l2_states[i]
  print(string.format(
    "core=%d seed=%d l2=%dx%d pu_max=%d calm=%d pending=%d collapse=%d encode=%d runtime_hits=%d pu_left=%d",
    i,
    state.seed,
    state.width,
    state.height,
    state.pu_budget,
    state.calm,
    state.pending_crystals,
    state.total_collapse,
    state.total_encode,
    state.total_runtime,
    state.pu_remaining
  ))
end
