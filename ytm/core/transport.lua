local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local auth_cookie = require("ytm.auth.cookie")

local transport = {}

function transport.ensure_visitor_data()
  local existing = store.get_visitor_data()
  if existing and string.len(existing) > 0 then
    return existing
  end

  local search_url = constants.HOST_MUSIC .. "/youtubei/v1/search"
  local payload = {
    query = "music"
  }
  transport.request(search_url, payload, constants.CLIENT_WEB_REMIX, nil)
  return store.get_visitor_data()
end

function transport.request(url_or_endpoint, payload, client_profile, target_host)
  local profile = client_profile or constants.CLIENT_WEB_REMIX
  local base_host = target_host or constants.HOST_MUSIC

  local url = url_or_endpoint
  if string.sub(url, 1, 4) ~= "http" then
    url = base_host .. "/youtubei/v1/" .. url_or_endpoint
  end

  local visitor_data = store.get_visitor_data()

  local ctx_client = {}
  for k, v in pairs(profile) do
    if k ~= "userAgent" then
      ctx_client[k] = v
    end
  end
  if visitor_data and string.len(visitor_data) > 0 then
    ctx_client.visitorData = visitor_data
  end

  local req_body = {}
  if type(payload) == "table" then
    for k, v in pairs(payload) do
      req_body[k] = v
    end
  end
  req_body.context = {
    client = ctx_client
  }

  local is_mobile = (profile and profile.clientName == "ANDROID_MUSIC")
  local ua = (profile and profile.userAgent) or constants.CLIENT_WEB_REMIX.userAgent
  local origin = (profile and profile.clientName == "VISIONOS") and constants.HOST_YOUTUBE or constants.HOST_MUSIC

  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = ua,
    ["X-Goog-Api-Format-Version"] = "2"
  }

  if not is_mobile then
    headers["Origin"] = origin
    headers["X-Origin"] = origin
  end

  if profile.clientName == "VISIONOS" then
    headers["X-YouTube-Client-Name"] = "101"
    headers["X-YouTube-Client-Version"] = "1.02"
  end

  if visitor_data and string.len(visitor_data) > 0 then
    headers["X-Goog-Visitor-Id"] = visitor_data
  end

  local cookie = store.get_cookie()
  if cookie and string.len(cookie) > 0 then
    headers["Cookie"] = cookie
    if not is_mobile then
      local auth_header = auth_cookie.generate_authorization(cookie, origin)
      if auth_header then
        headers["Authorization"] = auth_header
      end
    end
  end

  local body_str = host.json_encode(req_body)
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

  if data.responseContext and data.responseContext.visitorData then
    store.set_visitor_data(data.responseContext.visitorData)
  end

  return data
end

function transport.post_music(endpoint, payload, client_profile)
  return transport.request(endpoint, payload, client_profile or constants.CLIENT_WEB_REMIX, constants.HOST_MUSIC)
end

function transport.post_youtube(endpoint, payload, client_profile)
  return transport.request(endpoint, payload, client_profile or constants.CLIENT_VISIONOS, constants.HOST_YOUTUBE)
end

return transport
