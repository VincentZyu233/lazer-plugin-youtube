local account = require("ytm.account")
local catalog = require("ytm.catalog")
local stream = require("ytm.stream")

local plugin = {}

function plugin.call(operation, args)
  args = args or {}

  -- 1. 声明平台能力与元数据
  if operation == "describe" then
    return {
      providers = {
        {
          id = "youtube",
          name = "YouTube Music",
          auth = { "cookie" },
          capabilities = {
            "search",
            "lyrics",
            "homeFeed",
            "radio",
            "recommendations",
            "favorites"
          },
          loginHint = "在浏览器中打开 music.youtube.com，复制网络请求中的 Cookie 粘贴到下方即可登录",
          cookieHint = "支持包含 SID, HSID, SSID, SAPISID 的 Cookie 字符串"
        }
      }
    }
  end

  -- 2. 账号会话与登录
  if operation == "session" then
    return account.session()
  elseif operation == "loginCookie" then
    return account.login_cookie(args)
  elseif operation == "logout" then
    return account.logout()
  end

  -- 3. 搜索与音频流
  if operation == "search" then
    return catalog.search(args)
  elseif operation == "stream" then
    local song_id = args.id or args.songId or ""
    local quality = args.quality or "standard"
    return stream.get_audio_url(song_id, quality)
  elseif operation == "song" then
    local song_id = args.id or args.songId or ""
    return catalog.song(song_id)
  elseif operation == "lyrics" then
    return { lrc = "" }
  elseif operation == "favorites" then
    return catalog.favorites(args)
  elseif operation == "homeFeed" then
    return { sections = {} }
  end

  return nil
end

return plugin
