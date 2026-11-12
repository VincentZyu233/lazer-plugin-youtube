local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local auth_cookie = require("ytm.auth.cookie")
local nav = require("ytm.core.navigation")

local account = {}

--- 从 account_menu 的响应中提取当前登录账号的用户昵称与头像
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

--- 检查并返回当前已保存的会话
function account.session()
  local saved_cookie = store.get_cookie()
  if not saved_cookie or string.len(saved_cookie) == 0 then
    return nil
  end

  local saved_name = store.get("user_name") or "YouTube User"
  local saved_avatar = store.get("user_avatar") or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
  local saved_id = store.get("user_id") or "yt_authenticated"

  return {
    id = saved_id,
    name = saved_name,
    avatarUrl = saved_avatar
  }
end

--- 使用 Cookie 进行登录验证并持久化
function account.login_cookie(args)
  local cookie_str = tostring(args and args.cookie or "")
  if string.len(cookie_str) == 0 then
    error("Cookie 不能为空", 0)
  end

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

  local res = host.http({
    url = constants.HOST_MUSIC .. "/youtubei/v1/account/account_menu",
    method = "POST",
    headers = req_headers,
    body = host.json_encode(payload)
  })

  if not res or res.status ~= 200 then
    error("网络连接失败，请检查代理是否正常开启 (HTTP " .. tostring(res and res.status or "nil") .. ")", 0)
  end

  local ok, data = pcall(host.json_decode, res.body)
  local info = ok and extract_account_info(data)

  if not info then
    if not string.find(cookie_str, "LOGIN_INFO") then
      error("登录失败：检测到 Cookie 中缺少 YouTube 核心会话 (LOGIN_INFO)。请重新运行 tools/get_cookie.js，确保浏览器完全跳转回 YouTube Music 页面后再抓取！", 0)
    end
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

--- 退出登录
function account.logout()
  store.set_cookie("")
  store.set("user_name", "")
  store.set("user_avatar", "")
  store.set("user_id", "")
  return true
end

return account
