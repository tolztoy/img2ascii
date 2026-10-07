local zlib = require "zlib"

local M = {}

local SIG = "\137PNG\r\n\26\n"

local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }

local VALID = {
  [0] = { [1] = true, [2] = true, [4] = true, [8] = true, [16] = true },
  [2] = { [8] = true, [16] = true },
  [3] = { [1] = true, [2] = true, [4] = true, [8] = true },
  [4] = { [8] = true, [16] = true },
  [6] = { [8] = true, [16] = true },
}

local PASSES = {
  { 0, 0, 8, 8 }, { 4, 0, 8, 8 }, { 0, 4, 4, 8 },
  { 2, 0, 4, 4 }, { 0, 2, 2, 4 }, { 1, 0, 2, 2 }, { 0, 1, 1, 2 },
}

local GRAY3 = {}
for v = 0, 255 do
  GRAY3[v] = string.char(v, v, v)
end

local function be32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return a * 16777216 + b * 65536 + c * 256 + d
end

local function paeth(a, b, c)
  local p = a + b - c
  local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
  if pa <= pb and pa <= pc then
    return a
  elseif pb <= pc then
    return b
  end
  return c
end

local function unfilter(raw, offset, stride, height, bpp)
  local prev = {}
  for i = 1, stride do
    prev[i] = 0
  end
  local rows = {}
  local p = offset
  for y = 1, height do
    local f = raw:byte(p)
    p = p + 1
    local row = { raw:byte(p, p + stride - 1) }
    p = p + stride
    if f == 1 then
      for i = bpp + 1, stride do
        row[i] = (row[i] + row[i - bpp]) % 256
      end
    elseif f == 2 then
      for i = 1, stride do
        row[i] = (row[i] + prev[i]) % 256
      end
    elseif f == 3 then
      for i = 1, stride do
        local left = i > bpp and row[i - bpp] or 0
        row[i] = (row[i] + math.floor((left + prev[i]) / 2)) % 256
      end
    elseif f == 4 then
      for i = 1, stride do
        local left = i > bpp and row[i - bpp] or 0
        local upleft = i > bpp and prev[i - bpp] or 0
        row[i] = (row[i] + paeth(left, prev[i], upleft)) % 256
      end
    elseif f ~= 0 then
      error("png: unknown filter type " .. tostring(f))
    end
    rows[y] = row
    prev = row
  end
  return rows, p
end

