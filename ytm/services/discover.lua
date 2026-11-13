local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local nav = require("ytm.core.navigation")
local browse_parser = require("ytm.parsers.browse")
local search_parser = require("ytm.parsers.search")
local store = require("ytm.core.store")

local discover_service = {}
local cached_user_mixes = {}

local OFFICIAL_FALLBACK_MIXES = {
  {
    id = "RDTMAK5uy_kset8DisdE7LSD4TNjEVnkKRTmG7a562Y8",
    name = "My Supermix",
    description = "Endless personalized music blend tailored to your tastes",
    coverUrl = "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_supermix.png",
    songCount = 0,
    owner = "YouTube Music"
  },
  {
    id = "RDTMAK5uy_m_jQ6oU5_130iJbN95_W4jWqQ7c-kC_rM",
    name = "Discover Mix",
    description = "Fresh music and hidden gems updated every week",
    coverUrl = "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_discover_mix.png",
    songCount = 0,
    owner = "YouTube Music"
  },
  {
    id = "RDTMAK5uy_ksxU4WqD24u_Xk_hZfXQ65m7R3Z9Z6w",
    name = "Replay Mix",
    description = "Your favorite songs on repeat",
    coverUrl = "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_replay_mix.png",
    songCount = 0,
    owner = "YouTube Music"
  },
  {
    id = "RDTMAK5uy_l43N1o_GZJ25u1_Xq_hZfXQ65m7R3Z9Z6w",
    name = "New Release Mix",
    description = "The latest tracks from artists you love",
    coverUrl = "https://cdn.jsdelivr.net/gh/VincentZyu233/lazer-plugin-youtube@main/assets/covers/cover_archive_mix.png",
    songCount = 0,
    owner = "YouTube Music"
  }
}

--- 首页探索推荐流 (对齐 Lazer MusicHome 契约)
function discover_service.home_feed()
  transport.ensure_visitor_data()
  local payload = {
    browseId = "FEmusic_home"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  local feed = browse_parser.parse_home_feed(data)

  -- 0. 若首屏未解析到专属合辑，发起 1 次延续请求（Continuation）深度提取用户专属合辑（如“新しい曲や過去のお気に入り” / “Mixed for you”）
  if #feed.userMixes == 0 and feed.continuation and string.len(feed.continuation) > 0 then
    local ok, cont_data = pcall(transport.post_music, "browse?continuation=" .. feed.continuation, { continuation = feed.continuation }, constants.CLIENT_WEB_REMIX)
    if ok and cont_data then
      browse_parser.parse_home_continuation(cont_data, feed)
    end
  end

  -- 1. 更新或提取用户专属 Mix 快照 (归档合辑/重放合辑/发现合辑/新歌合辑/Mixart)
  if feed.userMixes and #feed.userMixes > 0 then
    cached_user_mixes = feed.userMixes
    pcall(store.set, "cached_user_mixes", cached_user_mixes)
  else
    -- 若本次请求没有返回专属合辑，尝试从磁盘持久化存储加载
    if #cached_user_mixes == 0 then
      local ok, saved = pcall(store.get, "cached_user_mixes")
      if ok and saved and type(saved) == "table" and #saved > 0 then
        cached_user_mixes = saved
      end
    end
  end

  -- 2. 确定最终生效的专属合辑列表 (网络最新/磁盘快照 > 官方种子兜底)
  local active_mixes = {}
  if #cached_user_mixes > 0 then
    active_mixes = cached_user_mixes
  else
    active_mixes = OFFICIAL_FALLBACK_MIXES
  end

  -- 3. 稳稳置顶在 editorialPlaylists，主页中段 100% 稳定呈现 YouTube 官方下发的 mixart 动态封面
  local new_editorial = {}
  local seen_editorial = {}
  for _, mix in ipairs(active_mixes) do
    if not seen_editorial[mix.id] then
      seen_editorial[mix.id] = true
      table.insert(new_editorial, mix)
    end
  end
  for _, pl in ipairs(feed.editorialPlaylists) do
    if not seen_editorial[pl.id] then
      seen_editorial[pl.id] = true
      table.insert(new_editorial, pl)
    end
  end
  feed.editorialPlaylists = new_editorial

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
