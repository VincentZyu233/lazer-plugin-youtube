local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")
local browse_parser = require("ytm.parsers.browse")

local catalog_service = {}

--- 综合搜索业务
function catalog_service.search(args)
  local query = ""
  local requested_limit = 20
  if type(args) == "string" then
    query = args
  elseif type(args) == "table" then
    query = args.query or args.keyword or ""
    if args.limit then
      requested_limit = tonumber(args.limit) or 20
    end
  end

  query = nav.trim_str(query)
  if string.len(query) == 0 then
    return { songs = {}, albums = {}, artists = {}, playlists = {} }
  end

  transport.ensure_visitor_data()

  local payload = {
    query = query
  }

  local data = transport.post_music("search", payload, constants.CLIENT_WEB_REMIX)
  local results = search_parser.parse_search_results(data, query)

  -- 若单曲不足且未满足请求量，发起歌曲过滤搜索作为补充
  -- 若已有足够单曲（例如榜单匹配只需 8 条），直接返回，避免冗余发起二次请求
  if #results.songs < requested_limit and #results.songs < 10 then
    local payload_songs = {
      query = query,
      params = "EgWKAQIIAWoOEAUQCRADEAQQChAVEBA%3D"
    }
    local data_songs = transport.post_music("search", payload_songs, constants.CLIENT_WEB_REMIX)
    if data_songs then
      local song_items = {}
      nav.find_music_items(data_songs, song_items)
      local seen_songs = {}
      for _, s in ipairs(results.songs) do
        seen_songs[s.id] = true
      end
      for _, it in ipairs(song_items) do
        local s = search_parser.parse_song_item(it, query, seen_songs)
        if s then
          table.insert(results.songs, s)
        end
      end
    end
  end

  return results
end

--- 单曲详情业务
function catalog_service.song(id)
  local vid = tostring(id or "")
  if string.len(vid) == 0 then
    error("Invalid song id", 0)
  end

  transport.ensure_visitor_data()

  local payload = {
    videoId = vid,
    playbackContext = {
      contentPlaybackContext = {
        html5Preference = "HTML5_PREF_WANTS"
      }
    }
  }

  local res = transport.post_youtube("player?prettyPrint=false", payload, constants.CLIENT_VISIONOS)
  return browse_parser.parse_song_details(res, vid)
end

--- 歌单详情业务 (对齐 Lazer MusicPlaylist 契约)
function catalog_service.playlist(playlist_id)
  local pid = tostring(playlist_id or "")
  if string.len(pid) == 0 then return nil end

  local clean_id = string.match(pid, "([a-zA-Z0-9_-]+)$") or pid
  local b_id = clean_id
  if string.sub(b_id, 1, 2) ~= "VL" and string.sub(b_id, 1, 2) ~= "PL" and string.sub(b_id, 1, 4) ~= "RDCL" then
    b_id = "VL" .. b_id
  end

  transport.ensure_visitor_data()
  local data = transport.post_music("browse", { browseId = b_id }, constants.CLIENT_WEB_REMIX)
  return browse_parser.parse_playlist_header(data, pid)
end

--- 歌单歌曲分页业务 (对齐 Lazer List<MusicSong> 契约)
function catalog_service.playlist_songs(playlist_id, limit, offset)
  local pid = tostring(playlist_id or "")
  if string.len(pid) == 0 then return {} end

  local clean_id = string.match(pid, "([a-zA-Z0-9_-]+)$") or pid
  local b_id = clean_id
  if string.sub(b_id, 1, 2) ~= "VL" and string.sub(b_id, 1, 2) ~= "PL" and string.sub(b_id, 1, 4) ~= "RDCL" then
    b_id = "VL" .. b_id
  end

  transport.ensure_visitor_data()
  local data = transport.post_music("browse", { browseId = b_id }, constants.CLIENT_WEB_REMIX)
  if not data then return {} end

  local songs = browse_parser.parse_playlist_songs(data)
  local take = tonumber(limit) or 50
  local skip = tonumber(offset) or 0

  local paged = {}
  for i = skip + 1, math.min(#songs, skip + take) do
    table.insert(paged, songs[i])
  end

  return paged
end

--- 我喜欢的音乐 (VLLM)
function catalog_service.favorites(args)
  local cookie = store.get_cookie()
  if not cookie or string.len(cookie) == 0 then
    return {}
  end

  local payload = {
    browseId = "VLLM"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  return browse_parser.parse_favorites(data)
end

return catalog_service
