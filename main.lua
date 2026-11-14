-- Lazer YouTube & YouTube Music Plugin
-- 架构设计参考 ytmusicapi：Parsers (纯数据清洗) / Services (网络与业务编排) / Core (通信底座)

local account = require("ytm.services.account")
local catalog = require("ytm.services.catalog")
local lyrics = require("ytm.services.lyrics")
local stream = require("ytm.services.stream")
local discover = require("ytm.services.discover")

local plugin = {}

local CAPABILITIES = {
  "search",
  "lyrics",
  "playlists",
  "browseAlbums",
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
          auth = { "qr", "cookie" },
          capabilities = CAPABILITIES,
          loginHint = "使用手机相机扫码直接授权登录，或在下方输入 -1 / LOCAL 读取本地凭据（亦可粘贴完整 Cookie）",
          cookieHint = "输入 -1 或 LOCAL 读取本地存储凭据，亦可直接粘贴完整 Cookie"
        }
      }
    }
  end

  -- 2. 账号会话与登录
  if operation == "session" then
    return account.session()
  elseif operation == "loginCookie" then
    return account.login_cookie(args)
  elseif operation == "qrKey" then
    return account.qrKey()
  elseif operation == "qrUrl" then
    return account.qrUrl(args)
  elseif operation == "qrCheck" then
    return account.qrCheck(args)
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
    local playlist_id = (type(args) == "table" and (args.id or args.playlistId or args.playlist_id)) or tostring(args or "")
    return catalog.playlist(playlist_id)
  elseif operation == "playlists" then
    return catalog.playlists(args)
  elseif operation == "playlistSongs" then
    local playlist_id = (type(args) == "table" and (args.id or args.playlistId or args.playlist_id)) or tostring(args or "")
    local limit = type(args) == "table" and (tonumber(args.limit) or 50) or 50
    local offset = type(args) == "table" and (tonumber(args.offset) or 0) or 0
    return catalog.playlist_songs(playlist_id, limit, offset)
  elseif operation == "lyrics" then
    local song_id = args.id or args.songId or ""
    return lyrics.get_lyrics(song_id)
  elseif operation == "favorites" then
    return catalog.favorites(args)
  elseif operation == "setFavorite" then
    return catalog.set_favorite(args)
  elseif operation == "album" then
    local album_id = args.id or args.albumId or ""
    return catalog.album(album_id)
  elseif operation == "albumSongs" then
    local album_id = args.id or args.albumId or ""
    local limit = tonumber(args.limit) or 50
    local offset = tonumber(args.offset) or 0
    return catalog.album_songs(album_id, limit, offset)
  elseif operation == "artist" then
    local artist_id = args.id or args.artistId or ""
    return catalog.artist(artist_id)
  elseif operation == "artistSongs" then
    local artist_id = args.id or args.artistId or ""
    local limit = tonumber(args.limit) or 50
    local offset = tonumber(args.offset) or 0
    return catalog.artist_songs(artist_id, limit, offset)
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
