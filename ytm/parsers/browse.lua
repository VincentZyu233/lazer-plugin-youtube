local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")

local browse_parser = {}

--- 针对缺失官方独立封面的专属系统合集（如重放/发现/归档/超级混音），匹配高颜值语义徽标
function browse_parser.resolve_curated_mix_cover(title, original_thumb)
  if original_thumb and string.len(original_thumb) > 0 then
    return original_thumb
  end
  local t_lower = string.lower(title or "")
  if string.find(t_lower, "归档") or string.find(t_lower, "archive") then
    return "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_archive_mix.png"
  elseif string.find(t_lower, "重放") or string.find(t_lower, "replay") then
    return "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_replay_mix.png"
  elseif string.find(t_lower, "发现") or string.find(t_lower, "discover") then
    return "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_discover_mix.png"
  elseif string.find(t_lower, "超级") or string.find(t_lower, "supermix") then
    return "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_supermix.png"
  end
  return original_thumb or ""
end

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

--- 解析首页 FEmusic_home 推荐流，对齐 Lazer MusicHome 数据契约
function browse_parser.parse_home_feed(data)
  local feed = {
    quick = {},
    daily = {},
    recommended = {},
    playlists = {},
    albums = {},
    editorialPlaylists = {}
  }
  if not data or type(data) ~= "table" then return feed end

  local tabs = nav.nav(data, { "contents", "singleColumnBrowseResultsRenderer", "tabs" }) or {}
  local sec_list = nav.nav(tabs, { 1, "tabRenderer", "content", "sectionListRenderer", "contents" }) or {}

  local seen_pl = {}
  local seen_alb = {}
  local seen_songs = {}

  for _, sec in ipairs(sec_list) do
    local carousel = sec.musicCarouselShelfRenderer
    if carousel and carousel.contents then
      for _, it in ipairs(carousel.contents) do
        -- 1. 歌单与专辑双行卡片 (musicTwoRowItemRenderer)
        local r = it.musicTwoRowItemRenderer
        if r then
          local title = nav.extract_text(r.title)
          local sub = nav.extract_text(r.subtitle)
          local endpoint = nav.nav(r, { "navigationEndpoint", "browseEndpoint" }) or {}
          local b_id = endpoint.browseId
          local page_type = nav.nav(endpoint, {
            "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig",
            "pageType"
          })
          local thumb = ""
          local thumbs = nav.nav(r, { "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
          if thumbs then thumb = nav.extract_thumbnail(thumbs) end
          thumb = browse_parser.resolve_curated_mix_cover(title, thumb)

          if b_id and string.len(title) > 0 then
            local is_playlist = (page_type == "MUSIC_PAGE_TYPE_PLAYLIST")
                             or (string.sub(b_id, 1, 2) == "VL")
                             or (string.sub(b_id, 1, 2) == "PL")
                             or (string.sub(b_id, 1, 4) == "RDCL")

            local is_album = (page_type == "MUSIC_PAGE_TYPE_ALBUM")
                          or (string.sub(b_id, 1, 4) == "MPRE")

            if is_playlist then
              if not seen_pl[b_id] then
                seen_pl[b_id] = true
                local pl = {
                  id = b_id,
                  name = title,
                  description = sub,
                  coverUrl = thumb,
                  songCount = 0,
                  owner = "YouTube Music"
                }
                table.insert(feed.recommended, pl)
                table.insert(feed.playlists, pl)
                table.insert(feed.editorialPlaylists, pl)
              end
            elseif is_album then
              if not seen_alb[b_id] then
                seen_alb[b_id] = true
                local alb = {
                  id = b_id,
                  name = title,
                  artist = sub,
                  coverUrl = thumb
                }
                table.insert(feed.albums, alb)
              end
            end
          end
        end

        -- 2. 直接展示的单曲卡片 (musicResponsiveListItemRenderer)
        local resp = it.musicResponsiveListItemRenderer
        if resp then
          local s = search_parser.parse_song_item(resp, nil, seen_songs)
          if s then
            table.insert(feed.quick, s)
            table.insert(feed.daily, s)
          end
        end
      end
    end
  end

  return feed
end

--- 解析 FEmusic_charts 为榜单歌单列表
function browse_parser.parse_charts(data)
  local charts = {}
  if not data or type(data) ~= "table" then return charts end

  local tabs = nav.nav(data, { "contents", "singleColumnBrowseResultsRenderer", "tabs" }) or {}
  local sec_list = nav.nav(tabs, { 1, "tabRenderer", "content", "sectionListRenderer", "contents" }) or {}

  local seen_charts = {}
  for _, sec in ipairs(sec_list) do
    local carousel = sec.musicCarouselShelfRenderer
    if carousel and carousel.contents then
      for _, it in ipairs(carousel.contents) do
        local r = it.musicTwoRowItemRenderer
        if r then
          local title = nav.extract_text(r.title)
          local sub = nav.extract_text(r.subtitle)
          local endpoint = nav.nav(r, { "navigationEndpoint", "browseEndpoint" }) or {}
          local b_id = endpoint.browseId
          local thumb = ""
          local thumbs = nav.nav(r, { "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
          if thumbs then thumb = nav.extract_thumbnail(thumbs) end
          thumb = browse_parser.resolve_curated_mix_cover(title, thumb)

          if b_id and string.len(title) > 0 and not seen_charts[b_id] then
            seen_charts[b_id] = true
            table.insert(charts, {
              id = b_id,
              name = title,
              description = sub,
              coverUrl = thumb,
              songCount = 0,
              owner = "YouTube Charts"
            })
          end
        end
      end
    end
  end

  return charts
end

--- 解析歌单详情元数据 (Header)
function browse_parser.parse_playlist_header(data, playlist_id)
  if not data or type(data) ~= "table" then
    return {
      id = playlist_id,
      name = "YouTube Playlist",
      description = "",
      coverUrl = "",
      songCount = 0,
      owner = "YouTube Music"
    }
  end

  local hdr = nil
  -- 尝试从 twoColumnBrowseResultsRenderer 提取 header
  local two_col = nav.nav(data, { "contents", "twoColumnBrowseResultsRenderer" })
  if two_col then
    local tabs = two_col.tabs or {}
    local tab_sec = nav.nav(tabs, { 1, "tabRenderer", "content", "sectionListRenderer", "contents" }) or {}
    for _, s in ipairs(tab_sec) do
      if s.musicResponsiveHeaderRenderer then
        hdr = s.musicResponsiveHeaderRenderer
        break
      end
    end
  end

  -- 回退至顶级 header
  if not hdr and data.header then
    hdr = data.header.musicDetailHeaderRenderer
       or data.header.musicResponsiveHeaderRenderer
       or nav.nav(data.header, { "musicEditablePlaylistDetailHeaderRenderer", "header", "musicDetailHeaderRenderer" })
  end

  local name = (hdr and nav.extract_text(hdr.title)) or "YouTube Playlist"
  local desc = ""
  if hdr and hdr.description then
    desc = nav.extract_text(hdr.description)
    if string.len(desc) == 0 and hdr.description.musicDescriptionShelfRenderer then
      desc = nav.extract_text(hdr.description.musicDescriptionShelfRenderer.description)
    end
  end

  local owner = "YouTube Music"
  if hdr and hdr.subtitle then
    local sub_text = nav.extract_text(hdr.subtitle)
    if string.len(sub_text) > 0 then owner = sub_text end
  end

  local song_count = 0
  if hdr and hdr.secondSubtitle then
    local sec_sub = nav.extract_text(hdr.secondSubtitle)
    local cnt_str = string.match(sec_sub, "(%d+)")
    if cnt_str then song_count = tonumber(cnt_str) or 0 end
  end

  local cover_url = ""
  local thumbs = hdr and nav.nav(hdr, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
  if thumbs then cover_url = nav.extract_thumbnail(thumbs) end
  cover_url = browse_parser.resolve_curated_mix_cover(name, cover_url)

  return {
    id = playlist_id,
    name = name,
    description = desc,
    coverUrl = cover_url,
    songCount = song_count,
    owner = owner
  }
end

--- 解析歌单中的曲目列表
function browse_parser.parse_playlist_songs(data)
  local songs = {}
  if not data or type(data) ~= "table" then return songs end

  local music_items = {}
  -- 优先从 twoColumnBrowseResultsRenderer 的 secondaryContents 提取
  local two_col = nav.nav(data, { "contents", "twoColumnBrowseResultsRenderer" })
  if two_col and two_col.secondaryContents then
    local sec_list = nav.nav(two_col, { "secondaryContents", "sectionListRenderer", "contents" }) or {}
    for _, s in ipairs(sec_list) do
      local pl_shelf = s.musicPlaylistShelfRenderer or s.musicShelfRenderer
      if pl_shelf and pl_shelf.contents then
        for _, it in ipairs(pl_shelf.contents) do
          if it.musicResponsiveListItemRenderer then
            table.insert(music_items, it.musicResponsiveListItemRenderer)
          end
        end
      end
    end
  end

  -- 回退至全局递归寻找
  if #music_items == 0 then
    nav.find_music_items(data, music_items)
  end

  local seen_songs = {}
  for _, it in ipairs(music_items) do
    local s = search_parser.parse_song_item(it, nil, seen_songs)
    if s then table.insert(songs, s) end
  end

  return songs
end

return browse_parser
