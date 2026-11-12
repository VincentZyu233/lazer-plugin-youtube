local config = require("ytm.config")
local auth = require("ytm.auth")
local account = {}

--- 从 account_menu 的响应中提取当前登录账号的用户昵称与头像
local function extract_account_info(data)
  if not data or type(data) ~= "table" then return nil end
  local actions = data.actions
  if not actions or type(actions) ~= "table" then return nil end

  for _, act in ipairs(actions) do
    local popup = act.openPopupAction and act.openPopupAction.popup
    local menu = popup and popup.multiPageMenuRenderer
    local header = menu and menu.header
    local active = header and header.activeAccountHeaderRenderer
    if active then
      local name = nil
      if active.accountName and active.accountName.runs and active.accountName.runs[1] then
        name = active.accountName.runs[1].text
      end

      local avatar_url = nil
      if active.accountPhoto and active.accountPhoto.thumbnails then
        local thumbs = active.accountPhoto.thumbnails
        if #thumbs > 0 and thumbs[#thumbs].url then
          avatar_url = thumbs[#thumbs].url
          if string.sub(avatar_url, 1, 2) == "//" then
            avatar_url = "https:" .. avatar_url
          end
        end
      end

      local handle = nil
      if active.channelHandle and active.channelHandle.runs and active.channelHandle.runs[1] then
        handle = active.channelHandle.runs[1].text
      end

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
-- 符合宿主 MusicUser _adopt 契约：登录有效时直接返回平铺对象，未登录时返回 nil
function account.session()
  local saved_cookie = host.storage_get("user_cookie")
  if not saved_cookie or string.len(saved_cookie) == 0 then
    return nil
  end

  local saved_name = host.storage_get("user_name") or "YouTube User"
  local saved_avatar = host.storage_get("user_avatar") or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
  local saved_id = host.storage_get("user_id") or "yt_authenticated"

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
    error("Cookie 不能为空")
  end

  -- 向 YouTube Music account_menu 发起验证请求以获取真实用户名与头像
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

  local auth_header = auth.generate_authorization(cookie_str, config.HOST_MUSIC)
  local req_headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    ["Origin"] = config.HOST_MUSIC,
    ["X-Origin"] = config.HOST_MUSIC,
    ["X-Goog-Api-Format-Version"] = "2",
    ["Cookie"] = cookie_str
  }
  if auth_header then
    req_headers["Authorization"] = auth_header
  end

  local res = host.http({
    url = "https://music.youtube.com/youtubei/v1/account/account_menu",
    method = "POST",
    headers = req_headers,
    body = host.json_encode(payload)
  })

  if not res or res.status ~= 200 then
    error("网络连接失败，请检查代理是否正常开启 (HTTP " .. tostring(res and res.status or "nil") .. ")")
  end

  local ok, data = pcall(host.json_decode, res.body)
  local info = ok and extract_account_info(data)

  -- 如果未能获取到账号专属卡片，提示用户 Cookie 是否完整
  if not info then
    if not string.find(cookie_str, "LOGIN_INFO") then
      error("登录失败：检测到 Cookie 中缺少 YouTube 核心会话 (LOGIN_INFO)。请重新运行 tools/get_cookie.js，确保浏览器完全跳转回 YouTube Music 页面后再抓取！")
    end
  end

  local user_name = (info and info.name) or "YouTube User"
  local user_avatar = (info and info.avatarUrl) or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
  local user_id = (info and info.handle) or "yt_authenticated"

  -- 持久化存储
  host.storage_set("user_cookie", cookie_str)
  host.storage_set("user_name", user_name)
  host.storage_set("user_avatar", user_avatar)
  host.storage_set("user_id", user_id)

  return {
    id = user_id,
    name = user_name,
    avatarUrl = user_avatar
  }
end

--- 退出登录
function account.logout()
  host.storage_set("user_cookie", "")
  host.storage_set("user_name", "")
  host.storage_set("user_avatar", "")
  host.storage_set("user_id", "")
  return true
end

return account
