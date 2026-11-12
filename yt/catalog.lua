local client = require("yt.client")
local config = require("yt.config")
local catalog = {}

local function extract_text(obj)
  if not obj then return "" end
  if type(obj) == "string" then return obj end
  if obj.simpleText then return obj.simpleText end
  if obj.runs and type(obj.runs) == "table" then
    local parts = {}
    for _, r in ipairs(obj.runs) do
      if r.text then
        table.insert(parts, r.text)
      end
    end
    return table.concat(parts, "")
  end
  return ""
end

local function extract_thumbnail(thumbnails)
  if not thumbnails or type(thumbnails) ~= "table" then
    return ""
  end
  local best_url = ""
  local max_w = 0
  for _, item in ipairs(thumbnails) do
    local w = item.width or 0
    if w >= max_w and item.url then
      max_w = w
      best_url = item.url
    end
  end
  return best_url
end

--- 纯字符串安全去除首尾空白，不依赖正则引擎（兼容 Dart lua_dardo_plus 虚拟机）
local function trim_str(s)
  if not s or type(s) ~= "string" then return "" end
  local len = string.len(s)
  local i = 1
  local j = len
  while i <= j and string.byte(s, i) <= 32 do
    i = i + 1
  end
  while j >= i and string.byte(s, j) <= 32 do
    j = j - 1
  end
  if i > j then return "" end
  return string.sub(s, i, j)
end

--- 纯字符串安全解析时长为毫秒数（支持 "4:48", "03:25", "1:05:20"）
-- 完全避免使用 Lua 正则捕获组，杜绝 Dart RegExp 转换与捕获组截断问题
local function parse_time_to_ms(str)
  if not str or type(str) ~= "string" then return 0 end
  local colon1 = string.find(str, ":", 1, true)
  if not colon1 then return 0 end

  local parts = {}
  local start_pos = 1
  while true do
    local c_pos = string.find(str, ":", start_pos, true)
    if not c_pos then
      table.insert(parts, string.sub(str, start_pos))
      break
    end
    table.insert(parts, string.sub(str, start_pos, c_pos - 1))
    start_pos = c_pos + 1
  end

  local nums = {}
  for _, p in ipairs(parts) do
    local clean = ""
    for idx = 1, string.len(p) do
      local b = string.byte(p, idx)
      if b >= 48 and b <= 57 then
        clean = clean .. string.char(b)
      end
    end
    if string.len(clean) == 0 then return 0 end
    table.insert(nums, tonumber(clean) or 0)
  end

  if #nums == 2 then
    return (nums[1] * 60 + nums[2]) * 1000
  elseif #nums == 3 then
    return (nums[1] * 3600 + nums[2] * 60 + nums[3]) * 1000
  end
  return 0
end

local function try_extract_video_id(input)
  if not input or type(input) ~= "string" then return nil end
  local id = string.match(input, "youtu%.be/([%w%-_]+)")
  if id and string.len(id) == 11 then return id end

  id = string.match(input, "[%?&]v=([%w%-_]+)")
  if id and string.len(id) == 11 then return id end

  if string.len(input) == 11 and string.match(input, "^[%w%-_]+$") then
    return input
  end
  return nil
end

--- 递归寻找所有 musicResponsiveListItemRenderer
local function find_music_items(node, list)
  if not node or type(node) ~= "table" then return end
  if node.musicResponsiveListItemRenderer then
    table.insert(list, node.musicResponsiveListItemRenderer)
    return
  end
  for _, v in pairs(node) do
    if type(v) == "table" then
      find_music_items(v, list)
    end
  end
end