local function expand_row(row, width, bitdepth, colortype, palette)
  local out = {}
  if colortype == 2 and bitdepth == 8 then
    for i = 1, width, 256 do
      local last = math.min(i + 255, width)
      local from = (i - 1) * 3 + 1
      local to = (last - 1) * 3 + 3
      out[#out + 1] = string.char(table.unpack(row, from, to))
    end
  elseif colortype == 6 and bitdepth == 8 then
    for i = 0, width - 1 do
      local o = i * 4 + 1
      out[#out + 1] = string.char(row[o], row[o + 1], row[o + 2])
    end
  elseif colortype == 0 and bitdepth == 8 then
    for i = 1, width do
      out[#out + 1] = GRAY3[row[i]]
    end
  elseif colortype == 4 and bitdepth == 8 then
    for i = 0, width - 1 do
      out[#out + 1] = GRAY3[row[i * 2 + 1]]
    end
  elseif colortype == 3 then
    for i = 0, width - 1 do
      local v
      if bitdepth == 8 then
        v = row[i + 1]
      else
        local bitpos = i * bitdepth
        local byte = row[math.floor(bitpos / 8) + 1]
        local shift = 8 - bitdepth - (bitpos % 8)
        v = (byte >> shift) & ((1 << bitdepth) - 1)
      end
      out[#out + 1] = palette[v + 1] or "\0\0\0"
    end
  elseif colortype == 0 and bitdepth == 16 then
    for i = 1, width do
      out[#out + 1] = GRAY3[row[i * 2 - 1]]
    end
  elseif colortype == 4 and bitdepth == 16 then
    for i = 1, width do
      out[#out + 1] = GRAY3[row[i * 4 - 3]]
    end
  elseif colortype == 2 and bitdepth == 16 then
    for i = 0, width - 1 do
      local o = i * 6 + 1
      out[#out + 1] = string.char(row[o], row[o + 2], row[o + 4])
    end
  elseif colortype == 6 and bitdepth == 16 then
    for i = 0, width - 1 do
      local o = i * 8 + 1
      out[#out + 1] = string.char(row[o], row[o + 2], row[o + 4])
    end
  elseif colortype == 0 then
    local scale = 255 / ((1 << bitdepth) - 1)
    for i = 0, width - 1 do
      local bitpos = i * bitdepth
      local byte = row[math.floor(bitpos / 8) + 1]
      local shift = 8 - bitdepth - (bitpos % 8)
      local v = (byte >> shift) & ((1 << bitdepth) - 1)
      out[#out + 1] = GRAY3[math.floor(v * scale + 0.5)]
    end
  else
    error("png: unsupported color type/bit depth " .. colortype .. "/" .. bitdepth)
  end
  return table.concat(out)
end

function M.decode(data)
  if data:sub(1, 8) ~= SIG then
    error("png: bad signature")
  end
  local pos = 9
  local ihdr, plte
  local idat = {}
  while pos + 11 <= #data do
    local len = be32(data, pos)
    local typ = data:sub(pos + 4, pos + 7)
    if typ == "IHDR" then
      ihdr = data:sub(pos + 8, pos + 7 + len)
    elseif typ == "PLTE" then
      plte = data:sub(pos + 8, pos + 7 + len)
    elseif typ == "IDAT" then
      idat[#idat + 1] = data:sub(pos + 8, pos + 7 + len)
    elseif typ == "IEND" then
      break
    end
    pos = pos + 12 + len
  end
  if not ihdr or #ihdr < 13 then
    error("png: missing IHDR")
  end
  if #idat == 0 then
    error("png: missing IDAT")
  end
  local w = be32(ihdr, 1)
  local h = be32(ihdr, 5)
  local bitdepth = ihdr:byte(9)
  local colortype = ihdr:byte(10)
  local interlace = ihdr:byte(13)
  if w < 1 or h < 1 or w > 16384 or h > 16384 or w * h > 40000000 then
    error("png: dimensions out of range")
  end
  if not (VALID[colortype] and VALID[colortype][bitdepth]) then
    error("png: unsupported color type/bit depth " .. tostring(colortype) .. "/" .. tostring(bitdepth))
  end
  if colortype == 3 and not plte then
    error("png: missing PLTE")
  end
  local palette
  if colortype == 3 then
    palette = {}
    for i = 1, math.floor(#plte / 3) do
      palette[i] = plte:sub((i - 1) * 3 + 1, (i - 1) * 3 + 3)
    end
  end
  local raw, eof = zlib.inflate()(table.concat(idat), "finish")
  if type(raw) ~= "string" then
    error("png: decompression failed")
  end
  local channels = CHANNELS[colortype]
  local bpp = math.max(1, math.ceil(channels * bitdepth / 8))
  local lines
  if interlace == 0 then
    local stride = math.ceil(w * channels * bitdepth / 8)
    if #raw < h * (stride + 1) then
      error("png: truncated pixel data")
    end
    local rows = unfilter(raw, 1, stride, h, bpp)
    lines = {}
    for y = 1, h do
      lines[y] = expand_row(rows[y], w, bitdepth, colortype, palette)
    end
  elseif interlace == 1 then
    local total = 0
    local plan = {}
    for _, pass in ipairs(PASSES) do
      local x0, y0, dx, dy = pass[1], pass[2], pass[3], pass[4]
      local pw = w > x0 and math.ceil((w - x0) / dx) or 0
      local ph = h > y0 and math.ceil((h - y0) / dy) or 0
      if pw > 0 and ph > 0 then
        local stride = math.ceil(pw * channels * bitdepth / 8)
        plan[#plan + 1] = { x0, y0, dx, dy, pw, ph, stride }
        total = total + ph * (stride + 1)
      end
    end
    if #raw < total then
      error("png: truncated pixel data")
    end
    local grid = {}
    for y = 1, h do
      grid[y] = {}
    end
    local p = 1
    for _, entry in ipairs(plan) do
      local x0, y0, dx, dy = entry[1], entry[2], entry[3], entry[4]
      local pw, ph, stride = entry[5], entry[6], entry[7]
      local rows
      rows, p = unfilter(raw, p, stride, ph, bpp)
      for py = 1, ph do
        local line = expand_row(rows[py], pw, bitdepth, colortype, palette)
        local gline = grid[y0 + (py - 1) * dy + 1]
        for px = 1, pw do
          gline[x0 + (px - 1) * dx + 1] = line:sub((px - 1) * 3 + 1, px * 3)
        end
      end
    end
    lines = {}
    for y = 1, h do
      lines[y] = table.concat(grid[y])
    end
  else
    error("png: unknown interlace method " .. tostring(interlace))
  end
  return { width = w, height = h, data = table.concat(lines) }
end

return M
