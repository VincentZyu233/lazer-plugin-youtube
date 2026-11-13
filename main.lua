-- Lazer YouTube & YouTube Music Plugin
-- 架构设计参考 ytmusicapi：Parsers (纯数据清洗) / Services (网络与业务编排) / Core (通信底座)

local account = require("ytm.account")
local catalog = require("ytm.services.catalog")
local lyrics = require("ytm.services.lyrics")
local stream = require("ytm.services.stream")
local discover = require("ytm.services.discover")

local plugin = {}

local CAPABILITIES = {
  "search",
  "lyrics",
  "playlists",
  "homeFeed",
  "charts",
  "radio",
  "recommendations",
  "favorites"
}

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
          capabilities = CAPABILITIES,
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
  elseif operation == "playlist" then
    local playlist_id = args.id or args.playlistId or ""
    return catalog.playlist(playlist_id)
  elseif operation == "playlistSongs" then
    local playlist_id = args.id or args.playlistId or ""
    local limit = tonumber(args.limit) or 50
    local offset = tonumber(args.offset) or 0
    return catalog.playlist_songs(playlist_id, limit, offset)
  elseif operation == "lyrics" then
    local song_id = args.id or args.songId or ""
    return lyrics.get_lyrics(song_id)
  elseif operation == "favorites" then
    return catalog.favorites(args)
  elseif operation == "homeFeed" then
    return discover.home_feed()
  elseif operation == "recommendations" then
    local limit = tonumber(args.limit) or 30
    return discover.recommendations(limit)
  elseif operation == "charts" then
    return discover.charts()
  elseif operation == "radio" then
    return discover.radio(args)
  end

  return nil
end

return plugin
