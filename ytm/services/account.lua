local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local auth_cookie = require("ytm.auth.cookie")
local oauth = require("ytm.auth.oauth")
local nav = require("ytm.core.navigation")

local account = {}

local pending_sessions = {}

--- 从 account_menu 的响应中提取当前登录账号的用户昵称与头像 (Cookie 模式)
local function extract_account_info(data)
  if not data or type(data) ~= "table" then return nil end
  local actions = data.actions
  if not actions or type(actions) ~= "table" then return nil end

  for _, act in ipairs(actions) do
    local active = nav.nav(act, {
      "openPopupAction", "popup", "multiPageMenuRenderer", "header", "activeAccountHeaderRenderer"
    })
    if active then
      local name = nav.nav(active, { "accountName", "runs", 1, "text" })

      local avatar_url = nil
      local thumbs = nav.nav(active, { "accountPhoto", "thumbnails" })
      if thumbs and #thumbs > 0 and thumbs[#thumbs].url then
        avatar_url = thumbs[#thumbs].url
        if string.sub(avatar_url, 1, 2) == "//" then
          avatar_url = "https:" .. avatar_url
        end
      end

      local handle = nav.nav(active, { "channelHandle", "runs", 1, "text" })

      return {
        name = name,
        avatarUrl = avatar_url,
        handle = handle
      }
    end
  end
  return nil
end

--- 使用 Access Token 获取当前账号个人信息 (OAuth 模式: TVHTML5 guide 端点)
function account.fetch_current_user_info(access_token)
  if not access_token or string.len(access_token) == 0 then return nil end

  local payload = {
    context = {
      client = {
        clientName = constants.CLIENT_TVHTML5.clientName,
        clientVersion = constants.CLIENT_TVHTML5.clientVersion,
        hl = "zh-CN",
        gl = "JP"
      }
    }
  }

  local req_headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = constants.CLIENT_TVHTML5.userAgent,
    ["Authorization"] = "Bearer " .. access_token
  }

  local ok, res = pcall(function()
    return host.http({
      url = "https://www.youtube.com/youtubei/v1/guide?alt=json",
      method = "POST",
      headers = req_headers,
      body = host.json_encode(payload)
    })
  end)

  if ok and res and res.status == 200 and res.body then
    local parse_ok, data = pcall(host.json_decode, res.body)
    if parse_ok and type(data) == "table" then
      local items = nav.nav(data, { "topbar", "guideSectionRenderer", "items" })
      if items and type(items) == "table" then
        for _, it in ipairs(items) do
          local entry = it.guideAccountEntryRenderer
          if entry then
            local name = nav.nav(entry, { "title", "simpleText" }) or nav.nav(entry, { "title", "runs", 1, "text" })
            local avatar_url = nil
            local thumbs = nav.nav(entry, { "thumbnail", "thumbnails" })
            if thumbs and #thumbs > 0 and thumbs[#thumbs].url then
              avatar_url = thumbs[#thumbs].url
              if string.sub(avatar_url, 1, 2) == "//" then
                avatar_url = "https:" .. avatar_url
              end
            end

            if name or avatar_url then
              return {
                name = name or "YouTube 用户",
                avatarUrl = avatar_url or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png",
                handle = name
              }
            end
          end
        end
      end
    end
  end

  return nil
end

--- 使用 Cookie 获取当前账号个人信息 (Cookie 模式: account_menu 接口，对齐 0.1.x 原生直调规范)
function account.fetch_cookie_user_info(cookie_str)
  if not cookie_str or string.len(cookie_str) == 0 then return nil end
  local cleaned = auth_cookie.clean_cookie(cookie_str)

  local payload = {
    context = {
      client = {
        clientName = "WEB_REMIX",
        clientVersion = "1.20261110.04.00",
        hl = "zh-CN",
        gl = "JP"
      }
    }
  }

  local auth_header = auth_cookie.generate_authorization(cleaned, constants.HOST_MUSIC)
  local req_headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = constants.CLIENT_WEB_REMIX.userAgent,
    ["Origin"] = constants.HOST_MUSIC,
    ["X-Origin"] = constants.HOST_MUSIC,
    ["X-Goog-Api-Format-Version"] = "2",
    ["Cookie"] = cleaned
  }
  if auth_header then
    req_headers["Authorization"] = auth_header
  end

  local ok, res = pcall(function()
    return host.http({
      url = constants.HOST_MUSIC .. "/youtubei/v1/account/account_menu",
      method = "POST",
      headers = req_headers,
      body = host.json_encode(payload)
    })
  end)

  if ok and res and res.status == 200 and res.body then
    local parse_ok, data = pcall(host.json_decode, res.body)
    if parse_ok and data then
      return extract_account_info(data)
    end
  end
  return nil
