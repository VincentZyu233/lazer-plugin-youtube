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

--- 按字节边界裁剪首尾空白
-- 宿主 lua_dardo_plus 的 string.match 直接调用 Dart RegExp，Lua 的 %s 字符类会
-- 变成字面量，`^%s*(.-)%s*$` 永远匹配失败。因此这里只使用 string.byte/string.sub。
function auth_cookie.trim(value)
  if value == nil then return "" end
  local str = tostring(value)
  local first = 1
  local last = string.len(str)
  while first <= last and string.byte(str, first) <= 32 do first = first + 1 end
  while last >= first and string.byte(str, last) <= 32 do last = last - 1 end
  if last < first then return "" end
  return string.sub(str, first, last)
end

--- 从 Cookie 串中按字段名取值的纯字节扫描实现
-- 作为 host.cookie_field 缺失时的兜底，同样不依赖任何 Lua 模式字符类。
local function cookie_field_fallback(cookie_str, name)
  local needle = name .. "="
  local total = string.len(cookie_str)
  local search_from = 1
  while true do
    local start = string.find(cookie_str, needle, search_from, true)
    if not start then return nil end

    -- 前一个字符必须是字段分隔符，避免命中 `XXSAPISID=` 这类后缀
    local boundary = true
    if start > 1 then
      local prev = string.byte(cookie_str, start - 1)
      if prev ~= 59 and prev ~= 32 and prev ~= 9 and prev ~= 10 and prev ~= 13 then
        boundary = false
      end
    end

    if boundary then
      local value_start = start + string.len(needle)
      local index = value_start
      while index <= total do
        local b = string.byte(cookie_str, index)
        if b == 59 or b == 32 or b == 9 or b == 10 or b == 13 then break end
        index = index + 1
      end
      if index > value_start then
        return string.sub(cookie_str, value_start, index - 1)
      end
    end

    search_from = start + 1
  end
end

--- 从 Cookie 字符串中提取 SAPISID 凭据 (对齐 0.1.15 规范: 原汁原味提取，绝不进行字符串拆解破坏签名)
function auth_cookie.get_sapisid(cookie_str)
  if not cookie_str or type(cookie_str) ~= "string" or string.len(cookie_str) == 0 then
    return nil
  end

  if host and type(host.cookie_field) == "function" then
    local s = host.cookie_field(cookie_str, "SAPISID")
    if s and string.len(s) > 0 then return s end
    s = host.cookie_field(cookie_str, "__Secure-3PAPISID")
    if s and string.len(s) > 0 then return s end
    s = host.cookie_field(cookie_str, "__Secure-1PAPISID")
    if s and string.len(s) > 0 then return s end
  end

  local val = cookie_field_fallback(cookie_str, "SAPISID")
  if val and string.len(val) > 0 then return val end

  val = cookie_field_fallback(cookie_str, "__Secure-3PAPISID")
  if val and string.len(val) > 0 then return val end

  val = cookie_field_fallback(cookie_str, "__Secure-1PAPISID")
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
