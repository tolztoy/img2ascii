local socket = require "socket"
local multipart = require "src.multipart"
local image = require "src.image"
local ascii = require "src.ascii"

local ROOT = arg[0]:match("^(.*)/[^/]+$") or "."
local PORT = tonumber(arg[1]) or tonumber(os.getenv("PORT") or "") or 8080
local MAX_BODY = 8 * 1024 * 1024
local DJPEG = ROOT .. "/local/usr/bin/djpeg"
do
  local probe = io.open(DJPEG, "r")
  if probe then
    probe:close()
  else
    DJPEG = "djpeg"
  end
end

local STYLE = [[
<style>
  * { box-sizing: border-box; }
  body { font-family: system-ui, sans-serif; background: #101418; color: #d6dde4;
         max-width: 960px; margin: 2rem auto; padding: 0 1rem; }
  h1 { font-weight: 600; font-size: 1.5rem; }
  h1 span { color: #2f81f7; }
  form { background: #1a2027; padding: 1rem 1.2rem; border-radius: 10px;
         display: flex; flex-wrap: wrap; gap: .9rem; align-items: center; }
  label { font-size: .9rem; color: #9fb0bf; display: flex; gap: .4rem; align-items: center; }
  input[type=number] { width: 4.5rem; background: #0d1116; color: #d6dde4;
                      border: 1px solid #2d3640; border-radius: 6px; padding: .3rem .4rem; }
  select { background: #0d1116; color: #d6dde4; border: 1px solid #2d3640;
           border-radius: 6px; padding: .3rem .4rem; }
  button { background: #2f81f7; color: #fff; border: 0; padding: .55rem 1.3rem;
           border-radius: 7px; font-size: 1rem; cursor: pointer; }
  button:hover { background: #4593f8; }
  .meta { color: #8b98a5; font-size: .85rem; margin: 1.2rem 0 .6rem; }
  .art { background: #0a0d10; padding: 1rem 1.2rem; border-radius: 10px; overflow-x: auto; }
  pre { font-family: 'DejaVu Sans Mono', 'Courier New', monospace; font-size: 13px;
        line-height: 1; margin: 0; color: #e8edf2; }
  a { color: #6cb6ff; }
  .err { background: #2a1517; border: 1px solid #6e2a2f; color: #f0b6b9;
         padding: .8rem 1.1rem; border-radius: 10px; }
  .note { margin-top: 1.4rem; font-size: .8rem; color: #5d6a76; }
</style>
]]

local FORM_PAGE = [[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>image &rarr; ascii</title>
]] .. STYLE .. [[
</head>
<body>
<h1>image <span>&rarr;</span> ascii</h1>
<form method="post" action="/" enctype="multipart/form-data">
  <input type="file" name="image" accept="image/png,image/jpeg,image/bmp,.ppm,.pgm" required>
  <label>mode
    <select name="mode">
      <option value="chars" selected>chars</option>
      <option value="halfblocks">half-blocks (2&times; detail)</option>
      <option value="braille">braille (8&times; detail)</option>
    </select>
  </label>
  <label>width <input type="number" name="width" value="160" min="10" max="400"></label>
  <label data-chars>charset
    <select name="charset">
      <option value="standard">standard</option>
      <option value="detailed">detailed</option>
      <option value="blocks">blocks</option>
      <option value="solid">solid</option>
    </select>
  </label>
  <label>contrast
    <select name="contrast">
      <option value="stretch" selected>stretch</option>
      <option value="equalize">equalize</option>
      <option value="off">off</option>
    </select>
  </label>
  <label>aspect <input type="number" name="aspect" value="0.6" min="0.3" max="1.2" step="0.05" title="cell width / height in the browser (0.6 matches typical monospace fonts)"></label>
  <label><input type="checkbox" name="sharpen" value="1" checked> sharpen</label>
  <label><input type="checkbox" name="invert" value="1"> invert</label>
  <label data-color><input type="checkbox" name="color" value="1"> color</label>
  <button type="submit">convert</button>
</form>
<div class="note">Supported formats: PNG, JPEG, BMP, PPM, PGM &mdash; decoded locally, nothing leaves this machine.<br>
Most recognizable: <strong>half-blocks</strong> or <strong>braille</strong>. Braille needs a font with dot glyphs (if it misaligns on your system, use half-blocks).</div>
<script>
(function () {
  var form = document.querySelector('form');
  var modeSel = form.querySelector('[name=mode]');
  function sync() {
    var m = modeSel.value;
    form.querySelectorAll('[data-chars]').forEach(function (el) {
      el.style.display = m === 'chars' ? '' : 'none';
    });
    form.querySelectorAll('[data-color]').forEach(function (el) {
      el.style.display = m === 'halfblocks' ? 'none' : '';
    });
  }
  modeSel.addEventListener('change', sync);
  sync();
})();
</script>
</body>
</html>
]]

local function html_escape(s)
  return (s:gsub("[&<>\"']", {
    ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
    ["\""] = "&quot;", ["'"] = "&#39;",
  }))
end

local function error_page(title, detail)
  return [[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>]] .. html_escape(title) .. [[</title>
]] .. STYLE .. [[
</head>
<body>
<h1>image <span>&rarr;</span> ascii</h1>
<div class="err"><strong>]] .. html_escape(title) .. [[</strong><br>]] .. html_escape(detail or "") .. [[</div>
<p><a href="/">&larr; try another image</a></p>
</body>
</html>
]]
end

local MODE_LABELS = {
  chars = "chars", halfblocks = "half-blocks", braille = "braille",
}

local function result_page(filename, img, art)
  local body = art.html or html_escape(art.plain)
  local name = html_escape(filename or "uploaded image")
  local bits = { MODE_LABELS[art.mode] or art.mode }
  if art.contrast and art.contrast ~= "off" then
    bits[#bits + 1] = art.contrast
  end
  if art.html and art.mode ~= "halfblocks" then
    bits[#bits + 1] = "color"
  end
  return string.format([[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>%s &rarr; ascii</title>
]] .. STYLE .. [[
</head>
<body>
<h1>image <span>&rarr;</span> ascii</h1>
<div class="meta">%s &middot; %dx%d px &rarr; %dx%d cells &middot; %s</div>
<div class="art"><pre>%s</pre></div>
<p><a href="/">&larr; try another image</a></p>
</body>
</html>
]], name, name, img.width, img.height, art.cols, art.rows,
    table.concat(bits, " &middot; "), body)
end

local STATUS_TEXT = {
  [200] = "OK", [400] = "Bad Request", [404] = "Not Found",
  [405] = "Method Not Allowed", [408] = "Request Timeout",
  [413] = "Payload Too Large", [500] = "Internal Server Error",
}

local function respond(client, status, ctype, body)
  local header = string.format(
    "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
    status, STATUS_TEXT[status] or "OK", ctype, #body)
  local payload = header .. body
  local i = 1
  while i <= #payload do
    local sent, err, last = client:send(payload, i)
    if sent then
      i = sent + 1
    elseif err == "timeout" then
      socket.sleep(0.05)
      i = last and (last + 1) or i
    else
      break
    end
  end
end

local function parse_headers(lines)
  local headers = {}
  local request_line = lines[1] or ""
  for i = 2, #lines do
    local k, v = lines[i]:match("^([%w%-]+):%s*(.*)$")
    if k then
      headers[k:lower()] = v
    end
  end
  local method, path = request_line:match("^(%u+)%s+(%S+)%s+HTTP/1%.1")
  return method, path, headers
end

local function read_request(client)
  local lines = {}
  while true do
    local line, err, partial = client:receive("*l")
    if not line then
      line = partial
      if not line or err == "timeout" then
        return nil, err == "timeout" and 408 or 400
      end
      lines[#lines + 1] = (line:gsub("\r$", ""))
      return nil, 400
    end
    line = line:gsub("\r$", "")
    if line == "" then
      break
    end
    lines[#lines + 1] = line
    if #lines > 100 then
      return nil, 400
    end
  end
  local method, path, headers = parse_headers(lines)
  if not method then
    return nil, 400
  end
  local body = ""
  local clen = tonumber(headers["content-length"] or "")
  if clen and clen > 0 then
    if clen > MAX_BODY then
      return method, path, headers, nil, 413
    end
    local data, err, partial = client:receive(clen)
    if data then
      body = data
    elseif partial and err == "closed" then
      return nil, 400
    else
      return nil, 408
    end
  end
  return method, path, headers, body
end

local function handle_post(client, headers, body)
  local ct = headers["content-type"] or ""
  if not ct:lower():find("multipart/form%-data", 1) then
    respond(client, 400, "text/html; charset=utf-8",
      error_page("Bad request", "expected a multipart form upload"))
    return
  end
  local parsed, perr = multipart.parse(body, ct)
  if not parsed then
    respond(client, 400, "text/html; charset=utf-8",
      error_page("Bad request", perr or "could not parse upload"))
    return
  end
  local file = parsed.files.image
  if not file or #file.content == 0 then
    respond(client, 400, "text/html; charset=utf-8",
      error_page("No image", "choose an image file before submitting"))
    return
  end
  local img, err = image.decode(file.content, { djpeg = DJPEG })
  if not img then
    respond(client, 400, "text/html; charset=utf-8",
      error_page("Could not read image", err or "unknown decode error"))
    return
  end
  local mode = parsed.fields.mode
  if mode ~= "halfblocks" and mode ~= "braille" then
    mode = "chars"
  end
  local color = parsed.fields.color == "1" or mode == "halfblocks"
  local art = ascii.render(img, {
    width = parsed.fields.width,
    ramp = parsed.fields.charset,
    invert = parsed.fields.invert == "1",
    color = color,
    mode = mode,
    contrast = parsed.fields.contrast,
    sharpen = parsed.fields.sharpen == "1",
    aspect = parsed.fields.aspect,
  })
  respond(client, 200, "text/html; charset=utf-8",
    result_page(file.filename, img, art))
end

local function handle(client)
  client:settimeout(10)
  local method, path, headers, body, early = read_request(client)
  if early then
    if early == 413 then
      respond(client, 413, "text/html; charset=utf-8",
        error_page("Upload too large", "limit is " .. (MAX_BODY // 1024) .. " KB"))
    else
      respond(client, early, "text/html; charset=utf-8",
        error_page("Request error", "the request could not be read"))
    end
    return
  end
  if not method then
    respond(client, path or 400, "text/html; charset=utf-8",
      error_page("Request error", "malformed request"))
    return
  end
  if method == "GET" and (path == "/" or path == "/index.html") then
    respond(client, 200, "text/html; charset=utf-8", FORM_PAGE)
  elseif method == "POST" and (path == "/" or path == "/upload") then
    local ok, perr = pcall(handle_post, client, headers, body)
    if not ok then
      respond(client, 500, "text/html; charset=utf-8",
        error_page("Server error", tostring(perr)))
    end
  elseif method == "GET" and path == "/favicon.ico" then
    respond(client, 204, "image/x-icon", "")
  else
    respond(client, 404, "text/html; charset=utf-8",
      error_page("Not found", "no such page: " .. html_escape(path or "?")))
  end
end

local server = assert(socket.bind("0.0.0.0", PORT))
server:settimeout(nil)
local _, actual = server:getsockname()
print(string.format("image -> ascii running at http://localhost:%d/  (Ctrl+C to stop)", actual))
while true do
  local client, cerr = server:accept()
  if client then
    local ok, herr = pcall(handle, client)
    if not ok then
      pcall(respond, client, 500, "text/html; charset=utf-8",
        error_page("Server error", tostring(herr)))
    end
    client:close()
  elseif cerr ~= "timeout" then
    socket.sleep(0.1)
  end
end
