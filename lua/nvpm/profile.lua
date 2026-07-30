local M = {}

---@alias NvpmProfile {data: string|{[string]:string}, time: number, [number]:NvpmProfile}

---@type NvpmProfile[]
M._profiles = { { name = "nvpm" } }
M._start = nil

function M.reset()
  M._profiles = { { name = "nvpm" } }
  M._start = (vim.uv or vim.loop).hrtime()
end

--- Start a nested span with `data`, or close the current span when called with no args.
---@param data (string|{[string]:string})?
---@param time number?
---@return NvpmProfile
function M.track(data, time)
  if data then
    local entry = {
      data = data,
      time = time or (vim.uv or vim.loop).hrtime(),
    }
    table.insert(M._profiles[#M._profiles], entry)
    if not time then
      table.insert(M._profiles, entry)
    end
    return entry
  end
  local entry = table.remove(M._profiles)
  entry.time = (vim.uv or vim.loop).hrtime() - entry.time
  return entry
end

---@generic F: fun()
---@param data (string|{[string]:string})?
---@param fn F
---@return any
function M.trackfn(data, fn)
  M.track(data)
  local ok, ret = pcall(fn)
  M.track()
  if not ok then
    error(ret)
  end
  return ret
end

---@param ns number
---@return number
function M.ms(ns)
  return ns / 1e6
end

function M.root()
  return M._profiles[1]
end

function M.total_ms()
  if not M._start then
    return 0
  end
  local total_ns = 0
  local rows = vim.tbl_filter(function(row)
    return row.depth == 0
  end, M.rows())
  for _, row in ipairs(rows) do
    total_ns = total_ns + row.ms * 1e6
  end
  return M.ms(total_ns)
end

local function label(data)
  if type(data) == "string" then
    return data
  end
  if type(data) == "table" then
    local parts = {}
    for k, v in pairs(data) do
      parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    end
    table.sort(parts)
    return table.concat(parts, " ")
  end
  return tostring(data)
end

local function collect(entry, depth, rows)
  for _, child in ipairs(entry) do
    if type(child) == "table" and child.data ~= nil then
      rows[#rows + 1] = {
        depth = depth,
        label = label(child.data),
        ms = M.ms(child.time or 0),
      }
      collect(child, depth + 1, rows)
    end
  end
end

---@return {depth:number, label:string, ms:number}[]
function M.rows()
  local rows = {}
  local root = M.root()
  if root then
    collect(root, 0, rows)
  end
  return rows
end

function M.format()
  local lines = {
    ("nvpm profile (total %.2f ms)"):format(M.total_ms()),
  }
  for _, row in ipairs(M.rows()) do
    lines[#lines + 1] = ("%s%6.2f ms  %s"):format(string.rep("  ", row.depth), row.ms, row.label)
  end
  return table.concat(lines, "\n")
end

function M.print()
  print(M.format())
end

return M
