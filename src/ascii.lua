local M = {}

M.ramps = {
  standard = " .:-=+*#%@",
  detailed = " .'`^\",:;Il!i><~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
  blocks = " ░▒▓█",
  solid = " .█",
}

local MAX_COLS = 400
local MAX_ROWS = 600
local MAX_GRID = 800000

local function ramp_chars(ramp)
  local chars = {}
  for _, cp in utf8.codes(ramp) do
    chars[#chars + 1] = utf8.char(cp)
  end
  return chars
end

local function html_escape(s)
  return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

local function luminance(r, g, b)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function clamp_byte(v)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return math.floor(v + 0.5)
end

local function lum_byte(r, g, b)
  return clamp_byte(luminance(r, g, b))
end

local function downsample(img, gw, gh)
  local rw, rh, data = img.width, img.height, img.data
  local R, G, B = {}, {}, {}
  for oy = 0, gh - 1 do
    local sy0 = math.floor(oy * rh / gh)
    local sy1 = math.max(sy0 + 1, math.floor((oy + 1) * rh / gh))
    local stepy = math.max(1, math.floor((sy1 - sy0) / 8))
    for ox = 0, gw - 1 do
      local sx0 = math.floor(ox * rw / gw)
      local sx1 = math.max(sx0 + 1, math.floor((ox + 1) * rw / gw))
      local stepx = math.max(1, math.floor((sx1 - sx0) / 8))
      local rs, gs, bs, cnt = 0, 0, 0, 0
      local y = sy0
      while y < sy1 do
        local rowbase = y * rw
        local x = sx0
        while x < sx1 do
          local i = (rowbase + x) * 3 + 1
          local r, g, b = data:byte(i, i + 2)
          rs = rs + r
          gs = gs + g
          bs = bs + b
          cnt = cnt + 1
          x = x + stepx
        end
        y = y + stepy
      end
      local idx = oy * gw + ox + 1
      R[idx] = math.floor(rs / cnt + 0.5)
      G[idx] = math.floor(gs / cnt + 0.5)
      B[idx] = math.floor(bs / cnt + 0.5)
    end
  end
  return R, G, B
end

local function box_blur(S, gw, gh)
  local out = {}
  for y = 0, gh - 1 do
    for x = 0, gw - 1 do
      local sum, n = 0, 0
      for dy = -1, 1 do
        local yy = y + dy
        if yy >= 0 and yy < gh then
          for dx = -1, 1 do
            local xx = x + dx
            if xx >= 0 and xx < gw then
              sum = sum + S[yy * gw + xx + 1]
              n = n + 1
            end
          end
        end
      end
      out[y * gw + x + 1] = sum / n
    end
  end
  return out
end

local function sharpen(R, G, B, gw, gh, amount)
  local br = box_blur(R, gw, gh)
  local bg = box_blur(G, gw, gh)
  local bb = box_blur(B, gw, gh)
  local n = gw * gh
  for i = 1, n do
    R[i] = clamp_byte(R[i] + amount * (R[i] - br[i]))
    G[i] = clamp_byte(G[i] + amount * (G[i] - bg[i]))
    B[i] = clamp_byte(B[i] + amount * (B[i] - bb[i]))
  end
end

local function histogram(R, G, B, n)
  local hist = {}
  for v = 0, 255 do hist[v] = 0 end
  for i = 1, n do
    local l = lum_byte(R[i], G[i], B[i])
    hist[l] = hist[l] + 1
  end
  return hist
end

local function stretch_lut(hist, n, clip)
  local lo_edge = n * clip
  local hi_edge = n * (1 - clip)
  local cum, lo, hi = 0, 0, 255
  local found_lo = false
  for v = 0, 255 do
    cum = cum + hist[v]
    if not found_lo and cum > lo_edge then
      lo = v
      found_lo = true
    end
    if found_lo and cum >= hi_edge then
      hi = v
      break
    end
  end
  if hi - lo < 8 then
    local ident = {}
    for v = 0, 255 do ident[v] = v end
    return ident
  end
  local lut = {}
  local span = hi - lo
  for v = 0, 255 do
    local t = math.floor((v - lo) * 255 / span + 0.5)
    if t < 0 then t = 0 elseif t > 255 then t = 255 end
    lut[v] = t
  end
  return lut
end

local function equalize_lut(hist, n)
  local lut = {}
  local cdf, cdf_min = 0, 0
  local first = true
  for v = 0, 255 do
    if first and hist[v] > 0 then
      cdf_min = hist[v]
      first = false
    end
    cdf = cdf + hist[v]
    local val = math.floor((cdf - cdf_min) * 255 / math.max(1, n - cdf_min) + 0.5)
    if val < 0 then val = 0 elseif val > 255 then val = 255 end
    lut[v] = val
  end
  return lut
end

local function apply_contrast(R, G, B, n, mode)
  if mode ~= "stretch" and mode ~= "equalize" then
    return
  end
  local hist = histogram(R, G, B, n)
  local lut
  if mode == "equalize" then
    lut = equalize_lut(hist, n)
  else
    lut = stretch_lut(hist, n, 0.02)
  end
  for i = 1, n do
    local l0 = lum_byte(R[i], G[i], B[i])
    local l1 = lut[l0]
    if l1 ~= l0 then
      local f = (l1 + 4) / (l0 + 4)
      if f > 3 then f = 3 elseif f < 0.1 then f = 0.1 end
      R[i] = clamp_byte(R[i] * f)
      G[i] = clamp_byte(G[i] * f)
      B[i] = clamp_byte(B[i] * f)
    end
  end
end

local function otsu(hist, n)
  local sum = 0
  for v = 0, 255 do
    sum = sum + v * hist[v]
  end
  local sum_b, w_b, max_var, thr = 0, 0, -1, 127
  for t = 0, 255 do
    w_b = w_b + hist[t]
    local w_f = n - w_b
    if w_b > 0 and w_f > 0 then
      sum_b = sum_b + t * hist[t]
      local m_b = sum_b / w_b
      local m_f = (sum - sum_b) / w_f
      local var = w_b * w_f * (m_b - m_f) * (m_b - m_f)
      if var > max_var then
        max_var = var
        thr = t
      end
    end
    if w_f == 0 then
      break
    end
  end
  return thr
end

local function braille_bit(k, j)
  if j == 3 then
    return 6 + k
  end
  return k * 3 + j
end

function M.render(img, opts)
  opts = opts or {}
  local mode = opts.mode
  if mode ~= "halfblocks" and mode ~= "braille" then
    mode = "chars"
  end
  local cols = math.floor(tonumber(opts.width) or 160)
  if cols < 10 then cols = 10 end
  if cols > MAX_COLS then cols = MAX_COLS end
  local invert = opts.invert and true or false
  local color = opts.color and true or false
  if mode == "halfblocks" then
    color = true
  end
  local contrast = opts.contrast or "stretch"
  if contrast ~= "off" and contrast ~= "stretch" and contrast ~= "equalize" then
    contrast = "stretch"
  end
  local do_sharpen = opts.sharpen ~= false
  local aspect = tonumber(opts.aspect) or 0.6
  if aspect < 0.3 then aspect = 0.3 end
  if aspect > 1.2 then aspect = 1.2 end
  local rw, rh = img.width, img.height
  local rows = math.floor(cols * (rh / rw) * aspect + 0.5)
  if rows < 1 then rows = 1 end
  if rows > MAX_ROWS then rows = MAX_ROWS end

  local gw, gh
  if mode == "halfblocks" then
    gw, gh = cols, rows * 2
  elseif mode == "braille" then
    gw, gh = cols * 2, rows * 4
  else
    gw, gh = cols, rows
  end
  if gw * gh > MAX_GRID then
    local scale = math.sqrt(MAX_GRID / (gw * gh))
    rows = math.max(1, math.floor(rows * scale))
    if mode == "halfblocks" then
      gw, gh = cols, rows * 2
    elseif mode == "braille" then
      gw, gh = cols * 2, rows * 4
    else
      gw, gh = cols, rows
    end
  end

  local R, G, B = downsample(img, gw, gh)
  if do_sharpen then
    sharpen(R, G, B, gw, gh, 0.8)
  end
  apply_contrast(R, G, B, gw * gh, contrast)

  local lines = {}
  local html_lines = color and {} or nil

  if mode == "halfblocks" then
    for oy = 0, rows - 1 do
      local top_i = oy * 2 * gw
      local bot_i = (oy * 2 + 1) * gw
      local parts = {}
      for ox = 0, cols - 1 do
        local tr, tg, tb = R[top_i + ox + 1], G[top_i + ox + 1], B[top_i + ox + 1]
        local br, bg, bb = R[bot_i + ox + 1], G[bot_i + ox + 1], B[bot_i + ox + 1]
        if invert then
          tr, tg, tb = 255 - tr, 255 - tg, 255 - tb
          br, bg, bb = 255 - br, 255 - bg, 255 - bb
        end
        parts[ox + 1] = string.format(
          '<span style="color:#%02x%02x%02x;background:#%02x%02x%02x">▀</span>',
          tr, tg, tb, br, bg, bb)
      end
      html_lines[oy + 1] = table.concat(parts)
      lines[oy + 1] = ""
    end
  elseif mode == "braille" then
    local hist = histogram(R, G, B, gw * gh)
    local thr = otsu(hist, gw * gh)
    for oy = 0, rows - 1 do
      local parts = {}
      local hparts = html_lines and {} or nil
      for ox = 0, cols - 1 do
        local bits, sr, sg, sb, nlit = 0, 0, 0, 0, 0
        for j = 0, 3 do
          local y = oy * 4 + j
          for k = 0, 1 do
            local x = ox * 2 + k
            local i = y * gw + x + 1
            local l = lum_byte(R[i], G[i], B[i])
            local lit
            if invert then
              lit = l <= thr
            else
              lit = l > thr
            end
            if lit then
              bits = bits + (1 << braille_bit(k, j))
              sr = sr + R[i]
              sg = sg + G[i]
              sb = sb + B[i]
              nlit = nlit + 1
            end
          end
        end
        local ch = utf8.char(0x2800 + bits)
        parts[ox + 1] = ch
        if hparts and nlit > 0 then
          local r = clamp_byte(sr / nlit)
          local g = clamp_byte(sg / nlit)
          local b = clamp_byte(sb / nlit)
          hparts[#hparts + 1] = string.format(
            '<span style="color:#%02x%02x%02x">%s</span>', r, g, b, ch)
        elseif hparts then
          hparts[#hparts + 1] = ch
        end
      end
      lines[oy + 1] = table.concat(parts)
      if html_lines then
        html_lines[oy + 1] = table.concat(hparts)
      end
    end
  else
    local ramp = M.ramps[opts.ramp] or M.ramps.standard
    local chars = ramp_chars(ramp)
    local n = #chars
    for oy = 0, rows - 1 do
      local parts, hparts = {}, nil
      if html_lines then hparts = {} end
      for ox = 0, cols - 1 do
        local i = oy * gw + ox + 1
        local r, g, b = R[i], G[i], B[i]
        local l = luminance(r, g, b)
        local idx = math.floor(l / 256 * n) + 1
        if idx > n then idx = n end
        if invert then
          idx = n - idx + 1
        end
        local ch = chars[idx]
        parts[ox + 1] = ch
        if hparts then
          hparts[#hparts + 1] = string.format(
            '<span style="color:#%02x%02x%02x">%s</span>',
            clamp_byte(r), clamp_byte(g), clamp_byte(b), html_escape(ch))
        end
      end
      lines[oy + 1] = table.concat(parts)
      if html_lines then
        html_lines[oy + 1] = table.concat(hparts)
      end
    end
  end

  return {
    plain = table.concat(lines, "\n"),
    html = html_lines and table.concat(html_lines, "\n") or nil,
    cols = cols,
    rows = rows,
    mode = mode,
    contrast = contrast,
  }
end

return M