end

--- 检查并返回当前已保存的会话
function account.session()
  if not store.is_authenticated() then
    return nil
  end

  local saved_name = store.get("user_name")
  local saved_avatar = store.get("user_avatar")
  local saved_id = store.get("user_id")

  -- 自动恢复/纠正逻辑：如果当前只有 "YouTube User" / "YouTube 用户" 占位名，自动静默更新为真正账号名与头像
  local access_token = store.get_access_token()
  local cookie = store.get_cookie()

  if access_token and string.len(access_token) > 0 and (not saved_name or saved_name == "YouTube 用户" or saved_name == "YouTube User" or saved_name == "") then
    local info = account.fetch_current_user_info(access_token)
    if info and info.name and info.name ~= "YouTube 用户" and info.name ~= "YouTube User" then
      saved_name = info.name
      saved_avatar = info.avatarUrl or saved_avatar
      saved_id = info.handle or saved_id
      store.set("user_name", saved_name)
      store.set("user_avatar", saved_avatar)
      store.set("user_id", saved_id)
    end
  elseif cookie and string.len(cookie) > 0 and (not saved_name or saved_name == "YouTube User" or saved_name == "YouTube 用户" or saved_name == "") then
    local info = account.fetch_cookie_user_info(cookie)
    if info and info.name and info.name ~= "YouTube User" and info.name ~= "YouTube 用户" then
      saved_name = info.name
      saved_avatar = info.avatarUrl or saved_avatar
      saved_id = info.handle or saved_id
      -- 同时把清洗后的 cookie 回写持久化
      local clean_c = auth_cookie.clean_cookie(cookie)
      store.set_cookie(clean_c)
      store.set("user_name", saved_name)
      store.set("user_avatar", saved_avatar)
      store.set("user_id", saved_id)
    end
  end

  return {
    id = saved_id or "yt_authenticated",
    name = (saved_name and string.len(saved_name) > 0) and saved_name or "YouTube 用户",
    avatarUrl = (saved_avatar and string.len(saved_avatar) > 0) and saved_avatar or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
  }
end

--- 获取扫码 Key (Lazer 契约: qrKey)
function account.qrKey()
  local res, err = oauth.request_device_code()
  if res and res.device_code and res.user_code then
    local user_code = tostring(res.user_code)
    pending_sessions[user_code] = {
      device_code = tostring(res.device_code),
      user_code = user_code,
      expires_at = store.now_sec() + (tonumber(res.expires_in) or 1800),
      interval = tonumber(res.interval) or 5
    }
    return user_code
  end
  return nil
end

--- 获取扫码展示用的 URL (Lazer 契约: qrUrl)
function account.qrUrl(args)
  local key = tostring(args and args.key or "")
  if key == "" then
    return "https://youtube.com/activate"
  end
  return "https://youtube.com/activate?user_code=" .. host.url_encode(key)
end

--- 轮询二维码扫码与授权状态 (Lazer 契约: qrCheck)
-- 契约状态码：801=等待扫码确认, 802=已扫码待确认, 803=成功, 800=过期/失效/拒绝
function account.qrCheck(args)
  local key = tostring(args and args.key or "")
  if key == "" then return 800 end

  local sess = pending_sessions[key]
  if not sess then return 800 end

  if store.now_sec() > sess.expires_at then
    pending_sessions[key] = nil
    return 800
  end

  local status, data = oauth.poll_token(sess.device_code)

  if status == "success" and data and data.access_token then
    pending_sessions[key] = nil

    local access_token = tostring(data.access_token)
    local refresh_token = tostring(data.refresh_token or "")
    local expires_in = tonumber(data.expires_in) or 3600
    local expires_at = store.now_sec() + expires_in

    store.set_access_token(access_token)
    if string.len(refresh_token) > 0 then
      store.set_refresh_token(refresh_token)
    end
    store.set_expires_at(expires_at)

    -- 使用 TVHTML5 guide 接口获取用户真实的 Google / YouTube 个人信息
    local user_info = account.fetch_current_user_info(access_token)
    local user_name = (user_info and user_info.name) or "YouTube 用户"
    local user_avatar = (user_info and user_info.avatarUrl) or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
    local user_id = (user_info and user_info.handle) or ("yt_oauth_" .. string.sub(access_token, -8))

    store.set("user_name", user_name)
    store.set("user_avatar", user_avatar)
    store.set("user_id", user_id)

    return 803
  elseif status == "pending" then
    return 801
  elseif status == "expired" then
    pending_sessions[key] = nil
    return 800
  else
    return 801
  end
