local config = require("yt.config")
local client = {}

local memory_visitor_data = nil

function client.get_cookie()
  local ok, val = pcall(host.storage_get, "user_cookie")
  if ok and val and type(val) == "string" and string.len(val) > 0 then
    return val
  end
  return nil
end

function client.get_visitor_data()
  if memory_visitor_data and string.len(memory_visitor_data) > 0 then
    return memory_visitor_data
  end
  local ok, val = pcall(host.storage_get, "visitor_data")
  if ok and val and type(val) == "string" and string.len(val) > 0 then
    memory_visitor_data = val
    return memory_visitor_data
  end
  return nil
end

function client.set_visitor_data(data)
  if data and type(data) == "string" and string.len(data) > 0 then
    memory_visitor_data = data
    pcall(host.storage_set, "visitor_data", data)
  end
end

local function do_post(url, payload, client_profile)
  local profile = client_profile or config.CLIENT_WEB_REMIX
  local visitor_data = client.get_visitor_data()

  local ctx_client = {}
  for k, v in pairs(profile) do
    ctx_client[k] = v
  end
  if visitor_data and string.len(visitor_data) > 0 then
    ctx_client.visitorData = visitor_data
  end

  payload.context = {
    client = ctx_client
  }

  local ua = (profile and profile.userAgent) or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = ua,
    ["X-Goog-Api-Format-Version"] = "2"
  }

  if visitor_data and string.len(visitor_data) > 0 then
    headers["X-Goog-Visitor-Id"] = visitor_data
  end

  local cookie = client.get_cookie()
  if cookie and string.len(cookie) > 0 then
    headers["Cookie"] = cookie
  end

  local body_str = host.json_encode(payload)
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
    client.set_visitor_data(data.responseContext.visitorData)
  end

  return data
end

function client.ensure_visitor_data()
  local existing = client.get_visitor_data()
  if existing and string.len(existing) > 0 then
    return existing
  end

  -- 向 YouTube Music 发起一次极小查询以初始化获取 visitorData 会话
  local search_url = config.HOST_MUSIC .. "/youtubei/v1/search"
  local payload = {
    query = "music"
  }
  do_post(search_url, payload, config.CLIENT_WEB_REMIX)
  return client.get_visitor_data()
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
