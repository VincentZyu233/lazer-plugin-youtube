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
  if type(args) == "string" then
    query = args
  elseif type(args) == "table" then
    query = args.query or args.keyword or ""
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

  -- 若综合搜索中的单曲较少，发起歌曲过滤搜索作为强力补充，确保歌曲充足
  if #results.songs < 20 then
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
