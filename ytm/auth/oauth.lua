local store = require("ytm.core.store")

local oauth = {}

-- 默认客户端凭据：使用广泛兼容的 YouTube on TV / Cobalt 凭据
-- 高级用户可通过 store.set("oauth_client_id", ...) 与 store.set("oauth_client_secret", ...) 自定义覆盖
local DEFAULT_CLIENT_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
local DEFAULT_CLIENT_SECRET = "SboVhoG9s0rNafixCSGGKXAT"
local OAUTH_SCOPE = "https://www.googleapis.com/auth/youtube"

local ENDPOINT_DEVICE_CODE = "https://oauth2.googleapis.com/device/code"
local ENDPOINT_DEVICE_CODE_FALLBACK = "https://www.youtube.com/o/oauth2/device/code"
local ENDPOINT_TOKEN = "https://oauth2.googleapis.com/token"

--- 获取当前生效的 Client ID 与 Client Secret
function oauth.get_credentials()
  local custom_id = store.get("oauth_client_id")
  local custom_secret = store.get("oauth_client_secret")

  if custom_id and string.len(custom_id) > 0 and custom_secret and string.len(custom_secret) > 0 then
    return custom_id, custom_secret
  end
  return DEFAULT_CLIENT_ID, DEFAULT_CLIENT_SECRET
end

--- 第一步：向 Google 申请设备验证码与用户码 (RFC 8628)
function oauth.request_device_code()
  local client_id, _ = oauth.get_credentials()

  local payload = {
    client_id = client_id,
    scope = OAUTH_SCOPE
  }

  local req = {
    url = ENDPOINT_DEVICE_CODE,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["User-Agent"] = "Mozilla/5.0 Cobalt/Version"
    },
    body = host.json_encode(payload)
  }

  local ok, resp = pcall(function() return host.http(req) end)

  -- 若主端点失败，尝试 Fallback 端点
  if not ok or not resp or not resp.body or resp.status ~= 200 then
    req.url = ENDPOINT_DEVICE_CODE_FALLBACK
    ok, resp = pcall(function() return host.http(req) end)
  end

  if ok and resp and resp.body and resp.status == 200 then
    local parse_ok, data = pcall(function() return host.json_decode(resp.body) end)
    if parse_ok and type(data) == "table" and data.device_code and data.user_code then
      return {
        device_code = data.device_code,
        user_code = data.user_code,
        verification_url = data.verification_url or "https://www.google.com/device",
        expires_in = tonumber(data.expires_in) or 1800,
        interval = tonumber(data.interval) or 5
      }
    end
  end

  return nil, (resp and resp.status) or "network_error"
end

--- 第二步：轮询 Google 授权状态
-- 返回值：
-- "success", data (包含 access_token, refresh_token, expires_in)
-- "pending", nil (等待用户在网页端确认)
-- "expired", nil (验证码已过期或用户拒绝)
-- "error", msg (发生未知错误)
function oauth.poll_token(device_code)
  if not device_code or string.len(device_code) == 0 then
    return "error", "invalid_device_code"
  end

  local client_id, client_secret = oauth.get_credentials()

  local payload = {
    client_id = client_id,
    client_secret = client_secret,
    code = device_code,
    grant_type = "http://oauth.net/grant_type/device/1.0"
  }

  local req = {
    url = ENDPOINT_TOKEN,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["User-Agent"] = "Mozilla/5.0 Cobalt/Version"
    },
    body = host.json_encode(payload)
  }

  local ok, resp = pcall(function() return host.http(req) end)
  if not ok or not resp or not resp.body then
    return "pending", nil
  end

  local parse_ok, data = pcall(function() return host.json_decode(resp.body) end)
  if not parse_ok or type(data) ~= "table" then
    return "pending", nil
  end

  if resp.status == 200 and data.access_token then
    return "success", {
      access_token = tostring(data.access_token),
      refresh_token = tostring(data.refresh_token or ""),
      expires_in = tonumber(data.expires_in) or 3600
    }
  end

  local err = tostring(data.error or "")
  if err == "authorization_pending" or err == "slow_down" or resp.status == 428 then
    return "pending", nil
  elseif err == "expired_token" or err == "access_denied" then
    return "expired", nil
  end

  return "error", err
end

--- 第三步：静默使用 refresh_token 刷新 access_token
function oauth.refresh_token()
  local refresh_token = store.get_refresh_token()
  if not refresh_token or string.len(refresh_token) == 0 then
    return false
  end

  local client_id, client_secret = oauth.get_credentials()

  local payload = {
    client_id = client_id,
    client_secret = client_secret,
    refresh_token = refresh_token,
    grant_type = "refresh_token"
  }

  local req = {
    url = ENDPOINT_TOKEN,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["User-Agent"] = "Mozilla/5.0 Cobalt/Version"
    },
    body = host.json_encode(payload)
  }

  local ok, resp = pcall(function() return host.http(req) end)
  if ok and resp and resp.status == 200 and resp.body then
    local parse_ok, data = pcall(function() return host.json_decode(resp.body) end)
    if parse_ok and type(data) == "table" and data.access_token then
      store.set_access_token(tostring(data.access_token))
      local exp = store.now_sec() + (tonumber(data.expires_in) or 3600)
      store.set_expires_at(exp)
      return true
    end
  end

  return false
end

--- 检查当前 Token 是否即将过期并在后台自动静默刷新
function oauth.ensure_valid_token()
  local token = store.get_access_token()
  if not token or string.len(token) == 0 then
    return
  end

  local expires_at = store.get_expires_at()
  local now = store.now_sec()

  -- 如果距离过期时间不足 5 分钟 (300 秒)，自动发起静默刷新
  if (expires_at - now) < 300 then
    oauth.refresh_token()
  end
end

return oauth
