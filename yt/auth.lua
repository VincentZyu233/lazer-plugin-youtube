local auth = {}

--- 32 位循环左移
local function rol(val, n)
  return (((val << n) | (val >> (32 - n))) & 0xFFFFFFFF)
end

--- 纯 Lua 实现的标准 SHA-1 哈希算法 (适用于 Lua 5.3+ 及 Lazer 沙箱)
function auth.sha1(msg)
  if not msg then return "" end
  msg = tostring(msg)

  local bytes = {}
  for i = 1, #msg do
    bytes[i] = string.byte(msg, i)
  end

  local len = #bytes
  local bit_len = len * 8

  -- 追加填充位 0x80
  bytes[#bytes + 1] = 0x80

  -- 填充 0 使得长度在模 64 下余 56 字节
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end

  -- 追加 64 位大端格式的原始长度
  for i = 7, 0, -1 do
    bytes[#bytes + 1] = ((bit_len >> (i * 8)) & 0xFF)
  end

  local h0 = 0x67452301
  local h1 = 0xEFCDAB89
  local h2 = 0x98BADCFE
  local h3 = 0x10325476
  local h4 = 0xC3D2E1F0

  local num_chunks = #bytes // 64
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
        k = 0x5A827999
      elseif i <= 39 then
        f = b ~ c ~ d
        k = 0x6ED9EBA1
      elseif i <= 59 then
        f = (b & c) | (b & d) | (c & d)
        k = 0x8F1BBCDC
      else
        f = b ~ c ~ d
        k = 0xCA62C1D6
      end

      local temp = (rol(a, 5) + f + e + k + w[i]) & 0xFFFFFFFF
      e = d
      d = c
      c = rol(b, 30)
      b = a
      a = temp
    end

    h0 = (h0 + a) & 0xFFFFFFFF
    h1 = (h1 + b) & 0xFFFFFFFF
    h2 = (h2 + c) & 0xFFFFFFFF
    h3 = (h3 + d) & 0xFFFFFFFF
    h4 = (h4 + e) & 0xFFFFFFFF
  end

  return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

--- 从 Cookie 字符串中提取 SAPISID 凭据
function auth.get_sapisid(cookie_str)
  if not cookie_str or type(cookie_str) ~= "string" or #cookie_str == 0 then
    return nil
  end

  -- 优先使用 host 原生 cookie 解析
  if host and type(host.cookie_field) == "function" then
    local s = host.cookie_field(cookie_str, "SAPISID")
    if s and #s > 0 then return s end
    s = host.cookie_field(cookie_str, "__Secure-3PAPISID")
    if s and #s > 0 then return s end
    s = host.cookie_field(cookie_str, "__Secure-1PAPISID")
    if s and #s > 0 then return s end
  end

  -- 正则模式匹配回退
  local val = cookie_str:match("[;%s]?SAPISID=([^;%s\r\n]+)")
  if val and #val > 0 then return val end

  val = cookie_str:match("[;%s]?__Secure%-3PAPISID=([^;%s\r\n]+)")
  if val and #val > 0 then return val end

  val = cookie_str:match("[;%s]?__Secure%-1PAPISID=([^;%s\r\n]+)")
  if val and #val > 0 then return val end

  return nil
end

--- 生成 YouTube Innertube API 认证所必需的 Authorization 标头
-- 格式: "SAPISIDHASH <timestamp>_<sha1(timestamp .. ' ' .. sapisid .. ' ' .. origin)>"
function auth.generate_authorization(cookie_str, origin)
  local sapisid = auth.get_sapisid(cookie_str)
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
    ts = 1794503614
  end

  local to_hash = tostring(ts) .. " " .. sapisid .. " " .. host_origin
  local hash = auth.sha1(to_hash)

  return "SAPISIDHASH " .. tostring(ts) .. "_" .. hash
end

return auth
