local M = {}

function M.parse(body, content_type)
  if type(body) ~= "string" or type(content_type) ~= "string" then
    return nil, "missing body or content type"
  end
  local boundary = content_type:match("[Bb]oundary%*?=%s*\"?([^\";]+)\"?")
  if not boundary then
    return nil, "missing multipart boundary"
  end
  local delim = "--" .. boundary
  local fields = {}
  local files = {}
  local start = body:find(delim, 1, true)
  if not start then
    return nil, "malformed multipart body"
  end
  local pos = start + #delim
  while true do
    local c = body:sub(pos, pos + 1)
    if c == "--" then
      break
    end
    if c ~= "\r\n" then
      return nil, "malformed multipart delimiter"
    end
    local next_delim = body:find("\r\n" .. delim, pos, true)
    if not next_delim then
      return nil, "unterminated multipart section"
    end
    local part = body:sub(pos + 2, next_delim - 1)
    local sep = part:find("\r\n\r\n", 1, true)
    if sep then
      local heads = part:sub(1, sep - 1)
      local content = part:sub(sep + 4)
      local disp = heads:match("[Dd]isposition:%s*form%-data;([^\r\n]*)")
      local name = disp and disp:match("name=\"([^\"]*)\"")
      local filename = disp and disp:match("filename=\"([^\"]*)\"")
      local ctype = heads:match("[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)")
      if name then
        if filename and filename ~= "" then
          files[name] = { filename = filename, content = content, ctype = ctype }
        elseif not filename then
          fields[name] = content
        end
      end
    end
    pos = next_delim + #delim + 2
  end
  return { fields = fields, files = files }
end

return M
