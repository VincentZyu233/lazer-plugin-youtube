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

function store.get_visitor_data()
  return store.get("visitor_data")
end

function store.set_visitor_data(data)
  if data and type(data) == "string" and string.len(data) > 0 then
    store.set("visitor_data", data)
  end
end

return store
