local config = require("yt.config")
local client = {}

local function do_post(url, payload, client_profile)
  local profile = client_profile or config.CLIENT_WEB_REMIX
  local ctx = {
    client = profile
  }
  payload.context = ctx

  local body_str = host.json_encode(payload)
  local ua = (profile and profile.userAgent) or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = ua,
    ["X-Goog-Api-Format-Version"] = "2"
  }

  local res = host.http({
    url = url,
    method = "POST",
    headers = headers,
    body = body_str
  })

  if not res or res.status ~= 200 then
    return nil, "HTTP " .. tostring(res and res.status or "nil")
  end

  local ok, data = pcall(host.json_decode, res.body)
  if not ok or not data then
    return nil, "Invalid JSON response"
  end
  return data
end

function client.post_youtube(endpoint, payload, client_profile)
  local url = config.HOST_YOUTUBE .. "/youtubei/v1/" .. endpoint
  return do_post(url, payload, client_profile or config.CLIENT_VISIONOS)
end

function client.post_music(endpoint, payload, client_profile)
  local url = config.HOST_MUSIC .. "/youtubei/v1/" .. endpoint
  return do_post(url, payload, client_profile or config.CLIENT_WEB_REMIX)
end

return client
