local DEFAULT_WIDTH = 12
local DEFAULT_HEIGHT = 10
local DEFAULT_TICKS = 128
local DEFAULT_SEED = 12345
local DIRS = { "E", "W", "NE", "NW", "SE", "SW" }

local function wrap(v, n)
  return ((v - 1) % n) + 1
end

local function cell_id(x, y, width)
  return (y - 1) * width + x
end

local function make_rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = 1 end
  return function()
    state = (state * 48271) % 2147483647
    return state
  end
end

local function hash_noise(x, y, tick, seed)
  local v = x * 92821 + y * 68917 + tick * 1237 + seed * 17
  v = (v ~ (v << 13)) & 0x7fffffff
  v = (v ~ (v >> 17)) & 0x7fffffff
  v = (v ~ (v << 5)) & 0x7fffffff
  return v % 256
end

local function make_grid(width, height)
  local grid = {}
  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      local band = (y - 1) / height
      local kind
      if band < 0.25 then
        kind = "OBSERVE"
      elseif band < 0.5 then
        kind = "CHOOSE"
      elseif band < 0.75 then
        kind = "ENCODE"
      else
        kind = "RUNTIME"
      end

      grid[y][x] = {
        kind = kind,
        charge = 0,
        next_charge = 0,
        mark = 0,
        phase = 0,
        calm_hits = 0,
      }
    end
  end
  return grid
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