function catalog.search(args)
  local query = tostring(args and args.query or "")
  if string.len(query) == 0 then
    return { songs = {}, albums = {}, artists = {}, playlists = {} }
  end

  local direct_id = try_extract_video_id(query)
  if direct_id then
    return {
      songs = { catalog.song(direct_id) },
      albums = {},
      artists = {},
      playlists = {}
    }
  end

  local songs = {}
  local albums = {}
  local artists = {}
  local playlists = {}

  local seen_songs = {}
  local seen_albums = {}
  local seen_artists = {}

  -- 使用 YouTube Music 歌曲过滤参数，获取包含完整歌手、专辑与时长的标准单曲列表
  local payload = {
    query = query,
    params = "EgWKAQIIAWoOEAUQCRADEAQQChAVEBA%3D"
  }
  local data = client.post_music("search", payload, config.CLIENT_WEB_REMIX)

  if data then
    local music_items = {}
    find_music_items(data, music_items)

    for _, it in ipairs(music_items) do
      local vid = it.playlistItemData and it.playlistItemData.videoId
      if (not vid or string.len(vid) ~= 11) and it.overlay and it.overlay.musicItemThumbnailOverlayRenderer then
        local c = it.overlay.musicItemThumbnailOverlayRenderer.content
        if c and c.musicPlayButtonRenderer and c.musicPlayButtonRenderer.playNavigationEndpoint then
          local we = c.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint
          if we and we.videoId then vid = we.videoId end
        end
      end

      if vid and string.len(vid) == 11 and not seen_songs[vid] then
        seen_songs[vid] = true

        local cols = it.flexColumns or {}
        local title = ""
        if cols[1] and cols[1].musicResponsiveListItemFlexColumnRenderer then
          title = extract_text(cols[1].musicResponsiveListItemFlexColumnRenderer.text)
        end
        if string.len(title) == 0 then
          title = "Song " .. vid
        end

        local cover_url = ""
        if it.thumbnail and it.thumbnail.musicThumbnailRenderer then
          local th_obj = it.thumbnail.musicThumbnailRenderer.thumbnail
          cover_url = extract_thumbnail(th_obj and th_obj.thumbnails)
        end
        if string.len(cover_url) == 0 then
          cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
        end

        local song_artists = {}
        local album_name = ""
        local album_id = nil
        local dur_ms = 0

        -- 遍历 flexColumns 提取歌手、专辑、时长
        for c_idx = 2, #cols do
          local col_rend = cols[c_idx].musicResponsiveListItemFlexColumnRenderer
          if col_rend and col_rend.text and col_rend.text.runs then
            for _, r in ipairs(col_rend.text.runs) do
              local t = r.text or ""
              local endpoint = (r.navigationEndpoint and r.navigationEndpoint.browseEndpoint) or {}
              local config_endpoint = endpoint.browseEndpointContextSupportedConfigs and
                                      endpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig
              local page_type = config_endpoint and config_endpoint.pageType
              local b_id = endpoint.browseId

              if page_type == "MUSIC_PAGE_TYPE_ARTIST" or page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL" then
                local trimmed_artist = trim_str(t)
                if string.len(trimmed_artist) > 0 and trimmed_artist ~= "•" and trimmed_artist ~= "·" and trimmed_artist ~= "・" then
                  table.insert(song_artists, {
                    id = b_id or ("yt_artist_" .. vid),
                    name = trimmed_artist,
                    coverUrl = ""
                  })
                  if b_id and not seen_artists[b_id] then
                    seen_artists[b_id] = true
                    table.insert(artists, {
                      id = b_id,
                      name = trimmed_artist,
                      coverUrl = "",
                      albumCount = 0
                    })
                  end
                end
              elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" then
                album_name = trim_str(t)
                album_id = b_id
                if b_id and not seen_albums[b_id] then
                  seen_albums[b_id] = true
                  table.insert(albums, {
                    id = b_id,
                    title = album_name,
                    artists = song_artists,
                    coverUrl = cover_url,
                    year = 0,
                    songCount = 0
                  })
                end
              else
                local ms = parse_time_to_ms(t)
                if ms > 0 then
                  dur_ms = ms
                end
              end
            end
          end
        end

        -- 保底：如果 flexColumns 中未识别到时长，检查 fixedColumns
        if dur_ms == 0 and it.fixedColumns then
          for _, fcol in ipairs(it.fixedColumns) do
            local rend = fcol.musicResponsiveListItemFixedColumnRenderer
            if rend and rend.text and rend.text.runs then
              for _, r in ipairs(rend.text.runs) do
                local ms = parse_time_to_ms(r.text)
                if ms > 0 then
                  dur_ms = ms
                  break
                end
              end
            end
            if dur_ms > 0 then break end
          end
        end

        if #song_artists == 0 then
          table.insert(song_artists, {
            id = "yt_artist_" .. vid,
            name = query,
            coverUrl = ""
          })
        end

        table.insert(songs, {
          id = vid,
          title = title,
          artists = song_artists,
          albumId = album_id,
          albumName = string.len(album_name) > 0 and album_name or "YouTube Music",
          coverUrl = cover_url,
          durationMs = dur_ms
        })
      end
    end
  end

  return {
    songs = songs,
    albums = albums,
    artists = artists,
    playlists = playlists
  }
end

