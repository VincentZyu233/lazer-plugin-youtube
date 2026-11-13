local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")

local browse_parser = {}

--- 解析 player 响应中的 videoDetails 为 Song 基础元数据
function browse_parser.parse_song_details(res, vid)
  local vd = (res and res.videoDetails) or {}
  local dur_s = tonumber(vd.lengthSeconds) or 0
  local title = (vd.title and string.len(vd.title) > 0) and vd.title or ("YouTube Song (" .. vid .. ")")
  local author = (vd.author and string.len(vd.author) > 0) and vd.author or "YouTube Music"
  local channel_id = (vd.channelId and string.len(vd.channelId) > 0) and vd.channelId or ("yt_artist_" .. vid)

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
      { id = channel_id, name = author, coverUrl = "" }
    },
    albumName = "YouTube Music",
    coverUrl = cover_url,
    durationMs = dur_s * 1000
  }
end

--- 解析喜欢/收藏列表 (VLLM)
function browse_parser.parse_favorites(data)
  if not data or type(data) ~= "table" then
    return {}, nil
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

  -- 提取后续分页 Continuation Token
  local shelf = nav.nav(data, {
    "contents", "twoColumnBrowseResultsRenderer", "secondaryContents",
    "sectionListRenderer", "contents", 1, "musicPlaylistShelfRenderer", "contents"
  }) or nav.nav(data, {
    "contents", "singleColumnBrowseResultsRenderer", "tabs", 1, "tabRenderer",
    "content", "sectionListRenderer", "contents", 1, "musicPlaylistShelfRenderer", "contents"
  }) or {}

  local token = nil
  for _, it in ipairs(shelf) do
    if it.continuationItemRenderer then
      token = nav.nav(it, { "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token" })
      if token then break end
    end
  end

  return songs, token
end

--- 解析 Continuation 增量分页歌曲与下一页 Token
function browse_parser.parse_continuation_songs(data, seen_songs)
  if not data or type(data) ~= "table" then
    return {}, nil
  end

  local items = nav.nav(data, { "onResponseReceivedActions", 1, "appendContinuationItemsAction", "continuationItems" })
             or nav.nav(data, { "continuationContents", "musicPlaylistShelfContinuation", "contents" })
             or {}

  local songs = {}
  local next_token = nil
  seen_songs = seen_songs or {}

  for _, it in ipairs(items) do
    if it.continuationItemRenderer then
      next_token = nav.nav(it, { "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token" })
    else
      local s = search_parser.parse_song_item(it, nil, seen_songs)
      if s then
        s.starred = true
        table.insert(songs, s)
      end
    end
  end

  return songs, next_token
end

--- 解析 Section 列表并填充到 feed 结构中
function browse_parser.parse_home_sections(sec_list, feed, seen_pl, seen_alb, seen_songs)
  if not sec_list or type(sec_list) ~= "table" or not feed then return end
  seen_pl = seen_pl or {}
  seen_alb = seen_alb or {}
  seen_songs = seen_songs or {}

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

          -- 1.1 若带有 browseEndpoint，判定歌单/专辑/专属合辑
          if b_id and string.len(title) > 0 then
            local is_user_mix = (string.sub(b_id, 1, 6) == "VLRDTM")
                             or (string.sub(b_id, 1, 4) == "RDTM")
                             or (b_id == "VLLM")
                             or (string.find(title, "合辑") ~= nil)
                             or (string.find(title, "Mix") ~= nil)
                             or (string.find(title, "Supermix") ~= nil)
                             or (string.find(title, "ミックス") ~= nil)

            local is_playlist = is_user_mix
                             or (page_type == "MUSIC_PAGE_TYPE_PLAYLIST")
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
                if is_user_mix then
                  table.insert(feed.userMixes, pl)
                end
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
          else
            -- 1.2 若带的是 watchEndpoint (单曲卡片)，提取单曲为跑马灯动画丰富素材库
            local watch_ep = nav.nav(r, { "navigationEndpoint", "watchEndpoint" })
            local vid = watch_ep and watch_ep.videoId
            if vid and string.len(vid) > 0 and not seen_songs[vid] then
              seen_songs[vid] = true
              local s = {
                id = vid,
                title = title,
                artists = { { id = "yt_artist_" .. vid, name = (sub ~= "" and sub or "YouTube Music"), coverUrl = "" } },
                albumName = "YouTube Music",
                coverUrl = thumb,
                durationMs = 0
              }
              table.insert(feed.quick, s)
              table.insert(feed.daily, s)
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
end