end

--- 使用 Cookie 进行登录验证并持久化 (支持直接传参校验，若为空或校验失败自动 fallback 读取本地 storage.json)
function account.login_cookie(args)
  local raw_cookie = tostring(args and args.cookie or "")
  -- 清理首尾空格与换行符
  raw_cookie = raw_cookie:match("^%s*(.-)%s*$") or ""

  -- 1. 如果传入为空，自动 fallback 到本地 storage 中已有的 Cookie (例如由 get_cookie.js 自动注入)
  if string.len(raw_cookie) == 0 then
    local saved = store.get_cookie()
    if saved and string.len(saved) > 0 then
      raw_cookie = saved:match("^%s*(.-)%s*$") or ""
    end
  end

  if string.len(raw_cookie) == 0 then
    -- 无有效 Cookie 输入且本地存储为空，返回 nil 让 Lazer 弹出 "这个 Cookie 无效或已过期。"
    return nil
  end

  -- 内部校验逻辑
  local function verify_cookie(candidate_cookie)
    if not candidate_cookie or string.len(candidate_cookie) == 0 then
      return nil
    end

    local cookie_str = auth_cookie.clean_cookie(candidate_cookie)
    local payload = {
      context = {
        client = {
          clientName = "WEB_REMIX",
          clientVersion = "1.20261110.04.00",
          hl = "zh-CN",
          gl = "JP"
        }
      }
    }

    local auth_header = auth_cookie.generate_authorization(cookie_str, constants.HOST_MUSIC)
    local req_headers = {
      ["Content-Type"] = "application/json",
      ["User-Agent"] = constants.CLIENT_WEB_REMIX.userAgent,
      ["Origin"] = constants.HOST_MUSIC,
      ["X-Origin"] = constants.HOST_MUSIC,
      ["X-Goog-Api-Format-Version"] = "2",
      ["Cookie"] = cookie_str
    }
    if auth_header then
      req_headers["Authorization"] = auth_header
    end

    local ok, res = pcall(function()
      return host.http({
        url = constants.HOST_MUSIC .. "/youtubei/v1/account/account_menu",
        method = "POST",
        headers = req_headers,
        body = host.json_encode(payload)
      })
    end)

    if not ok or not res or res.status ~= 200 or not res.body then
      return nil
    end

    local parse_ok, data = pcall(host.json_decode, res.body)
    local info = parse_ok and extract_account_info(data)

    if not info and not string.find(cookie_str, "LOGIN_INFO") then
      return nil
    end

    local user_name = (info and info.name) or "YouTube User"
    local user_avatar = (info and info.avatarUrl) or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
    local user_id = (info and info.handle) or "yt_authenticated"

    store.set_cookie(cookie_str)
    store.set("user_name", user_name)
    store.set("user_avatar", user_avatar)
    store.set("user_id", user_id)

    return {
      id = user_id,
      name = user_name,
      avatarUrl = user_avatar
    }
  end

  -- 首先尝试当前 candidate
  local result = verify_cookie(raw_cookie)
  if result then
    return result
  end

  -- 2. 如果当前 candidate 校验失败，且与本地 storage 的 Cookie 不同，尝试 fallback 到本地 storage
  local saved_cookie = store.get_cookie()
  if saved_cookie and string.len(saved_cookie) > 0 then
    local clean_saved = saved_cookie:match("^%s*(.-)%s*$") or ""
    if clean_saved ~= raw_cookie then
      local fallback_result = verify_cookie(clean_saved)
      if fallback_result then
        return fallback_result
      end
    end
  end

  return nil
end

--- 退出登录
function account.logout()
  store.set_cookie("")
  store.set_access_token("")
  store.set_refresh_token("")
  store.set_expires_at(0)
  store.set("user_name", "")
  store.set("user_avatar", "")
  store.set("user_id", "")
  return true
end

return account