--- 获取单曲真实元数据，包括标题、创作者、时长和封面
function catalog.song(id)
  local vid = tostring(id or "")
  if string.len(vid) == 0 then
    error("Invalid song id", 0)
  end

  client.ensure_visitor_data()

  local payload = {
    videoId = vid,
    playbackContext = {
      contentPlaybackContext = {
        html5Preference = "HTML5_PREF_WANTS"
      }
    }
  }

  local res = client.post_youtube("player?prettyPrint=false", payload, config.CLIENT_VISIONOS)
  local vd = (res and res.videoDetails) or {}
  local dur_s = tonumber(vd.lengthSeconds) or 0
  local title = (vd.title and string.len(vd.title) > 0) and vd.title or ("YouTube Song (" .. vid .. ")")
  local author = (vd.author and string.len(vd.author) > 0) and vd.author or "YouTube Music"

  local cover_url = ""
  if vd.thumbnail and vd.thumbnail.thumbnails and #vd.thumbnail.thumbnails > 0 then
    cover_url = extract_thumbnail(vd.thumbnail.thumbnails)
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

--- 获取我喜欢的音乐（YouTube 赞过的音乐 Liked Music / VLLM）
function catalog.favorites(args)
  local cookie = client.get_cookie()
  if not cookie or string.len(cookie) == 0 then
    return {}
  end

  local payload = {
    browseId = "VLLM"
  }
  local data = client.post_music("browse", payload, config.CLIENT_WEB_REMIX)
  if not data then
    return {}
  end

  local music_items = {}
  find_music_items(data, music_items)

  local songs = {}
  local seen_songs = {}

  for _, it in ipairs(music_items) do
    local vid = it.playlistItemData and it.playlistItemData.videoId
    if (not vid or string.len(vid) ~= 11) and it.overlay and it.overlay.musicItemThumbnailOverlayRenderer then
      local c = it.overlay.musicItemThumbnailOverlayRenderer.content
      if c and c.musicPlayButtonRenderer and c.musicPlayButtonRenderer.playNavigationEndpoint then
        local we = c.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint
        if we and we.videoId then vid = we.videoId end
      end
    end

    if vid and string.len(vid) == 11 and not seen_songs[vid] then
      seen_songs[vid] = true

      local cols = it.flexColumns or {}
      local title = ""
      if cols[1] and cols[1].musicResponsiveListItemFlexColumnRenderer then
        title = extract_text(cols[1].musicResponsiveListItemFlexColumnRenderer.text)
      end
      if string.len(title) == 0 then
        title = "Song " .. vid
      end

      local cover_url = ""
      if it.thumbnail and it.thumbnail.musicThumbnailRenderer then
        local th_obj = it.thumbnail.musicThumbnailRenderer.thumbnail
        cover_url = extract_thumbnail(th_obj and th_obj.thumbnails)
      end
      if string.len(cover_url) == 0 then
        cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
      end

      local song_artists = {}
      local album_name = ""
      local album_id = nil
      local dur_ms = 0

      for c_idx = 2, #cols do
        local col_rend = cols[c_idx].musicResponsiveListItemFlexColumnRenderer
        if col_rend and col_rend.text and col_rend.text.runs then
          for _, r in ipairs(col_rend.text.runs) do
            local t = r.text or ""
            local endpoint = (r.navigationEndpoint and r.navigationEndpoint.browseEndpoint) or {}
            local config_endpoint = endpoint.browseEndpointContextSupportedConfigs and
                                    endpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig
            local page_type = config_endpoint and config_endpoint.pageType
            local b_id = endpoint.browseId

            if page_type == "MUSIC_PAGE_TYPE_ARTIST" or page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL" then
              local trimmed_artist = trim_str(t)
              if string.len(trimmed_artist) > 0 and trimmed_artist ~= "•" and trimmed_artist ~= "·" and trimmed_artist ~= "・" then
                table.insert(song_artists, {
                  id = b_id or ("yt_artist_" .. vid),
                  name = trimmed_artist,
                  coverUrl = ""
                })
              end
            elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" then
              album_name = trim_str(t)
              album_id = b_id
            else
              local ms = parse_time_to_ms(t)
              if ms > 0 then
                dur_ms = ms
              end
            end
          end
        end
      end

      if dur_ms == 0 and it.fixedColumns then
        for _, fcol in ipairs(it.fixedColumns) do
          local rend = fcol.musicResponsiveListItemFixedColumnRenderer
          if rend and rend.text and rend.text.runs then
            for _, r in ipairs(rend.text.runs) do
              local ms = parse_time_to_ms(r.text)
              if ms > 0 then
                dur_ms = ms
                break
              end
            end
          end
          if dur_ms > 0 then break end
        end
      end

      if #song_artists == 0 then
        table.insert(song_artists, {
          id = "yt_artist_" .. vid,
          name = "YouTube Music",
          coverUrl = ""
        })
      end

      table.insert(songs, {
        id = vid,
        title = title,
        artists = song_artists,
        albumId = album_id,
        albumName = string.len(album_name) > 0 and album_name or "YouTube Music",
        coverUrl = cover_url,
        durationMs = dur_ms,
        starred = true
      })
    end
  end

  return songs
end

return catalog