local function all_neighbors(x, y, width, height)
  local out = {}
  for _, dir in ipairs(DIRS) do
    local nx, ny = neighbor(x, y, dir, width, height)
    out[#out + 1] = { x = nx, y = ny, dir = dir }
  end
  return out
end

local function make_walkers(width)
  return {
    { x = 2, y = 1, dir = "SE", load = 0, age = 0, alive = true },
    { x = math.max(3, math.floor(width / 3)), y = 1, dir = "SW", load = 0, age = 0, alive = true },
    { x = math.max(4, math.floor(width * 2 / 3)), y = 1, dir = "SE", load = 0, age = 0, alive = true },
    { x = width, y = 1, dir = "SW", load = 0, age = 0, alive = true },
  }
end

local function inject_from_l1(grid, width, tick, seed)
  local total = 0
  for x = 1, width do
    local cell = grid[1][x]
    local pressure = hash_noise(x, 1, tick, seed)
    if pressure > 96 then
      local pulse = math.floor((pressure - 96) / 8)
      cell.charge = math.min(255, cell.charge + pulse)
    end
    total = total + cell.charge
  end
  return total
end

local function diffuse_charge(grid, width, height)
  for y = 1, height do
    for x = 1, width do
      local cell = grid[y][x]
      local retain = math.floor(cell.charge * 0.60)
      local spread = math.floor((cell.charge - retain) / 6)
      cell.next_charge = cell.next_charge + retain
      if spread > 0 then
        for _, n in ipairs(all_neighbors(x, y, width, height)) do
          grid[n.y][n.x].next_charge = math.min(255, grid[n.y][n.x].next_charge + spread)
        end
      end
    end
  end

  local total = 0
  for y = 1, height do
    for x = 1, width do
      local cell = grid[y][x]
      cell.charge = math.min(255, cell.next_charge)
      cell.next_charge = 0
      total = total + cell.charge
    end
  end
  return total
end

local function choose_best_neighbor(grid, x, y, width, height, prefer_up)
  local best = nil
  for _, n in ipairs(all_neighbors(x, y, width, height)) do
    local charge = grid[n.y][n.x].charge
    local score = charge
    if prefer_up and (n.dir == "NE" or n.dir == "NW") then
      score = score + 16
    end
    if not prefer_up and (n.dir == "SE" or n.dir == "SW") then
      score = score + 8
    end
    if not best or score > best.score then
      best = { x = n.x, y = n.y, dir = n.dir, score = score }
    end
  end
  return best
end

local function choose_flow_neighbor(state, x, y, primary_dirs, fallback_dirs)
  local best = nil
  for _, dir in ipairs(primary_dirs) do
    local nx, ny = neighbor(x, y, dir, state.width, state.height)
    local charge = state.grid[ny][nx].charge
    local score = charge + 24
    if not best or score > best.score then
      best = { x = nx, y = ny, dir = dir, score = score }
    end
  end
  if best then
    return best
  end
  return choose_best_neighbor(state.grid, x, y, state.width, state.height, fallback_dirs == "up")
end

local function tick_walkers(state)
  local collapse_events = 0
  local encode_events = 0
  local runtime_hits = 0

  for _, walker in ipairs(state.walkers) do
    if walker.alive then
      local cell = state.grid[walker.y][walker.x]
      walker.age = walker.age + 1

      if cell.kind == "OBSERVE" then
        walker.load = math.max(walker.load, cell.charge)
        local next_hop = choose_flow_neighbor(state, walker.x, walker.y, { "SE", "SW" }, "down")
        walker.x, walker.y, walker.dir = next_hop.x, next_hop.y, next_hop.dir
        cell.mark = math.min(255, cell.mark + 1)
      elseif cell.kind == "CHOOSE" then
        local next_hop = choose_flow_neighbor(state, walker.x, walker.y, { "SE", "SW", "E", "W" }, "down")
        walker.load = math.min(255, walker.load + math.floor(cell.charge * 0.25) + 4)
        walker.x, walker.y, walker.dir = next_hop.x, next_hop.y, next_hop.dir
        cell.mark = math.min(255, cell.mark + 2)
        collapse_events = collapse_events + 1
      elseif cell.kind == "ENCODE" then
        if walker.load >= 16 and (cell.charge >= 6 or walker.age >= state.height) then
          walker.load = math.min(255, walker.load + 12)
          state.pending_crystals = state.pending_crystals + 1
          encode_events = encode_events + 1
        else
          walker.load = math.min(255, walker.load + math.floor(cell.charge * 0.20) + 2)
        end
        local next_hop = choose_flow_neighbor(state, walker.x, walker.y, { "SE", "SW", "E", "W" }, "down")
        walker.x, walker.y, walker.dir = next_hop.x, next_hop.y, next_hop.dir
        cell.mark = math.min(255, cell.mark + 1)
      elseif cell.kind == "RUNTIME" then
        if state.pending_crystals > 0 and walker.load > 0 then
          state.pending_crystals = state.pending_crystals - 1
          state.calm = state.calm + walker.load
          cell.calm_hits = cell.calm_hits + 1
          runtime_hits = runtime_hits + 1
          walker.load = math.floor(walker.load * 0.35)
        else
          walker.load = math.floor(walker.load * 0.92)
        end
        local next_hop = choose_flow_neighbor(state, walker.x, walker.y, { "NW", "NE" }, "up")
        walker.x, walker.y, walker.dir = next_hop.x, next_hop.y, next_hop.dir
      end

      if walker.age > state.height * 8 and walker.load == 0 then
        walker.alive = false
      end
    end
  end

  return collapse_events, encode_events, runtime_hits
end

local function count_alive_walkers(walkers)
  local n = 0
  for _, walker in ipairs(walkers) do
    if walker.alive then n = n + 1 end
  end
  return n
end

local function render_kinds(grid, width, height)
  local map = {
    OBSERVE = "O",
    CHOOSE = "C",
    ENCODE = "E",
    RUNTIME = "R",
  }
  for y = 1, height do
    local line = {}
    if y % 2 == 0 then
      line[#line + 1] = " "
    end
    for x = 1, width do
      line[#line + 1] = map[grid[y][x].kind]
      line[#line + 1] = " "
    end
    print(table.concat(line))
  end
end

local function run(width, height, ticks, seed)
  local state = {
    width = width,
    height = height,
    grid = make_grid(width, height),
    walkers = make_walkers(width),
    pending_crystals = 0,
    calm = 0,
  }

  print(string.format("L2 boundary stand :: width=%d height=%d ticks=%d seed=%d", width, height, ticks, seed))
  print("")
  print("Node kinds:")
  render_kinds(state.grid, width, height)
  print("")

  local total_collapse = 0
  local total_encode = 0
  local total_runtime_hits = 0

  for tick = 1, ticks do
    inject_from_l1(state.grid, width, tick, seed)
    local total_charge = diffuse_charge(state.grid, width, height)
    local collapse_events, encode_events, runtime_hits = tick_walkers(state)
    total_collapse = total_collapse + collapse_events
    total_encode = total_encode + encode_events
    total_runtime_hits = total_runtime_hits + runtime_hits

    if tick == 1 or tick % math.max(1, math.floor(ticks / 8)) == 0 or tick == ticks then
      print(string.format(
        "[tick=%d] walkers=%d charge=%d collapse=%d encode=%d runtime_hits=%d calm=%d pending=%d",
        tick,
        count_alive_walkers(state.walkers),
        total_charge,
        total_collapse,
        total_encode,
        total_runtime_hits,
        state.calm,
        state.pending_crystals
      ))
    end
  end

  print("")
  print("Final walkers:")
  for idx, walker in ipairs(state.walkers) do
    print(string.format(
      "  walker[%d] alive=%s pos=(%d,%d) dir=%s load=%d age=%d",
      idx,
      tostring(walker.alive),
      walker.x,
      walker.y,
      walker.dir,
      walker.load,
      walker.age
    ))
  end

  print("")
  print(string.format(
    "Summary :: calm=%d collapse=%d encode=%d runtime_hits=%d",
    state.calm,
    total_collapse,
    total_encode,
    total_runtime_hits
  ))
end

local width = tonumber(arg[1]) or DEFAULT_WIDTH
local height = tonumber(arg[2]) or DEFAULT_HEIGHT
local ticks = tonumber(arg[3]) or DEFAULT_TICKS
local seed = tonumber(arg[4]) or DEFAULT_SEED

run(width, height, ticks, seed)