--- 解析首页延续响应 (Continuation)，深度提取合辑与推荐
function browse_parser.parse_home_continuation(cont_data, feed)
  if not cont_data or not feed then return end
  local cont_secs = nav.nav(cont_data, { "continuationContents", "sectionListContinuation", "contents" })
                 or nav.nav(cont_data, { "contents", "sectionListRenderer", "contents" })
                 or {}
  local seen_pl = {}
  for _, p in ipairs(feed.playlists or {}) do seen_pl[p.id] = true end
  local seen_alb = {}
  for _, a in ipairs(feed.albums or {}) do seen_alb[a.id] = true end
  local seen_songs = {}
  for _, s in ipairs(feed.quick or {}) do seen_songs[s.id] = true end

  browse_parser.parse_home_sections(cont_secs, feed, seen_pl, seen_alb, seen_songs)
end

--- 解析首页 FEmusic_home 推荐流，对齐 Lazer MusicHome 数据契约
function browse_parser.parse_home_feed(data)
  local feed = {
    quick = {},
    daily = {},
    recommended = {},
    playlists = {},
    albums = {},
    editorialPlaylists = {},
    userMixes = {},
    continuation = nil
  }
  if not data or type(data) ~= "table" then return feed end

  local tabs = nav.nav(data, { "contents", "singleColumnBrowseResultsRenderer", "tabs" }) or {}
  local sec_list_renderer = nav.nav(tabs, { 1, "tabRenderer", "content", "sectionListRenderer" }) or {}
  local sec_list = sec_list_renderer.contents or {}
  feed.continuation = nav.nav(sec_list_renderer, { "continuations", 1, "nextContinuationData", "continuation" })

  local seen_pl = {}
  local seen_alb = {}
  local seen_songs = {}

  browse_parser.parse_home_sections(sec_list, feed, seen_pl, seen_alb, seen_songs)

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

