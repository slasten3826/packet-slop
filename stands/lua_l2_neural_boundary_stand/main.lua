local DEFAULT_L1_RING = 4096
local DEFAULT_L1_CW = 256
local DEFAULT_TICKS = 160
local DEFAULT_SEED = 12345
local DIRS = { "E", "W", "NE", "NW", "SE", "SW" }

local KIND_GLYPH = {
  OBSERVE = "O",
  CHOOSE = "C",
  ENCODE = "E",
  RUNTIME = "R",
}

local PU_COST = {
  OBSERVE = 1,
  CHOOSE = 2,
  ENCODE = 3,
  RUNTIME = 2,
}

local function wrap(v, n)
  return ((v - 1) % n) + 1
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
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
      for _, dir in ipairs(DIRS) do
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

local function render_kinds(grid, width, height)
  local max_rows = math.min(height, 12)
  local max_cols = math.min(width, 28)
  for y = 1, max_rows do
    local line = {}
    if y % 2 == 0 then
      line[#line + 1] = " "
    end
    for x = 1, max_cols do
      line[#line + 1] = KIND_GLYPH[grid[y][x].kind]
      line[#line + 1] = " "
    end
    if max_cols < width then
      line[#line + 1] = "..."
    end
    print(table.concat(line))
  end
  if max_rows < height then
    print("...")
  end
end

local function neighbor_sum(grid, x, y, width, height)
  local total = 0.0
  for _, dir in ipairs(DIRS) do
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

local function tick_neural(state, tick)
  local collapse_events = 0
  local encode_events = 0
  local runtime_hits = 0
  local pu_spent_tick = 0

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = state.grid[y][x]
      local base_cost = PU_COST[cell.kind]

      if state.pu_remaining >= base_cost then
        state.pu_remaining = state.pu_remaining - base_cost
        state.pu_spent[cell.kind] = state.pu_spent[cell.kind] + base_cost
        pu_spent_tick = pu_spent_tick + base_cost

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
            pu_spent_tick = pu_spent_tick + 4
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
              pu_spent_tick = pu_spent_tick + spent
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

  local sums = {
    OBSERVE = 0.0,
    CHOOSE = 0.0,
    ENCODE = 0.0,
    RUNTIME = 0.0,
  }

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = state.grid[y][x]
      cell.activation = cell.next_activation
      cell.next_activation = 0.0
      sums[cell.kind] = sums[cell.kind] + cell.activation
    end
  end

  return sums, collapse_events, encode_events, runtime_hits, pu_spent_tick
end

local function run(l1_ring, l1_cw, ticks, seed)
  local width, height = derive_l2_shape(l1_ring, l1_cw)
  local pu_budget = derive_pu_budget(l1_ring, l1_cw, width, height)
  local state = {
    width = width,
    height = height,
    seed = seed,
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
  }

  print(string.format(
    "L2 neural boundary stand :: l1_ring=%d l1_cw=%d -> width=%d height=%d ticks=%d seed=%d pu=%d",
    l1_ring, l1_cw, width, height, ticks, seed, pu_budget
  ))
  print(string.format(
    "Derived :: l1_gain=%.3f l3_feedback_ceiling=%.3f",
    state.l1_gain, state.l3_feedback_ceiling
  ))
  print("")
  print("Node kinds:")
  render_kinds(state.grid, width, height)
  print("")

  local total_collapse = 0
  local total_encode = 0
  local total_runtime = 0

  for tick = 1, ticks do
    local sums, collapse_events, encode_events, runtime_hits, pu_spent_tick = tick_neural(state, tick)
    total_collapse = total_collapse + collapse_events
    total_encode = total_encode + encode_events
    total_runtime = total_runtime + runtime_hits

    if tick == 1 or tick % math.max(1, math.floor(ticks / 8)) == 0 or tick == ticks then
      print(string.format(
        "[tick=%d] O=%.2f C=%.2f E=%.2f R=%.2f collapse=%d encode=%d runtime_hits=%d calm=%d pending=%d pu_tick=%d pu_left=%d",
        tick,
        sums.OBSERVE,
        sums.CHOOSE,
        sums.ENCODE,
        sums.RUNTIME,
        total_collapse,
        total_encode,
        total_runtime,
        state.calm,
        state.pending_crystals,
        pu_spent_tick,
        state.pu_remaining
      ))
    end

    if state.pu_remaining <= 0 then
      print(string.format("[tick=%d] PU exhausted, stopping", tick))
      break
    end
  end

  print("")
  print(string.format(
    "Summary :: collapse=%d encode=%d runtime_hits=%d calm=%d pending=%d pu_left=%d",
    total_collapse,
    total_encode,
    total_runtime,
    state.calm,
    state.pending_crystals,
    state.pu_remaining
  ))
  print(string.format(
    "PU trace :: OBSERVE=%d CHOOSE=%d ENCODE=%d RUNTIME=%d",
    state.pu_spent.OBSERVE,
    state.pu_spent.CHOOSE,
    state.pu_spent.ENCODE,
    state.pu_spent.RUNTIME
  ))
end

local l1_ring = tonumber(arg[1]) or DEFAULT_L1_RING
local l1_cw = tonumber(arg[2]) or DEFAULT_L1_CW
local ticks = tonumber(arg[3]) or DEFAULT_TICKS
local seed = tonumber(arg[4]) or DEFAULT_SEED

run(l1_ring, l1_cw, ticks, seed)
