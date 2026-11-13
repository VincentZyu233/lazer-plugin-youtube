local nav = require("ytm.core.navigation")

local search_parser = {}

--- 清洗歌曲标题，去除噪音修饰，提升 Lazer 榜单与搜索匹配成功率
local function clean_song_title(title, query)
  if not title or title == "" then return title end
  local clean = title

  -- 1. 去除 【...】 和 [...] (如 【MV】、[Official Music Video]、[初音ミク]、[meme] 等)
  clean = string.gsub(clean, "^【[^】]*】%s*", "")
  clean = string.gsub(clean, "%s*【[^】]*】$", "")
  clean = string.gsub(clean, "^%[[^%]]*%]%s*", "")
  clean = string.gsub(clean, "%s*%[[^%]]*%]$", "")

  -- 2. 去除 合作音乐人 / feat / ft 修饰
  clean = string.gsub(clean, "%s*（合作音乐人：[^）]*）", "")
  clean = string.gsub(clean, "%s*%(合作音乐人：[^%)]*%)", "")
  clean = string.gsub(clean, "%s*%(feat%.?[^%)]*%)", "")
  clean = string.gsub(clean, "%s*%(ft%.?[^%)]*%)", "")
  clean = string.gsub(clean, "%s*（feat%.?[^）]*）", "")
  clean = string.gsub(clean, "%s*（ft%.?[^）]*）", "")
  clean = string.gsub(clean, "%s+[Cc]over%s*.*$", "")
  clean = string.gsub(clean, "%s*歌ってみた.*$", "")
  clean = nav.trim_str(clean)

  -- 3. 分割处理复合标题 "A - B" 或 "A / B" (常见于 "日文名 - 英文译名" 或 "中文名 - 英文名")
  local sep_idx = string.find(clean, " - ", 1, true) or string.find(clean, " / ", 1, true)
  if sep_idx and sep_idx > 1 and sep_idx < string.len(clean) - 2 then
    local part1 = nav.trim_str(string.sub(clean, 1, sep_idx - 1))
    local part2 = nav.trim_str(string.sub(clean, sep_idx + 3))
    if string.len(part1) > 0 and string.len(part2) > 0 then
      local q_lower = string.lower(query or "")
      local p1_lower = string.lower(part1)
      local p2_lower = string.lower(part2)

      if string.len(q_lower) > 0 then
        if p1_lower == q_lower or string.find(q_lower, p1_lower, 1, true) or string.find(p1_lower, q_lower, 1, true) then
          clean = part1
        elseif p2_lower == q_lower or string.find(q_lower, p2_lower, 1, true) or string.find(p2_lower, q_lower, 1, true) then
          clean = part2
        end
      end
    end
  end

  return clean
end

