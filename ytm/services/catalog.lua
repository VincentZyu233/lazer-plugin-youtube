local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")
local browse_parser = require("ytm.parsers.browse")

local catalog_service = {}

-- 内存搜索缓存 (LRU / FIFO 限制 100 条)，消除榜单重复查询与二次匹配延迟
local search_cache = {}
local search_cache_keys = {}
local MAX_SEARCH_CACHE = 100

local function get_cached_search(key)
  return search_cache[key]
end

local function set_cached_search(key, val)
  if not search_cache[key] then
    table.insert(search_cache_keys, key)
    if #search_cache_keys > MAX_SEARCH_CACHE then
      local oldest = table.remove(search_cache_keys, 1)
      search_cache[oldest] = nil
    end
  end
  search_cache[key] = val
end

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

  local cache_key = query .. "::" .. tostring(requested_limit)
  local cached = get_cached_search(cache_key)
  if cached then
    return cached
  end

  transport.ensure_visitor_data()

  local payload = {
    query = query
  }

  local data = transport.post_music("search", payload, constants.CLIENT_WEB_REMIX)
  local results = search_parser.parse_search_results(data, query)

  -- 若单曲不足且未满足请求量，发起歌曲过滤搜索作为补充。
  -- 关键优化：当 requested_limit <= 8 时 (如 Lazer 榜单自动匹配批量并发场景)，
  -- 只要返回了歌曲或者榜单匹配，严禁发起二次 HTTP 请求，防止串行队列耗时累加突破 Dart 5.0 秒超时！
  if requested_limit > 8 and #results.songs < requested_limit and #results.songs < 10 then
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

  set_cached_search(cache_key, results)
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
  local ok, data = pcall(transport.post_music, "browse", { browseId = b_id }, constants.CLIENT_WEB_REMIX)
  if not ok or not data then
    return {
      id = pid,
      name = "Playlist",
      description = "",
      coverUrl = "",
      songCount = 0,
      owner = "YouTube Music"
    }
  end

  local pl = browse_parser.parse_playlist_header(data, pid)

  -- 若歌单无独立大图，自动继承首曲高清封面，详情页唱片质感立现
  if pl and (not pl.coverUrl or pl.coverUrl == "") then
    local songs = browse_parser.parse_playlist_songs(data)
    if songs and #songs > 0 and songs[1].coverUrl and string.len(songs[1].coverUrl) > 0 then
      pl.coverUrl = songs[1].coverUrl
    end
  end

  return pl
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
  local ok, data = pcall(transport.post_music, "browse", { browseId = b_id }, constants.CLIENT_WEB_REMIX)
  if not ok or not data then return {} end

  local songs = browse_parser.parse_playlist_songs(data)
  local take = tonumber(limit) or 50
  local skip = tonumber(offset) or 0

  local paged = {}
  for i = skip + 1, math.min(#songs, skip + take) do
    table.insert(paged, songs[i])
  end

  return paged
end

local cached_favs = nil
local cached_favs_time = 0

--- 专辑详情业务
function catalog_service.album(album_id)
  local aid = tostring(album_id or "")
  if string.len(aid) == 0 then return nil end

  transport.ensure_visitor_data()
  local ok, data = pcall(transport.post_music, "browse", { browseId = aid }, constants.CLIENT_WEB_REMIX)
  if not ok or not data then return nil end

  local header = browse_parser.parse_playlist_header(data, aid)
  local songs = browse_parser.parse_playlist_songs(data)
  return {
    id = aid,
    title = header and header.name or "Album",
    name = header and header.name or "Album",
    coverUrl = header and header.coverUrl or (songs[1] and songs[1].coverUrl or ""),
    artists = { { id = "yt_artist_unk", name = header and header.owner or "YouTube Music" } },
    songCount = songs and #songs or 0,
    description = header and header.description or ""
  }
end

--- 专辑歌曲列表业务
function catalog_service.album_songs(album_id, limit, offset)
  return catalog_service.playlist_songs(album_id, limit, offset)
end

--- 歌手详情业务
function catalog_service.artist(artist_id)
  local aid = tostring(artist_id or "")
  if string.len(aid) == 0 then return nil end

  transport.ensure_visitor_data()
  local ok, data = pcall(transport.post_music, "browse", { browseId = aid }, constants.CLIENT_WEB_REMIX)
  if not ok or not data then return nil end

  local hdr = nav.nav(data, { "header", "musicImmersiveHeaderRenderer" })
           or nav.nav(data, { "header", "musicVisualHeaderRenderer" })
           or {}
  local name = nav.nav(hdr, { "title", "runs", 1, "text" }) or "Artist"
  local desc = nav.nav(hdr, { "description", "runs", 1, "text" }) or ""
  local cover_url = ""
  local thumbs = nav.nav(hdr, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
  if thumbs then cover_url = nav.extract_thumbnail(thumbs) end

  return {
    id = aid,
    name = name,
    coverUrl = cover_url,
    description = desc,
    albumCount = 0
  }
end

--- 歌手热门歌曲列表业务
function catalog_service.artist_songs(artist_id, limit, offset)
  return catalog_service.playlist_songs(artist_id, limit, offset)
end

--- 我喜欢的音乐 (VLLM)
function catalog_service.favorites(args)
  local cookie = store.get_cookie()
  if not cookie or string.len(cookie) == 0 then
    return {}
  end

  local limit = 100
  local offset = 0
  if type(args) == "table" then
    limit = tonumber(args.limit) or 100
    offset = tonumber(args.offset) or 0
  end

  local now = os.time()
  -- 若缓存为空，或超过 60 秒且是第 1 页请求，重新全量同步
  if not cached_favs or (now - cached_favs_time > 60 and offset == 0) then
    local payload = {
      browseId = "VLLM"
    }
    local ok, data = pcall(transport.post_music, "browse", payload, constants.CLIENT_WEB_REMIX)
    if ok and data then
      local songs, next_token = browse_parser.parse_favorites(data)
      local all_songs = songs or {}
      local seen = {}
      for _, s in ipairs(all_songs) do seen[s.id] = true end

      -- 遍历 continuation tokens，拉取 100 首以后的全部收藏曲目
      local loop_count = 0
      while next_token and loop_count < 15 do
        loop_count = loop_count + 1
        local cont_payload = { continuation = next_token }
        local c_ok, c_data = pcall(transport.post_music, "browse", cont_payload, constants.CLIENT_WEB_REMIX)
        if c_ok and c_data then
          local more_songs, new_token = browse_parser.parse_continuation_songs(c_data, seen)
          if more_songs and #more_songs > 0 then
            for _, s in ipairs(more_songs) do
              table.insert(all_songs, s)
            end
          else
            break
          end
          next_token = new_token
        else
          break
        end
      end

      cached_favs = all_songs
      cached_favs_time = now
    end
  end

  cached_favs = cached_favs or {}

  local paged = {}
  for i = offset + 1, math.min(#cached_favs, offset + limit) do
    table.insert(paged, cached_favs[i])
  end

  return paged
end

--- 收藏/取消收藏单曲 (setFavorite)
function catalog_service.set_favorite(args)
  local cookie = store.get_cookie()
  if not cookie or string.len(cookie) == 0 then
    return false
  end

  local vid = ""
  local favorite = true
  if type(args) == "table" then
    vid = tostring(args.id or args.songId or "")
    if args.favorite ~= nil then
      favorite = (args.favorite == true or args.favorite == "true" or args.favorite == 1)
    end
  end

  if string.len(vid) == 0 then
    return false
  end

  local endpoint = favorite and "like/like" or "like/removelike"
  local payload = {
    target = {
      videoId = vid
    }
  }

  local ok, res = pcall(transport.post_music, endpoint, payload, constants.CLIENT_WEB_REMIX)

  -- 立即联动更新内存中的收藏列表缓存
  if cached_favs then
    if favorite then
      local exists = false
      for _, s in ipairs(cached_favs) do
        if s.id == vid then
          exists = true
          break
        end
      end
      if not exists then
        local s_info = catalog_service.song(vid)
        if s_info then
          s_info.starred = true
          table.insert(cached_favs, 1, s_info)
        else
          table.insert(cached_favs, 1, {
            id = vid,
            title = "Liked Song",
            artists = { { id = "yt_artist_unk", name = "YouTube Music" } },
            durationMs = 0,
            coverUrl = "",
            starred = true
          })
        end
      end
    else
      for i, s in ipairs(cached_favs) do
        if s.id == vid then
          table.remove(cached_favs, i)
          break
        end
      end
    end
  end

  return ok and res ~= nil
end

return catalog_service
