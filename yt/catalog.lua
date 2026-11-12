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
  local seen_playlists = {}

  local top_artist_name = query
  local top_artist_id = ""
  local top_artist_avatar = ""

  local payload = {
    query = query
  }
  local data, err = client.post_music("search", payload, config.CLIENT_WEB_REMIX)

  if data then
    -- 1. 查找置顶卡片（musicCardShelfRenderer）提取权威主创艺术家
    local contents = data.contents
    local tabs = contents and contents.tabbedSearchResultsRenderer and contents.tabbedSearchResultsRenderer.tabs
    local first_tab = tabs and tabs[1] and tabs[1].tabRenderer
    local sections = first_tab and first_tab.content and first_tab.content.sectionListRenderer and first_tab.content.sectionListRenderer.contents or {}

    for _, sec in ipairs(sections) do
      if sec.musicCardShelfRenderer then
        local shelf = sec.musicCardShelfRenderer
        local t_obj = shelf.title
        if t_obj and t_obj.runs and #t_obj.runs > 0 then
          top_artist_name = t_obj.runs[1].text or top_artist_name
          local nav = t_obj.runs[1].navigationEndpoint
          if nav and nav.browseEndpoint and nav.browseEndpoint.browseId then
            top_artist_id = nav.browseEndpoint.browseId
          end
        end
        local th = shelf.thumbnail and shelf.thumbnail.musicThumbnailRenderer and shelf.thumbnail.musicThumbnailRenderer.thumbnail and shelf.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails
        if th and #th > 0 then
          top_artist_avatar = th[#th].url or ""
        end
      end
    end

    if string.len(top_artist_id) > 0 and not seen_artists[top_artist_id] then
      seen_artists[top_artist_id] = true
      table.insert(artists, {
        id = top_artist_id,
        name = top_artist_name,
        coverUrl = top_artist_avatar,
        albumCount = 0
      })
    end

    -- 2. 递归收集所有音乐卡片条目
    local music_items = {}
    find_music_items(data, music_items)

    for _, it in ipairs(music_items) do
      local cols = it.flexColumns or {}
      local title = ""
      if cols[1] and cols[1].musicResponsiveListItemFlexColumnRenderer then
        title = extract_text(cols[1].musicResponsiveListItemFlexColumnRenderer.text)
      end

      -- 遍历所有的 flexColumns 提取文本块
      local all_runs = {}
      for c_idx = 2, #cols do
        local col_rend = cols[c_idx].musicResponsiveListItemFlexColumnRenderer
        if col_rend and col_rend.text and col_rend.text.runs then
          for _, r in ipairs(col_rend.text.runs) do
            table.insert(all_runs, r)
          end
        end
      end

      local dur_ms = 0
      local artist_name = nil
      local year = 0

      for _, r in ipairs(all_runs) do
        local t = r.text or ""
        -- 精确识别时长，如 "4:48", "03:28"
        local min, sec_part = string.match(t, "^%s*(%d+):(%d+)%s*$")
        if not min then
          min, sec_part = string.match(t, "(%d+):(%d+)")
        end
        if min and sec_part then
          dur_ms = ((tonumber(min) or 0) * 60 + (tonumber(sec_part) or 0)) * 1000
        end

        local y = string.match(t, "(%d%d%d%d)年?")
        if y then
          year = tonumber(y) or 0
        end
      end

      -- 提取歌手名字（排除时长、数字、符号、类型标签）
      for _, r in ipairs(all_runs) do
        local t = r.text or ""
        local trimmed = string.gsub(t, "^%s*(.-)%s*$", "%1")
        local is_time = string.find(trimmed, ":") ~= nil
        local is_tag = (trimmed == "歌曲" or trimmed == "视频" or trimmed == "专辑" or trimmed == "播放列表" or trimmed == "单曲" or trimmed == "个人资料" or trimmed == "音乐人" or trimmed == "•" or trimmed == "·" or trimmed == "")
        local is_num = string.match(trimmed, "^%d+$") ~= nil
        local is_stat = string.find(trimmed, "播放") or string.find(trimmed, "观看") or string.find(trimmed, "听众") or string.find(trimmed, "订阅") or string.find(trimmed, "次")

        if not is_time and not is_tag and not is_num and not is_stat then
          artist_name = trimmed
          break
        end
      end

      if not artist_name or string.len(artist_name) == 0 then
        artist_name = top_artist_name
      end

      -- 提取最高清封面
      local cover_url = ""
      if it.thumbnail and it.thumbnail.musicThumbnailRenderer then
        local th_obj = it.thumbnail.musicThumbnailRenderer.thumbnail
        cover_url = extract_thumbnail(th_obj and th_obj.thumbnails)
      end

      -- 提取 videoId (歌曲)
      local vid = it.playlistItemData and it.playlistItemData.videoId
      if (not vid or string.len(vid) ~= 11) and it.overlay and it.overlay.musicItemThumbnailOverlayRenderer then
        local c = it.overlay.musicItemThumbnailOverlayRenderer.content
        if c and c.musicPlayButtonRenderer and c.musicPlayButtonRenderer.playNavigationEndpoint then
          local we = c.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint
          if we and we.videoId then vid = we.videoId end
        end
      end

      -- 提取 navigation 页面类型 (专辑/歌手/歌单)
      local nav = it.navigationEndpoint
      local browse_id = nav and nav.browseEndpoint and nav.browseEndpoint.browseId
      local page_type = nav and nav.browseEndpoint and nav.browseEndpoint.browseEndpointContextSupportedConfigs and nav.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig and nav.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType

      if vid and string.len(vid) == 11 and not seen_songs[vid] then
        seen_songs[vid] = true
        if string.len(cover_url) == 0 then
          cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
        end
        table.insert(songs, {
          id = vid,
          title = string.len(title) > 0 and title or ("Song " .. vid),
          artists = {
            { id = "yt_artist_" .. vid, name = artist_name, coverUrl = "" }
          },
          albumName = "YouTube Music",
          coverUrl = cover_url,
          durationMs = dur_ms
        })
      elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" and browse_id and not seen_albums[browse_id] then
        seen_albums[browse_id] = true
        table.insert(albums, {
          id = browse_id,
          title = title,
          artists = {
            { id = "yt_artist_" .. browse_id, name = artist_name, coverUrl = "" }
          },
          coverUrl = cover_url,
          year = year,
          songCount = 0
        })
      elseif (page_type == "MUSIC_PAGE_TYPE_ARTIST" or page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL") and browse_id and not seen_artists[browse_id] then
        seen_artists[browse_id] = true
        table.insert(artists, {
          id = browse_id,
          name = title,
          coverUrl = cover_url,
          albumCount = 0
        })
      elseif page_type == "MUSIC_PAGE_TYPE_PLAYLIST" and browse_id and not seen_playlists[browse_id] then
        seen_playlists[browse_id] = true
        table.insert(playlists, {
          id = browse_id,
          name = title,
          coverUrl = cover_url,
          owner = artist_name,
          songCount = 0
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

return catalog
