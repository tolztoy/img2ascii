local image = require "src.image"
local ascii = require "src.ascii"

local passed, failed = 0, 0

local function check(cond, name)
  if cond then
    passed = passed + 1
    print("ok   " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name)
  end
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a")
  f:close()
  return d
end

local DJPEG = "./local/usr/bin/djpeg"
local IMG = "tests/img/"

local function px(img, x, y)
  local i = (y * img.width + x) * 3 + 1
  local r, g, b = img.data:byte(i, i + 2)
  return r, g, b
end

local g = image.decode(read(IMG .. "gradient.png"))
check(g and g.width == 160 and g.height == 120, "gradient.png dims")
check(g and #g.data == 160 * 120 * 3, "gradient.png rgb size")
local r, gg, b = px(g, 0, 0)
check(r == 0 and gg == 0 and b == 128, "gradient.png px(0,0)")
r, gg, b = px(g, 159, 119)
check(r == 255 and gg == 255 and b == 128, "gradient.png px(159,119)")

local c1 = image.decode(read(IMG .. "circle.png"))
local c2 = image.decode(read(IMG .. "circle_interlaced.png"))
check(c1 and c2 and c1.width == 100 and c1.height == 100, "circle dims")
check(c1 and c2 and c1.data == c2.data, "interlaced decodes identical to progressive")

local rgba = image.decode(read(IMG .. "gradient_rgba.png"))
check(rgba and rgba.width == 160 and rgba.height == 120, "rgba dims")
r, gg, b = px(rgba, 159, 0)
check(r == 255 and gg == 0 and b == 128, "rgba strips alpha channel")

local gray = image.decode(read(IMG .. "gradient_gray.png"))
check(gray and gray.width == 160 and gray.height == 120, "gray dims")
r, gg, b = px(gray, 100, 0)
check(r == (100 * 255) // 159 and r == gg and gg == b, "gray expands to rgb")

local g16 = image.decode(read(IMG .. "gradient16.png"))
check(g16 and g16.width == 160 and #g16.data == 160 * 120 * 3, "16-bit dims")
r, gg, b = px(g16, 0, 0)
check(r == 0 and gg == 0 and b == 128, "16-bit high byte used")

local pal = image.decode(read(IMG .. "palette.png"))
check(pal and pal.width == 160 and pal.height == 120, "palette dims")
r, gg, b = px(pal, 0, 0)
check(r == 0 and gg == 255 and b == 0, "palette color lookup")

local jpg = image.decode(read(IMG .. "gradient.jpg"), { djpeg = DJPEG })
check(jpg and jpg.width == 160 and jpg.height == 120, "jpeg dims")
r, gg, b = px(jpg, 0, 0)
check(math.abs(r) < 40 and math.abs(gg) < 40 and math.abs(b - 128) < 40, "jpeg approx colors")

local bmp = image.decode(read(IMG .. "circle.bmp"))
check(bmp and bmp.width == 100 and bmp.height == 100, "bmp dims")
r, gg, b = px(bmp, 50, 50)
check(r == 255 and gg == 255 and b == 255, "bmp center white")
r, gg, b = px(bmp, 0, 0)
check(r == 0 and gg == 0 and b == 0, "bmp corner black")

local pgm = image.decode(read(IMG .. "gradient.pgm"))
check(pgm and pgm.width == 160 and pgm.height == 120, "pgm dims")
r, gg, b = px(pgm, 159, 0)
check(r == 255 and r == gg and gg == b, "pgm gray expands to rgb")

local ppm = image.decode(read(IMG .. "gradient.ppm"))
check(ppm and ppm.width == 160 and ppm.height == 120, "ppm dims")
r, gg, b = px(ppm, 159, 119)
check(r == 255 and gg == 255 and b == 128, "ppm px(159,119)")

local function distinct(s)
  local seen, n = {}, 0
  for _, cp in utf8.codes(s) do
    if not seen[cp] then
      seen[cp] = true
      n = n + 1
    end
  end
  return n
end

local function split(s)
  local out = {}
  for line in s:gmatch("[^\n]+") do
    out[#out + 1] = line
  end
  return out
end

local art = ascii.render(c1, { width = 40, ramp = "standard" })
check(art.cols == 40, "art cols")
check(art.rows == 24, "art rows (aspect 0.6)")
check(art.mode == "chars" and art.contrast == "stretch", "default mode/contrast")
local lines = split(art.plain)
check(#lines == 24, "line count")
check(#lines[1] == 40, "line byte width")
local center = lines[13]:sub(20, 20)
check(center == "@", "circle center renders dense (got '" .. center .. "')")
check(lines[1]:sub(1, 1) == " ", "circle corner renders space")

local inv = ascii.render(c1, { width = 40, ramp = "standard", invert = true })
local invlines = split(inv.plain)
check(invlines[1]:sub(1, 1) == "@", "invert flips corner to dense")
check(invlines[13]:sub(20, 20) == " ", "invert flips center to space")

local blk = ascii.render(c1, { width = 40, ramp = "blocks" })
local ok_utf8 = true
local blcount = 0
for _, line in ipairs(split(blk.plain)) do
  blcount = blcount + 1
  if utf8.len(line) ~= 40 then
    ok_utf8 = false
  end
end
check(ok_utf8 and blcount == 24, "utf8 block ramp cell counts")

local col = ascii.render(c1, { width = 40, ramp = "standard", color = true })
check(col.html and col.html:find('<span style="color:#ffffff">', 1, true), "color html white center")
check(col.html:find('<span style="color:#000000">', 1, true), "color html black corner")

local det = ascii.render(c1, { width = 20, ramp = "detailed" })
check(#det.plain > 20, "detailed ramp renders")

local w1 = ascii.render(c1, { width = 5 })
check(w1.cols == 10, "width clamped to min")
local w2 = ascii.render(c1, { width = 9999 })
check(w2.cols == 400, "width clamped to max")

local a1 = ascii.render(c1, { width = 40, aspect = 1 })
check(a1.rows == 40, "aspect 1.0 rows")

local ns = ascii.render(c1, { width = 40, sharpen = false })
check(ns.cols == 40, "sharpen=false renders")

local badmode = ascii.render(c1, { width = 40, mode = "bogus" })
check(badmode.mode == "chars", "unknown mode falls back to chars")

local lc = image.decode(read(IMG .. "lowcontrast.png"))
check(lc and lc.width == 64 and lc.height == 64, "lowcontrast dims")
local lc_off = ascii.render(lc, { width = 40, contrast = "off" })
local lc_str = ascii.render(lc, { width = 40, contrast = "stretch" })
local lc_eq = ascii.render(lc, { width = 40, contrast = "equalize" })
check(distinct(lc_str.plain) > distinct(lc_off.plain), "stretch increases tonal range")
check(distinct(lc_eq.plain) > distinct(lc_off.plain), "equalize increases tonal range")

local hb = ascii.render(c1, { width = 40, mode = "halfblocks" })
check(hb.mode == "halfblocks" and hb.cols == 40 and hb.rows == 24, "halfblocks dims")
check(hb.html ~= nil, "halfblocks always has html")
check(hb.html:find("color:#ffffff;background:#ffffff", 1, true), "halfblocks white center cell")
check(hb.html:find("color:#000000;background:#000000", 1, true), "halfblocks black corner cell")
local hb_spans = 0
for _ in hb.html:gmatch("<span") do hb_spans = hb_spans + 1 end
check(hb_spans == 40 * 24, "halfblocks span per cell")
check(hb.html:find("▀", 1, true), "halfblocks use upper half block")
local hb_lines = split(hb.html)
check(#hb_lines == 24, "halfblocks line count")

local br = ascii.render(c1, { width = 40, mode = "braille" })
check(br.mode == "braille" and br.cols == 40 and br.rows == 24, "braille dims")
local brl = split(br.plain)
check(#brl == 24, "braille line count")
local br_ok = true
for _, line in ipairs(brl) do
  if utf8.len(line) ~= 40 then
    br_ok = false
  end
  for _, cp in utf8.codes(line) do
    if cp < 0x2800 or cp > 0x28FF then
      br_ok = false
    end
  end
end
check(br_ok, "braille codepoints all in U+2800..U+28FF")
check(utf8.codepoint(brl[1], 1) == 0x2800, "braille dark corner is blank cell")
local mid_byte = utf8.offset(brl[13], 25)
local mid_cp = utf8.codepoint(brl[13], mid_byte)
check(mid_cp ~= 0x2800, "braille bright center is lit")

local bri = ascii.render(c1, { width = 40, mode = "braille", invert = true })
local bril = split(bri.plain)
check(utf8.codepoint(bril[1], 1) == 0x28FF, "braille invert lights dark corner fully")

local brc = ascii.render(c1, { width = 40, mode = "braille", color = true })
check(brc.html and brc.html:find('<span style="color:#ffffff">', 1, true),
  "braille color white center span")

local sm = image.decode(read(IMG .. "smiley.png"))
check(sm and sm.width == 300 and sm.height == 300, "smiley dims")
check(sm and #sm.data == 300 * 300 * 3, "smiley rgb size")
local luaimg = image.decode(read(IMG .. "lua.png"))
check(luaimg and luaimg.width == 360 and luaimg.height == 160, "lua.png dims")

local bad, err = image.decode("this is not an image")
check(bad == nil and err and err:find("unsupported"), "rejects garbage input")
local bad2 = image.decode(read(IMG .. "gradient.png"):sub(1, 100))
check(bad2 == nil, "rejects truncated png")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
