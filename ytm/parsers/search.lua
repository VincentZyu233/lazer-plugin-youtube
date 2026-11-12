local nav = require("ytm.core.navigation")

local search_parser = {}

--- 解析单个 musicResponsiveListItemRenderer 为歌曲对象
function search_parser.parse_song_item(it, query, seen_songs)
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
  local title = ""
  if cols[1] and cols[1].musicResponsiveListItemFlexColumnRenderer then
    title = nav.extract_text(cols[1].musicResponsiveListItemFlexColumnRenderer.text)
  end
  if string.len(title) == 0 then
    title = "Song " .. vid
  end

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

  for c_idx = 2, #cols do
    local col_rend = cols[c_idx].musicResponsiveListItemFlexColumnRenderer
    if col_rend and col_rend.text and col_rend.text.runs then
      for _, r in ipairs(col_rend.text.runs) do
        local t = r.text or ""
        local endpoint = nav.nav(r, { "navigationEndpoint", "browseEndpoint" }) or {}
        local config_endpoint = nav.nav(endpoint, {
          "browseEndpointContextSupportedConfigs",
          "browseEndpointContextMusicConfig"
        })
        local page_type = config_endpoint and config_endpoint.pageType
        local b_id = endpoint.browseId

        if page_type == "MUSIC_PAGE_TYPE_ARTIST" or page_type == "MUSIC_PAGE_TYPE_USER_CHANNEL" then
          local trimmed = nav.trim_str(t)
          if string.len(trimmed) > 0 and trimmed ~= "•" and trimmed ~= "·" and trimmed ~= "・" then
            table.insert(song_artists, {
              id = b_id or ("yt_artist_" .. vid),
              name = trimmed,
              coverUrl = ""
            })
          end
        elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" then
          album_name = nav.trim_str(t)
          album_id = b_id
        else
          local ms = nav.parse_time_to_ms(t)
          if ms > 0 then dur_ms = ms end
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
    table.insert(song_artists, {
      id = "yt_artist_" .. vid,
      name = "YouTube Music",
      coverUrl = ""
    })
  end

  if seen_songs then seen_songs[vid] = true end

  return {
    id = vid,
    title = title,
    artists = song_artists,
    albumId = album_id,
    albumName = string.len(album_name) > 0 and album_name or "YouTube Music",
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

  local music_items = {}
  nav.find_music_items(data, music_items)

  for _, it in ipairs(music_items) do
    local endpoint = nav.nav(it, {
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

    if page_type == "MUSIC_PAGE_TYPE_ARTIST" then
      local art_id = browse_id or ("yt_artist_" .. title)
      if not seen_artists[art_id] and string.len(title) > 0 then
        seen_artists[art_id] = true
        table.insert(artists, {
          id = art_id,
          name = title,
          coverUrl = cover_url
        })
      end
    elseif page_type == "MUSIC_PAGE_TYPE_ALBUM" then
      local alb_id = browse_id or ("yt_album_" .. title)
      if not seen_albums[alb_id] and string.len(title) > 0 then
        seen_albums[alb_id] = true
        table.insert(albums, {
          id = alb_id,
          title = title,
          coverUrl = cover_url,
          artists = { { id = "yt_artist_unk", name = "YouTube Music" } },
          songCount = 0
        })
      end
    elseif page_type == "MUSIC_PAGE_TYPE_PLAYLIST" then
      local pl_id = browse_id or ("yt_playlist_" .. title)
      if not seen_playlists[pl_id] and string.len(title) > 0 then
        seen_playlists[pl_id] = true
        table.insert(playlists, {
          id = pl_id,
          title = title,
          coverUrl = cover_url,
          songCount = 0
        })
      end
    else
      local s = search_parser.parse_song_item(it, query, seen_songs)
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
