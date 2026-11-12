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

  -- 特性 1：如果输入的是直接视频 ID 或 URL，直接包装为单曲返回
  local direct_id = try_extract_video_id(query)
  if direct_id then
    return {
      songs = {
        {
          id = direct_id,
          title = "YouTube Video (" .. direct_id .. ")",
          artists = { { id = "yt_channel", name = "YouTube", coverUrl = "" } },
          albumName = "YouTube Audio",
          coverUrl = "https://i.ytimg.com/vi/" .. direct_id .. "/hqdefault.jpg",
          durationMs = 0
        }
      },
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

  local top_artist_name = "YouTube Music"
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

      local col1_runs = (cols[2] and cols[2].musicResponsiveListItemFlexColumnRenderer and cols[2].musicResponsiveListItemFlexColumnRenderer.text and cols[2].musicResponsiveListItemFlexColumnRenderer.text.runs) or {}

      local dur_ms = 0
      local artist_name = top_artist_name
      local year = 0

      for _, r in ipairs(col1_runs) do
        local t = r.text or ""
        local min, sec_part = string.match(t, "(%d+):(%d+)")
        if min and sec_part then
          dur_ms = ((tonumber(min) or 0) * 60 + (tonumber(sec_part) or 0)) * 1000
        end
        local y = string.match(t, "(%d%d%d%d)年?")
        if y then
          year = tonumber(y) or 0
        end
      end

      -- 提取歌手名字候选
      for _, r in ipairs(col1_runs) do
        local t = r.text or ""
        local is_skip = (t == "歌曲" or t == "视频" or t == "专辑" or t == "播放列表" or t == "单曲" or t == "个人资料" or t == "音乐人" or t == " • " or t == "•")
        if not is_skip and not string.match(t, "%d+:%d+") and not string.find(t, "观看") and not string.find(t, "听众") and not string.find(t, "订阅者") and not string.match(t, "^%d%d%d%d") then
          artist_name = t
          break
        end
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

function catalog.song(id)
  return {
    id = id,
    title = "YouTube Video (" .. tostring(id) .. ")",
    artists = { { id = "yt_channel", name = "YouTube", coverUrl = "" } },
    albumName = "YouTube Audio",
    coverUrl = "https://i.ytimg.com/vi/" .. tostring(id) .. "/hqdefault.jpg",
    durationMs = 0
  }
end

return catalog
