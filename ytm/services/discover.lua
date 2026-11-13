local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local nav = require("ytm.core.navigation")
local browse_parser = require("ytm.parsers.browse")
local search_parser = require("ytm.parsers.search")

local discover_service = {}
local cached_user_mixes = {}

--- 首页探索推荐流 (对齐 Lazer MusicHome 契约)
function discover_service.home_feed()
  transport.ensure_visitor_data()
  local payload = {
    browseId = "FEmusic_home"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  local feed = browse_parser.parse_home_feed(data)

  -- 1. 更新或提取用户专属 Mix 快照 (归档合辑/重放合辑/发现合辑/新歌合辑)
  if feed.userMixes and #feed.userMixes > 0 then
    cached_user_mixes = feed.userMixes
  end

  -- 2. 无论当前首页是否被单曲推荐冲刷，永远将专属 Mix 稳稳置顶在 editorialPlaylists
  --    主页中段 100% 稳定呈现 YouTube 官方下发的高级 mixart 几何艺术封面！
  if #cached_user_mixes > 0 then
    local existing_ids = {}
    for _, p in ipairs(feed.editorialPlaylists) do
      existing_ids[p.id] = true
    end
    for i = #cached_user_mixes, 1, -1 do
      local mix = cached_user_mixes[i]
      if not existing_ids[mix.id] then
        existing_ids[mix.id] = true
        table.insert(feed.editorialPlaylists, 1, mix)
      end
    end
  end

  -- 3. 若首屏未直接给出单曲卡片，取推荐第 1 歌单的曲目填充 quick 与 daily (单次快速请求)
  --    这样 Lazer 顶部的“每日推荐”与底部的“为你创建的电台”将拥有饱满的单曲封面供 _MovingCoverMosaic 平移！
  if #feed.quick == 0 and #feed.recommended > 0 then
    local first_pl = feed.recommended[1]
    local pl_data = transport.post_music("browse", {
      browseId = first_pl.id
    }, constants.CLIENT_WEB_REMIX)

    if pl_data then
      local pl_songs = browse_parser.parse_playlist_songs(pl_data)
      for i = 1, math.min(#pl_songs, 25) do
        table.insert(feed.quick, pl_songs[i])
        table.insert(feed.daily, pl_songs[i])
      end
    end
  end

  return feed
end

--- 排行榜 (对齐 Lazer List<MusicPlaylist> 契约)
function discover_service.charts()
  transport.ensure_visitor_data()
  local payload = {
    browseId = "FEmusic_charts"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  if not data then return {} end

  return browse_parser.parse_charts(data)
end

--- 个性化推荐单曲分页 (对齐 Lazer MusicPage<MusicSong> 契约)
function discover_service.recommendations(limit)
  local max_take = tonumber(limit) or 30
  local feed = discover_service.home_feed()
  local res = {}
  for i = 1, math.min(#feed.quick, max_take) do
    table.insert(res, feed.quick[i])
  end
  return res
end

--- 电台流 (对齐 Lazer List<MusicSong> 契约)
function discover_service.radio(args)
  args = args or {}
  local seed_vid = args.seed or ""
  local playlist_id = args.playlist or ""
  local limit = tonumber(args.limit) or 30

  transport.ensure_visitor_data()

  local payload = {}
  if string.len(playlist_id) > 0 then
    payload.playlistId = playlist_id
  elseif string.len(seed_vid) > 0 then
    payload.playlistId = "RDAMVM" .. seed_vid
    payload.videoId = seed_vid
  else
    -- 默认使用首屏推荐单曲作为电台种子
    local feed = discover_service.home_feed()
    if #feed.quick > 0 then
      local fallback_vid = feed.quick[1].id
      payload.playlistId = "RDAMVM" .. fallback_vid
      payload.videoId = fallback_vid
    end
  end

  if not payload.playlistId and not payload.videoId then
    return {}
  end

  local next_data = transport.post_music("next", payload, constants.CLIENT_WEB_REMIX)
  if not next_data then return {} end

  local queue_items = nav.nav(next_data, {
    "contents",
    "singleColumnMusicWatchNextResultsRenderer",
    "tabbedRenderer",
    "watchNextTabbedResultsRenderer",
    "tabs",
    1,
    "tabRenderer",
    "content",
    "musicQueueRenderer",
    "content",
    "playlistPanelRenderer",
    "contents"
  }) or {}

  local songs = {}
  local seen_songs = {}

  for _, it in ipairs(queue_items) do
    local r = it.playlistPanelVideoRenderer
    if r and r.videoId and not seen_songs[r.videoId] then
      seen_songs[r.videoId] = true
      local title = nav.extract_text(r.title)
      local author = nav.extract_text(r.longBylineText or r.shortBylineText)
      local dur_str = nav.extract_text(r.lengthText)
      local dur_ms = nav.parse_time_to_ms(dur_str)

      local thumb = ""
      if r.thumbnail and r.thumbnail.thumbnails then
        thumb = nav.extract_thumbnail(r.thumbnail.thumbnails)
      end
      if string.len(thumb) == 0 then
        thumb = "https://i.ytimg.com/vi/" .. r.videoId .. "/hqdefault.jpg"
      end

      table.insert(songs, {
        id = r.videoId,
        title = title,
        artists = {
          { id = "yt_artist_" .. r.videoId, name = author, coverUrl = "" }
        },
        albumName = "YouTube Music Radio",
        coverUrl = thumb,
        durationMs = dur_ms
      })

      if #songs >= limit then break end
    end
  end

  return songs
end

return discover_service
