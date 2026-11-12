local config = require("yt.config")
local client = {}

local function do_post(url, payload, client_profile)
  local ctx = {
    client = client_profile or config.CLIENT_IOS
  }
  payload.context = ctx

  local body_str = host.json_encode(payload)
  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = (client_profile and client_profile.userAgent) or config.CLIENT_IOS.userAgent,
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
  return do_post(url, payload, client_profile)
end

function client.post_music(endpoint, payload, client_profile)
  local url = config.HOST_MUSIC .. "/youtubei/v1/" .. endpoint
  return do_post(url, payload, client_profile or config.CLIENT_WEB_REMIX)
end

return client
