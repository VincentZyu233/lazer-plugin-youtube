local config = require("yt.config")
local account = {}

--- 检查并返回当前已保存的会话
function account.session()
  local saved_cookie = host.storage_get("user_cookie")
  if not saved_cookie or string.len(saved_cookie) == 0 then
    -- 未登录时返回 guest 假会话，允许免登录播放
    return {
      valid = false,
      user = nil
    }
  end

  local saved_name = host.storage_get("user_name") or "YouTube User"
  local saved_avatar = host.storage_get("user_avatar") or "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
  local saved_id = host.storage_get("user_id") or "yt_user"

  return {
    valid = true,
    user = {
      id = saved_id,
      name = saved_name,
      avatar = saved_avatar
    }
  }
end

--- 使用 Cookie 进行登录验证并持久化
function account.login_cookie(args)
  local cookie_str = tostring(args and args.cookie or "")
  if string.len(cookie_str) == 0 then
    error("Cookie 不能为空")
  end

  -- 向 YouTube 发起一次携带该 Cookie 的轻量级验证请求
  local res = host.http({
    url = "https://www.youtube.com",
    method = "GET",
    headers = {
      ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
      ["Cookie"] = cookie_str
    }
  })

  if not res or res.status ~= 200 then
    error("网络连接失败，请检查代理是否正常开启")
  end

  -- 简单校验是否包含 Google 登录标识
  -- 登录成功的页面中通常包含 LOGGED_IN = true 或 session_token
  local body = res.body or ""
  local is_logged_in = string.find(body, '"LOGGED_IN":true') or string.find(body, 'logged_in') or string.find(cookie_str, "SAPISID") or string.find(cookie_str, "SID=")

  if not is_logged_in then
    error("该 Cookie 无效或已过期，请重新在浏览器登录后复制")
  end

  -- 提取用户昵称
  local user_name = string.match(body, '"title":"(.-)","navigationEndpoint"') or "YouTube User"
  if string.len(user_name) > 30 then
    user_name = "YouTube User"
  end

  -- 持久化存储
  host.storage_set("user_cookie", cookie_str)
  host.storage_set("user_name", user_name)
  host.storage_set("user_avatar", "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png")
  host.storage_set("user_id", "yt_authenticated")

  return {
    id = "yt_authenticated",
    name = user_name,
    avatar = "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
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
