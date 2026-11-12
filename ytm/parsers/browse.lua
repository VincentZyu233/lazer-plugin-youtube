local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")

local browse_parser = {}

--- 解析 player 响应中的 videoDetails 为 Song 基础元数据
function browse_parser.parse_song_details(res, vid)
  local vd = (res and res.videoDetails) or {}
  local dur_s = tonumber(vd.lengthSeconds) or 0
  local title = (vd.title and string.len(vd.title) > 0) and vd.title or ("YouTube Song (" .. vid .. ")")
  local author = (vd.author and string.len(vd.author) > 0) and vd.author or "YouTube Music"

  local cover_url = ""
  if vd.thumbnail and vd.thumbnail.thumbnails and #vd.thumbnail.thumbnails > 0 then
    cover_url = nav.extract_thumbnail(vd.thumbnail.thumbnails)
  end
  if string.len(cover_url) == 0 then
    cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
  end

  return {
    id = vid,
    title = title,
    artists = {
      { id = "yt_artist_" .. vid, name = author, coverUrl = "" }
    },
    albumName = "YouTube Music",
    coverUrl = cover_url,
    durationMs = dur_s * 1000
  }
end

--- 解析喜欢/收藏列表 (VLLM)
function browse_parser.parse_favorites(data)
  if not data or type(data) ~= "table" then
    return {}
  end

  local music_items = {}
  nav.find_music_items(data, music_items)

  local songs = {}
  local seen_songs = {}

  for _, it in ipairs(music_items) do
    local s = search_parser.parse_song_item(it, nil, seen_songs)
    if s then
      s.starred = true
      table.insert(songs, s)
    end
  end

  return songs
end

return browse_parser
