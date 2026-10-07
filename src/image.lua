local png = require "src.png"

local M = {}

local function le16(s, i)
  local a, b = s:byte(i, i + 1)
  return a + b * 256
end

local function le32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function pnm_tokens(data, count)
  local tokens = {}
  local pos = 1
  while #tokens < count and pos <= #data do
    local b = data:byte(pos)
    if b == 35 then
      local nl = data:find("\n", pos, true)
      pos = nl and (nl + 1) or (#data + 1)
    elseif b == 32 or b == 9 or b == 10 or b == 13 then
      pos = pos + 1
    else
      local s, e = data:find("%S+", pos)
      tokens[#tokens + 1] = data:sub(s, e)
      pos = e + 1
    end
  end
  return tokens, pos
end

local function gray_expand(bytes, count)
  local parts = {}
  local buf = {}
  for i = 1, count do
    local v = bytes[i]
    buf[#buf + 1] = v
    buf[#buf + 1] = v
    buf[#buf + 1] = v
    if #buf >= 3072 then
      parts[#parts + 1] = string.char(table.unpack(buf))
      buf = {}
    end
  end
  if #buf > 0 then
    parts[#parts + 1] = string.char(table.unpack(buf))
  end
  return table.concat(parts)
end

local function read_pnm(data)
  local t, pos = pnm_tokens(data, 4)
  if #t < 4 then
    return nil
  end
  local magic = t[1]
  if magic ~= "P2" and magic ~= "P3" and magic ~= "P5" and magic ~= "P6" then
    return nil
  end
  local w = tonumber(t[2])
  local h = tonumber(t[3])
  local maxval = tonumber(t[4])
  if not w or not h or not maxval then
    return nil
  end
  if w < 1 or h < 1 or w > 16384 or h > 16384 or w * h > 40000000 then
    return nil
  end
  local color = magic == "P3" or magic == "P6"
  local channels = color and 3 or 1
  local count = w * h * channels
  if magic == "P6" then
    local b1 = data:byte(pos)
    local b2 = data:byte(pos + 1)
    if b1 == 13 and b2 == 10 then
      pos = pos + 2
    elseif b1 == 10 or b1 == 13 or b1 == 32 or b1 == 9 then
      pos = pos + 1
    end
    if maxval <= 255 then
      if #data - pos + 1 < count then
        return nil
      end
      return { width = w, height = h, data = data:sub(pos, pos + count - 1) }
    end
    if #data - pos + 1 < count * 2 then
      return nil
    end
    local parts = {}
    local buf = {}
    for i = 0, count - 1 do
      buf[#buf + 1] = data:byte(pos + i * 2)
      if #buf >= 3072 then
        parts[#parts + 1] = string.char(table.unpack(buf))
        buf = {}
      end
    end
    if #buf > 0 then
      parts[#parts + 1] = string.char(table.unpack(buf))
    end
    return { width = w, height = h, data = table.concat(parts) }
  elseif magic == "P5" then
    local b1 = data:byte(pos)
    local b2 = data:byte(pos + 1)
    if b1 == 13 and b2 == 10 then
      pos = pos + 2
    elseif b1 == 10 or b1 == 13 or b1 == 32 or b1 == 9 then
      pos = pos + 1
    end
    if maxval <= 255 then
      if #data - pos + 1 < count then
        return nil
      end
      return { width = w, height = h, data = gray_expand({ data:byte(pos, pos + count - 1) }, count) }
    end
    if #data - pos + 1 < count * 2 then
      return nil
    end
    local gray = {}
    for i = 0, count - 1 do
      gray[i + 1] = data:byte(pos + i * 2)
    end
    return { width = w, height = h, data = gray_expand(gray, count) }
  end
  local vals = {}
  for num in data:sub(pos):gmatch("%S+") do
    vals[#vals + 1] = tonumber(num)
    if #vals >= count then
      break
    end
  end
  if #vals < count then
    return nil
  end
  local scale = maxval > 255 and (255 / maxval) or nil
  if color then
    local parts = {}
    local buf = {}
    for i = 1, count do
      local v = vals[i]
      if scale then
        v = math.floor(v * scale + 0.5)
      end
      if v < 0 then v = 0 elseif v > 255 then v = 255 end
      buf[#buf + 1] = v
      if #buf >= 3072 then
        parts[#parts + 1] = string.char(table.unpack(buf))
        buf = {}
      end
    end
    if #buf > 0 then
      parts[#parts + 1] = string.char(table.unpack(buf))
    end
    return { width = w, height = h, data = table.concat(parts) }
  end
  for i = 1, count do
    local v = vals[i]
    if scale then
      v = math.floor(v * scale + 0.5)
    end
    if v < 0 then v = 0 elseif v > 255 then v = 255 end
    vals[i] = v
  end
  return { width = w, height = h, data = gray_expand(vals, count) }
end

local function read_bmp(data)
  if data:sub(1, 2) ~= "BM" or #data < 54 then
    return nil
  end
  local offset = le32(data, 11)
  local w = le32(data, 19)
  if w >= 2147483648 then
    w = w - 4294967296
  end
  local h = le32(data, 23)
  if h >= 2147483648 then
    h = h - 4294967296
  end
  local bpp = le16(data, 29)
  local comp = le32(data, 31)
  if comp ~= 0 or (bpp ~= 24 and bpp ~= 32) then
    return nil
  end
  local topdown = h < 0
  h = math.abs(h)
  if w < 1 or h < 1 or w > 16384 or h > 16384 or w * h > 40000000 then
    return nil
  end
  local bytespp = bpp / 8
  local rowsize = math.floor((bpp * w + 31) / 32) * 4
  if #data < offset + rowsize * h then
    return nil
  end
  local lines = {}
  for y = 0, h - 1 do
    local src_y = topdown and y or (h - 1 - y)
    local base = offset + src_y * rowsize + 1
    local parts = {}
    local buf = {}
    for x = 0, w - 1 do
      local o = base + x * bytespp
      local bpos, gpos, rpos = o, o + 1, o + 2
      buf[#buf + 1] = data:byte(rpos)
      buf[#buf + 1] = data:byte(gpos)
      buf[#buf + 1] = data:byte(bpos)
      if #buf >= 3072 then
        parts[#parts + 1] = string.char(table.unpack(buf))
        buf = {}
      end
    end
    if #buf > 0 then
      parts[#parts + 1] = string.char(table.unpack(buf))
    end
    lines[y + 1] = table.concat(parts)
  end
  return { width = w, height = h, data = table.concat(lines) }
end

local function decode_jpeg(data, djpeg)
  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  if not f then
    return nil, "jpeg: cannot write temp file"
  end
  f:write(data)
  f:close()
  local p = io.popen(string.format('"%s" -pnm "%s" 2>/dev/null', djpeg, tmp), "r")
  local out = p:read("a")
  p:close()
  os.remove(tmp)
  if not out or #out == 0 then
    return nil, "jpeg: decoding failed"
  end
  local img = read_pnm(out)
  if not img then
    return nil, "jpeg: unexpected decoder output"
  end
  return img
end

function M.decode(data, opts)
  opts = opts or {}
  if type(data) ~= "string" or #data == 0 then
    return nil, "file is empty"
  end
  local head = data:sub(1, 8)
  if head == "\137PNG\r\n\26\n" then
    local ok, res = pcall(png.decode, data)
    if ok then
      return res
    end
    return nil, res
  end
  if data:byte(1) == 255 and data:byte(2) == 216 and data:byte(3) == 255 then
    if not opts.djpeg then
      return nil, "jpeg support is not configured"
    end
    local ok, res, err = pcall(decode_jpeg, data, opts.djpeg)
    if not ok then
      return nil, "jpeg: " .. tostring(res)
    end
    return res, err
  end
  if data:sub(1, 2) == "BM" then
    local img = read_bmp(data)
    if img then
      return img
    end
    return nil, "bmp: unsupported or corrupt image"
  end
  local magic = data:sub(1, 2)
  if magic == "P2" or magic == "P3" or magic == "P5" or magic == "P6" then
    local img = read_pnm(data)
    if img then
      return img
    end
    return nil, "pnm: unsupported or corrupt image"
  end
  return nil, "unsupported format (use PNG, JPEG, BMP, PPM or PGM)"
end

return M