--- 解析歌手主页的热门歌曲列表 (Top songs)
function browse_parser.parse_artist_songs(data, artist_id)
  local songs = {}
  if not data or type(data) ~= "table" then return songs end

  local seen_songs = {}
  local sec_list = nav.nav(data, {
    "contents", "singleColumnBrowseResultsRenderer", "tabs", 1, "tabRenderer",
    "content", "sectionListRenderer", "contents"
  }) or {}

  -- 1. 优先从第 1 个 sectionListRenderer 的 musicShelfRenderer 提取热门歌曲
  for _, sec in ipairs(sec_list) do
    if sec.musicShelfRenderer and sec.musicShelfRenderer.contents then
      for _, it in ipairs(sec.musicShelfRenderer.contents) do
        local r = it.musicResponsiveListItemRenderer
        if r then
          local s = search_parser.parse_song_item(r, nil, seen_songs)
          if s then table.insert(songs, s) end
        end
      end
      if #songs > 0 then break end
    end
  end

  -- 2. 若未找到 (如 Topic 频道通常没有 musicShelfRenderer)，从所有 Carousel 货架中提取单曲
  if #songs == 0 then
    for _, sec in ipairs(sec_list) do
      local carousel = sec.musicCarouselShelfRenderer
      if carousel and carousel.contents then
        for _, it in ipairs(carousel.contents) do
          local r = it.musicResponsiveListItemRenderer or it.musicTwoRowItemRenderer
          if r then
            local watch_ep = nav.nav(r, { "navigationEndpoint", "watchEndpoint" })
                          or nav.nav(r, { "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 1, "navigationEndpoint", "watchEndpoint" })
            local vid = watch_ep and watch_ep.videoId
            if vid and string.len(vid) == 11 and not seen_songs[vid] then
              seen_songs[vid] = true
              local t_runs = (r.title and r.title.runs)
                          or (r.flexColumns and r.flexColumns[1] and r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer and r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text and r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text.runs)
                          or {}
              local t_title = t_runs[1] and t_runs[1].text or ("Song " .. vid)
              local thumbs = nav.nav(r, { "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
                          or nav.nav(r, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
              local cover = thumbs and nav.extract_thumbnail(thumbs) or ("https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg")
              table.insert(songs, {
                id = vid,
                title = t_title,
                artists = { { id = tostring(artist_id or ""), name = "Artist", coverUrl = "" } },
                albumName = "YouTube Music",
                coverUrl = cover,
                durationMs = 0
              })
            end
          end
        end
      end
      if #songs >= 30 then break end
    end
  end

  -- 3. 终极回退：全局搜索所有 music_items
  if #songs == 0 then
    local music_items = {}
    nav.find_music_items(data, music_items)
    for _, it in ipairs(music_items) do
      local s = search_parser.parse_song_item(it, nil, seen_songs)
      if s then table.insert(songs, s) end
    end
  end

  return songs
end

--- 智能缝合与清洗歌手介绍 Runs，修复 YouTube 官方维基百科切分破损并完整保留真实 URL
function browse_parser.extract_artist_description(desc_obj)
  if not desc_obj or type(desc_obj) ~= "table" then return "" end
  local runs = desc_obj.runs
  if not runs or #runs == 0 then
    return desc_obj.text or ""
  end

  if #runs < 3 then
    local parts = {}
    for _, r in ipairs(runs) do
      table.insert(parts, r.text or "")
    end
    return table.concat(parts, "")
  end

  local main_text = runs[1].text or ""
  local run1_ep = runs[2].navigationEndpoint or {}
  local run1_url = nav.nav(run1_ep, { "urlEndpoint", "url" }) or ""

  if string.find(main_text, "来自“Wikipedia”") and string.len(run1_url) > 0 then
    -- 1. 提纯维基百科纯净 URL (截去误吞的 "），遵循" 等后缀)
    local clean_wiki_url = string.match(run1_url, "^(https?://[^%)]+)") or run1_url
    clean_wiki_url = string.gsub(clean_wiki_url, "[，,%)]+$", "")

    -- 2. 提纯 CC 协议 URL (来自 run 4)
    local cc_url = "http://creativecommons.org/licenses/by-sa/3.0/legalcode"
    if #runs >= 4 then
      local raw_cc = nav.nav(runs[4], { "navigationEndpoint", "urlEndpoint", "url" })
      if raw_cc and string.len(raw_cc) > 0 then
        cc_url = raw_cc
      end
    end

    -- 3. 提取主体简介文本 (去除结尾残缺的 '来自“Wikipedia”(' )
    local clean_body = string.gsub(main_text, "[\r\n%s]*来自“Wikipedia”%($", "")
    clean_body = string.gsub(clean_body, "[\r\n%s]*来自“Wikipedia”$", "")

    -- 4. 规范重组输出
    local attribution = string.format(
      "\n\n来自“Wikipedia”（%s），遵循“Creative Commons Attribution CC-BY-SA 3.0”协议（%s）",
      clean_wiki_url,
      cc_url
    )
    return clean_body .. attribution
  end

  local parts = {}
  for _, r in ipairs(runs) do
    table.insert(parts, r.text or "")
  end
  return table.concat(parts, "")
end

--- 解析歌手详情 (包含头部、简介与统计)
function browse_parser.parse_artist(data, artist_id)
  if not data or type(data) ~= "table" then return nil end

  local hdr = nav.nav(data, { "header", "musicImmersiveHeaderRenderer" })
           or nav.nav(data, { "header", "musicVisualHeaderRenderer" })
           or nav.nav(data, { "header", "musicHeaderRenderer" })
           or nav.nav(data, { "header", "c4TabbedHeaderRenderer" })
           or {}
  local name = nav.nav(hdr, { "title", "runs", 1, "text" })
            or nav.nav(hdr, { "title", "simpleText" })
            or nav.nav(data, { "microformat", "microformatDataRenderer", "title" })
            or "Artist"

  -- 净化自动生成的 " - Topic" 后缀
  name = string.gsub(name, "%s*-[%s]*Topic$", "")

  local desc = browse_parser.extract_artist_description(hdr.description)

  -- 若头部未附带完整简介，从底部的 musicDescriptionShelfRenderer 深度提取
  if string.len(desc) == 0 then
    local sec_list = nav.nav(data, {
      "contents", "singleColumnBrowseResultsRenderer", "tabs", 1, "tabRenderer",
      "content", "sectionListRenderer", "contents"
    }) or {}
    for _, s in ipairs(sec_list) do
      if s.musicDescriptionShelfRenderer and s.musicDescriptionShelfRenderer.description then
        desc = browse_parser.extract_artist_description(s.musicDescriptionShelfRenderer.description)
        if string.len(desc) > 0 then break end
      end
    end
  end

  local cover_url = ""
  local thumbs = nav.nav(hdr, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
              or nav.nav(hdr, { "foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
  if thumbs then cover_url = nav.extract_thumbnail(thumbs) end

  return {
    id = tostring(artist_id or ""),
    name = name,
    coverUrl = cover_url,
    description = desc,
    albumCount = 0
  }
end

return browse_parser