--- 解析单个 musicResponsiveListItemRenderer 为歌曲对象
function search_parser.parse_song_item(it, query, seen_songs, default_artist)
  if not it or type(it) ~= "table" then return nil end

  local vid = nav.nav(it, { "playlistItemData", "videoId" })
  if (not vid or string.len(vid) ~= 11) then
    vid = nav.nav(it, {
      "overlay",
      "musicItemThumbnailOverlayRenderer",
      "content",
      "musicPlayButtonRenderer",
      "playNavigationEndpoint",
      "watchEndpoint",
      "videoId"
    })
  end

  if not vid or string.len(vid) ~= 11 or (seen_songs and seen_songs[vid]) then
    return nil
  end

  local cols = it.flexColumns or {}
  local raw_title = ""
  if cols[1] and cols[1].musicResponsiveListItemFlexColumnRenderer then
    raw_title = nav.extract_text(cols[1].musicResponsiveListItemFlexColumnRenderer.text)
  end
  if string.len(raw_title) == 0 then
    raw_title = "Song " .. vid
  end

  local title = clean_song_title(raw_title, query)

  local cover_url = ""
  local thumbs = nav.nav(it, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
  if thumbs then
    cover_url = nav.extract_thumbnail(thumbs)
  end
  if string.len(cover_url) == 0 then
    cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
  end

  local song_artists = {}
  local album_name = ""
  local album_id = nil
  local dur_ms = 0
  local raw_play_text = nil

  for c_idx = 2, #cols do
    local col_rend = cols[c_idx].musicResponsiveListItemFlexColumnRenderer
    if col_rend and col_rend.text and col_rend.text.runs then
      for _, r in ipairs(col_rend.text.runs) do
        local t = r.text or ""
        local trimmed = nav.trim_str(t)

        if string.len(trimmed) > 0 and trimmed ~= "•" and trimmed ~= "·" and trimmed ~= "・"
           and trimmed ~= "歌曲" and trimmed ~= "单曲" and trimmed ~= "视频" and trimmed ~= "Song" and trimmed ~= "Video"
           and trimmed ~= "曲" and trimmed ~= "動画" and trimmed ~= "和" and trimmed ~= "、" and trimmed ~= "&" then

          local endpoint = nav.nav(r, { "navigationEndpoint", "browseEndpoint" }) or {}
          local config_endpoint = nav.nav(endpoint, {
            "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig"
          })
          local page_type = config_endpoint and config_endpoint.pageType
          local b_id = endpoint.browseId

          -- 优先检查是否为播放量/统计数文本 (如 "播放次数：1743万", "17M views", "850K")
          if nav.is_play_count(trimmed) then
            if not raw_play_text then
              raw_play_text = trimmed
            end
          elseif page_type == "MUSIC_PAGE_TYPE_ARTIST" or page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL" then
            table.insert(song_artists, {
              id = b_id or ("yt_artist_" .. vid),
              name = trimmed,
              coverUrl = ""
            })
          elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" then
            album_name = trimmed
            album_id = b_id
          else
            -- 检查是否为时间 (如 "03:45" 或 "1:02:15")
            local ms = nav.parse_time_to_ms(trimmed)
            if ms > 0 then
              dur_ms = ms
            else
              -- 检查是否为 4 位发行年份 (如 "2022" 或 "2022年")
              local is_year = false
              if string.len(trimmed) >= 4 then
                local b1, b2, b3, b4 = string.byte(trimmed, 1, 4)
                if b1 >= 48 and b1 <= 57 and b2 >= 48 and b2 <= 57 and b3 >= 48 and b3 <= 57 and b4 >= 48 and b4 <= 57 then
                  is_year = true
                end
              end

              -- 若非发行年份且不是播放量，且当前尚无任何歌手，作为候选歌手兜底
              if not is_year and #song_artists == 0 and (not b_id or b_id == "") then
                table.insert(song_artists, {
                  id = "yt_artist_" .. vid,
                  name = trimmed,
                  coverUrl = ""
                })
              end
            end
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
          local ms = nav.parse_time_to_ms(r.text)
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
    if default_artist then
      if type(default_artist) == "table" then
        table.insert(song_artists, {
          id = default_artist.id or ("yt_artist_" .. vid),
          name = default_artist.name or "Unknown Artist",
          coverUrl = default_artist.coverUrl or ""
        })
      else
        table.insert(song_artists, {
          id = "yt_artist_" .. vid,
          name = tostring(default_artist),
          coverUrl = ""
        })
      end
    else
      table.insert(song_artists, {
        id = "yt_artist_" .. vid,
        name = "Unknown Artist",
        coverUrl = ""
      })
    end
  end

  -- 格式化播放量前缀与专辑名称 (K / M / B 国际化格式)
  local fmt_play = nav.format_play_count(raw_play_text)
  local play_prefix = fmt_play and ("[" .. fmt_play .. "] ") or ""

  local clean_album = album_name
  if not clean_album or string.len(clean_album) == 0 then
    if string.len(title) > 0 and title ~= "Unknown Track" then
      clean_album = title
    else
      clean_album = "Unknown Album"
    end
  end

  if seen_songs then seen_songs[vid] = true end

  return {
    id = vid,
    title = title,
    artists = song_artists,
    albumId = album_id,
    albumName = play_prefix .. clean_album,
    coverUrl = cover_url,
    durationMs = dur_ms
  }
end

--- 解析整个综合搜索响应数据
function search_parser.parse_search_results(data, query)
  local songs = {}
  local albums = {}
  local artists = {}
  local playlists = {}

  local seen_songs = {}
  local seen_albums = {}
  local seen_artists = {}
  local seen_playlists = {}

  if not data or type(data) ~= "table" then
    return { songs = songs, albums = albums, artists = artists, playlists = playlists }
  end

  -- 0. 优先提取置顶大卡片 (musicCardShelfRenderer，如权威歌手/官方专辑)
  local first_sec = nav.nav(data, {
    "contents", "tabbedSearchResultsRenderer", "tabs", 1, "tabRenderer",
    "content", "sectionListRenderer", "contents", 1
  })
  if first_sec and first_sec.musicCardShelfRenderer then
    local card = first_sec.musicCardShelfRenderer
    local card_title = nav.nav(card, { "title", "runs", 1, "text" }) or ""
    local card_sub = nav.nav(card, { "subtitle", "runs", 1, "text" }) or ""
    local card_ep = nav.nav(card, { "title", "runs", 1, "navigationEndpoint", "browseEndpoint" }) or {}
    local card_config = nav.nav(card_ep, {
      "browseEndpointContextSupportedConfigs",
      "browseEndpointContextMusicConfig"
    })
    local card_pt = card_config and card_config.pageType
    local card_bid = card_ep.browseId

    local card_cover = ""
    local card_thumbs = nav.nav(card, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
    if card_thumbs then
      card_cover = nav.extract_thumbnail(card_thumbs)
    end

    card_title = nav.trim_str(card_title)
    if string.len(card_title) > 0 then
      local card_is_artist = (card_pt == "MUSIC_PAGE_TYPE_ARTIST")
                          or (card_bid and string.sub(card_bid, 1, 2) == "UC")
                          or (card_sub and (string.find(card_sub, "音乐人") or string.find(card_sub, "歌手") or string.find(card_sub, "Artist") or string.find(card_sub, "アーティスト")))
      local card_is_album = (card_pt == "MUSIC_PAGE_TYPE_ALBUM")
                         or (card_bid and string.sub(card_bid, 1, 6) == "MPREb_")
                         or (card_sub and (string.find(card_sub, "专辑") or string.find(card_sub, "EP") or string.find(card_sub, "Album") or string.find(card_sub, "アルバム")))

      if card_is_artist then
        local art_id = card_bid or ("yt_artist_" .. card_title)
        seen_artists[art_id] = true
        table.insert(artists, {
          id = art_id,
          name = card_title,
          coverUrl = card_cover
        })
      elseif card_is_album then
        local alb_id = card_bid or ("yt_album_" .. card_title)
        seen_albums[alb_id] = true
        table.insert(albums, {
          id = alb_id,
          title = card_title,
          name = card_title,
          coverUrl = card_cover,
          artists = { { id = "yt_artist_unk", name = card_sub ~= "" and card_sub or "YouTube Music" } },
          songCount = 0
        })
      end
    end

    -- 0.1 提取卡片内挂载的热门歌曲，绑定该歌手身份
    local card_artist = (string.len(card_title) > 0 and ((card_pt == "MUSIC_PAGE_TYPE_ARTIST") or (card_bid and string.sub(card_bid, 1, 2) == "UC") or (card_sub and (string.find(card_sub, "音乐人") or string.find(card_sub, "歌手") or string.find(card_sub, "Artist") or string.find(card_sub, "アーティスト")))))
                    and { id = card_bid or ("yt_artist_" .. card_title), name = card_title, coverUrl = card_cover }
                    or nil

    if card.contents and #card.contents > 0 then
      for _, it in ipairs(card.contents) do
        local r = it.musicResponsiveListItemRenderer
        if r then
          local s = search_parser.parse_song_item(r, query, seen_songs, card_artist)
          if s then table.insert(songs, s) end
        end
      end
    end
  end

  local music_items = {}
  nav.find_music_items(data, music_items)

  for _, it in ipairs(music_items) do
    -- 提取导航 Endpoint (支持根节点 it.navigationEndpoint 与 flexColumns 内部)
    local endpoint = nav.nav(it, { "navigationEndpoint", "browseEndpoint" })
                  or nav.nav(it, {
                    "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 1, "navigationEndpoint", "browseEndpoint"
                  })
    local config_endpoint = nav.nav(endpoint, {
      "browseEndpointContextSupportedConfigs",
      "browseEndpointContextMusicConfig"
    })
    local page_type = config_endpoint and config_endpoint.pageType
    local browse_id = endpoint and endpoint.browseId

    local title = ""
    local col1_runs = nav.nav(it, {
      "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"
    })
    if col1_runs and #col1_runs > 0 and col1_runs[1].text then
      title = nav.trim_str(col1_runs[1].text)
    end

    local cover_url = ""
    local thumbs = nav.nav(it, { "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails" })
    if thumbs then
      cover_url = nav.extract_thumbnail(thumbs)
    end

    -- 读取第二列副标题与类型描述 (例如 "音乐人 • 每月听众", "专辑 • 2021", "播放列表 • 作者")
    local type_label = ""
    local subtitle_owner = ""
    local col2_runs = nav.nav(it, {
      "flexColumns", 2, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"
    })
    if col2_runs and #col2_runs > 0 then
      if col2_runs[1].text then
        type_label = nav.trim_str(col2_runs[1].text)
      end
      for idx = 2, #col2_runs do
        local r = col2_runs[idx]
        if r.text and r.text ~= " • " and r.text ~= "•" and nav.trim_str(r.text) ~= "" then
          subtitle_owner = nav.trim_str(r.text)
          break
        end
      end
    end

    local is_artist = (page_type == "MUSIC_PAGE_TYPE_ARTIST")
                   or (browse_id and string.sub(browse_id, 1, 2) == "UC")
                   or (type_label == "音乐人" or type_label == "歌手" or type_label == "Artist" or type_label == "アーティスト")

    local is_album = (page_type == "MUSIC_PAGE_TYPE_ALBUM")
                  or (browse_id and string.sub(browse_id, 1, 6) == "MPREb_")
                  or (type_label == "专辑" or type_label == "EP" or type_label == "单曲" or type_label == "Album" or type_label == "アルバム")

    local is_playlist = (page_type == "MUSIC_PAGE_TYPE_PLAYLIST")
                     or (browse_id and (string.sub(browse_id, 1, 2) == "VL" or string.sub(browse_id, 1, 2) == "PL"))
                     or (type_label == "播放列表" or type_label == "歌单" or type_label == "Playlist" or type_label == "プレイリスト")

    if is_artist then
      local art_id = browse_id or ("yt_artist_" .. title)
      if not seen_artists[art_id] and string.len(title) > 0 then
        seen_artists[art_id] = true
        table.insert(artists, {
          id = art_id,
          name = title,
          coverUrl = cover_url
        })
      end
    elseif is_album then
      local alb_id = browse_id or ("yt_album_" .. title)
      if not seen_albums[alb_id] and string.len(title) > 0 then
        seen_albums[alb_id] = true
        local artist_name = subtitle_owner ~= "" and subtitle_owner or "YouTube Music"
        table.insert(albums, {
          id = alb_id,
          title = title,
          name = title,
          coverUrl = cover_url,
          artists = { { id = "yt_artist_" .. artist_name, name = artist_name } },
          songCount = 0
        })
      end
    elseif is_playlist then
      local pl_id = browse_id or ("yt_playlist_" .. title)
      if not seen_playlists[pl_id] and string.len(title) > 0 then
        seen_playlists[pl_id] = true
        local owner_name = subtitle_owner ~= "" and subtitle_owner or "YouTube Music"
        table.insert(playlists, {
          id = pl_id,
          name = title,
          title = title,
          coverUrl = cover_url,
          songCount = 0,
          owner = owner_name
        })
      end
    else
      local s = search_parser.parse_song_item(it, query, seen_songs, card_artist)
      if s then table.insert(songs, s) end
    end
  end

  return {
    songs = songs,
    albums = albums,
    artists = artists,
    playlists = playlists
  }
end

return search_parser
