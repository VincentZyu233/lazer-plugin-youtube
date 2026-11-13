local store = {}

local memory_cache = {}

function store.get(key)
  if memory_cache[key] ~= nil then
    return memory_cache[key]
  end
  if host and type(host.storage_get) == "function" then
    local ok, val = pcall(host.storage_get, key)
    if ok and val ~= nil and val ~= "" then
      memory_cache[key] = val
      return val
    end
  end
  return nil
end

function store.set(key, value)
  memory_cache[key] = value
  if host and type(host.storage_set) == "function" then
    pcall(host.storage_set, key, value or "")
  end
end

function store.delete(key)
  memory_cache[key] = nil
  if host and type(host.storage_set) == "function" then
    pcall(host.storage_set, key, "")
  end
end

function store.get_cookie()
  return store.get("user_cookie")
end

function store.set_cookie(cookie)
  store.set("user_cookie", cookie)
end

function store.get_access_token()
  return store.get("access_token")
end

function store.set_access_token(token)
  store.set("access_token", token)
end

function store.get_refresh_token()
  return store.get("refresh_token")
end

function store.set_refresh_token(token)
  store.set("refresh_token", token)
end

function store.get_expires_at()
  return tonumber(store.get("expires_at") or 0)
end

function store.set_expires_at(ts)
  store.set("expires_at", tostring(ts or 0))
end

function store.now_ms()
  if host and type(host.now) == "function" then
    local ok, res = pcall(host.now)
    if ok and tonumber(res) then return tonumber(res) end
  end
  if type(os) == "table" and type(os.time) == "function" then
    local ok, s = pcall(os.time)
    if ok and tonumber(s) then return tonumber(s) * 1000 end
  end
  return 0
end

function store.now_sec()
  return math.floor(store.now_ms() / 1000)
end

function store.is_authenticated()
  local c = store.get_cookie()
  if c and string.len(c) > 0 then return true end
  local t = store.get_access_token()
  if t and string.len(t) > 0 then return true end
  return false
end

function store.get_visitor_data()
  return store.get("visitor_data")
end

function store.set_visitor_data(data)
  if data and type(data) == "string" and string.len(data) > 0 then
    store.set("visitor_data", data)
  end
end

return store
