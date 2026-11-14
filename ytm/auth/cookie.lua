local auth_cookie = {}

--- 32 位循环左移
local function rol(val, n)
  return (((val << n) | (val >> (32 - n))) & 4294967295)
end

--- 纯 Lua 实现的标准 SHA-1 哈希算法
-- 彻底避开 0x 十六进制字面量与字符串 # 运算符，兼容 Dart lua_dardo_plus
function auth_cookie.sha1(msg)
  if not msg then return "" end
  msg = tostring(msg)

  local msg_len = string.len(msg)
  local bytes = {}
  for i = 1, msg_len do
    bytes[i] = string.byte(msg, i)
  end

  local len = #bytes
  local bit_len = len * 8

  bytes[#bytes + 1] = 128
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end

  for i = 7, 0, -1 do
    bytes[#bytes + 1] = ((bit_len >> (i * 8)) & 255)
  end

  local h0 = 1732584193
  local h1 = 4023233417
  local h2 = 2562383102
  local h3 = 271733878
  local h4 = 3285377520

  local num_chunks = math.floor(#bytes / 64)
  for chunk = 0, num_chunks - 1 do
    local offset = chunk * 64
    local w = {}
    for i = 0, 15 do
      local idx = offset + i * 4
      w[i] = (bytes[idx + 1] << 24) | (bytes[idx + 2] << 16) | (bytes[idx + 3] << 8) | bytes[idx + 4]
    end

    for i = 16, 79 do
      w[i] = rol(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4

    for i = 0, 79 do
      local f, k
      if i <= 19 then
        f = (b & c) | ((~b) & d)
        k = 1518500249
      elseif i <= 39 then
        f = b ~ c ~ d
        k = 1859775393
      elseif i <= 59 then
        f = (b & c) | (b & d) | (c & d)
        k = 2400959708
      else
        f = b ~ c ~ d
        k = 3395469782
      end

      local temp = (rol(a, 5) + f + e + k + w[i]) & 4294967295
      e = d
      d = c
      c = rol(b, 30)
      b = a
      a = temp
    end

    h0 = (h0 + a) & 4294967295
    h1 = (h1 + b) & 4294967295
    h2 = (h2 + c) & 4294967295
    h3 = (h3 + d) & 4294967295
    h4 = (h4 + e) & 4294967295
  end

  return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

--- 智能清洗并去重 Cookie 字符串 (重复键保留最新值，过滤空段与空格)
function auth_cookie.clean_cookie(cookie_str)
  if not cookie_str or type(cookie_str) ~= "string" or string.len(cookie_str) == 0 then
    return ""
  end

  local keys = {}
  local map = {}

  for part in string.gmatch(cookie_str, "[^;]+") do
    part = string.gsub(part, "^%s+", "")
    part = string.gsub(part, "%s+$", "")
    if string.len(part) > 0 then
      local eq_pos = string.find(part, "=", 1, true)
      if eq_pos and eq_pos > 1 then
        local k = string.sub(part, 1, eq_pos - 1)
        local v = string.sub(part, eq_pos + 1)
        k = string.gsub(k, "^%s+", "")
        k = string.gsub(k, "%s+$", "")
        v = string.gsub(v, "^%s+", "")
        v = string.gsub(v, "%s+$", "")
        if not map[k] then
          table.insert(keys, k)
        end
        map[k] = v
      end
    end
  end

  local res = {}
  for _, k in ipairs(keys) do
    table.insert(res, k .. "=" .. map[k])
  end

  return table.concat(res, "; ")
end

--- 从 Cookie 字符串中提取 SAPISID 凭据
function auth_cookie.get_sapisid(cookie_str)
  if not cookie_str or type(cookie_str) ~= "string" or string.len(cookie_str) == 0 then
    return nil
  end

  local cleaned = auth_cookie.clean_cookie(cookie_str)

  if host and type(host.cookie_field) == "function" then
    local s = host.cookie_field(cleaned, "SAPISID")
    if s and string.len(s) > 0 then return s end
    s = host.cookie_field(cleaned, "__Secure-3PAPISID")
    if s and string.len(s) > 0 then return s end
    s = host.cookie_field(cleaned, "__Secure-1PAPISID")
    if s and string.len(s) > 0 then return s end
  end

  local val = cleaned:match("[;%s]?SAPISID=([^;%s\r\n]+)")
  if val and string.len(val) > 0 then return val end

  val = cleaned:match("[;%s]?__Secure%-3PAPISID=([^;%s\r\n]+)")
  if val and string.len(val) > 0 then return val end

  val = cleaned:match("[;%s]?__Secure%-1PAPISID=([^;%s\r\n]+)")
  if val and string.len(val) > 0 then return val end

  return nil
end

--- 生成 YouTube Innertube API 认证所必需的 Authorization 标头
function auth_cookie.generate_authorization(cookie_str, origin)
  local sapisid = auth_cookie.get_sapisid(cookie_str)
  if not sapisid then
    return nil
  end

  local host_origin = origin or "https://music.youtube.com"

  local ts = nil
  if host and type(host.now) == "function" then
    local ok, ms = pcall(host.now)
    if ok and type(ms) == "number" then
      ts = math.floor(ms / 1000)
    end
  end

  if not ts and type(os) == "table" and type(os.time) == "function" then
    local ok, s = pcall(os.time)
    if ok and type(s) == "number" then
      ts = s
    end
  end

  if not ts then
    ts = 1794503044
  end

  local to_hash = tostring(ts) .. " " .. sapisid .. " " .. host_origin
  local hash = auth_cookie.sha1(to_hash)

  return "SAPISIDHASH " .. tostring(ts) .. "_" .. hash
end

return auth_cookie
