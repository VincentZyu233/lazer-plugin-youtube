local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local lyrics_parser = require("ytm.parsers.lyrics")
local nav = require("ytm.core.navigation")

local lyrics_service = {}

--- 从指定 browseId 提取歌词，返回 (results, has_cues)
local function fetch_browse_lyrics(browse_id)
  if not browse_id then return {}, false end

  -- 优先尝试 ANDROID_MUSIC
  local android_data = transport.post_music("browse", {
    browseId = browse_id
  }, constants.CLIENT_ANDROID_MUSIC)

  if android_data then
    local timed_res, has_cues = lyrics_parser.parse_lyrics(android_data)
    if #timed_res > 0 and has_cues then
      return timed_res, true
    end
    if #timed_res > 0 then
      return timed_res, false
    end
  end

  -- 回退 WEB_REMIX
  local web_data = transport.post_music("browse", {
    browseId = browse_id
  }, constants.CLIENT_WEB_REMIX)

  if web_data then
    local web_res = lyrics_parser.parse_lyrics(web_data)
    return web_res, false
  end

  return {}, false
end

--- 从候选视频 ID 提取歌词 browseId
local function get_video_lyrics_browse_id(vid)
  local next_data = transport.post_music("next", {
    videoId = vid
  }, constants.CLIENT_WEB_REMIX)
  if not next_data then return nil end
  local b_id, is_pure = lyrics_parser.extract_browse_id(next_data)
  if is_pure then return nil end
  return b_id
end

--- 获取指定歌曲的歌词
-- 支持：
-- 1. 直出毫秒级精准时间戳 (ANDROID_MUSIC)
-- 2. MV / 用户上传版自动关联官方录音室音频版 (Audio Track Resolution)
-- 3. 静态全本歌词兜底
function lyrics_service.get_lyrics(song_id)
  if not song_id or type(song_id) ~= "string" or string.len(song_id) == 0 then
    return {}
  end

  local clean_id = string.match(song_id, "([a-zA-Z0-9_-]+)$") or song_id

  -- 第 1 步：尝试直接获取当前 videoId 的歌词
  local self_browse_id = get_video_lyrics_browse_id(clean_id)
  local self_lyrics, has_precise_cues = fetch_browse_lyrics(self_browse_id)

  if #self_lyrics > 0 and has_precise_cues then
    return self_lyrics
  end

  -- 第 2 步：若自身没有精准时间戳，自动尝试从官方录音室曲库 (ATV) 检索匹配
  local player_res = transport.post_youtube("player?prettyPrint=false", {
    videoId = clean_id
  }, constants.CLIENT_VISIONOS)

  local vd = player_res and player_res.videoDetails
  if vd and vd.title then
    local title = vd.title or ""
    local author = vd.author or ""

    local clean_title = title
    local mv_idx = string.find(clean_title, "MV", 1, true)
    if mv_idx and mv_idx > 1 then clean_title = string.sub(clean_title, 1, mv_idx - 1) end
    local off_idx = string.find(clean_title, "Official", 1, true)
    if off_idx and off_idx > 1 then clean_title = string.sub(clean_title, 1, off_idx - 1) end
    local brk_idx = string.find(clean_title, "【", 1, true)
    if brk_idx and brk_idx > 1 then clean_title = string.sub(clean_title, 1, brk_idx - 1) end
    clean_title = nav.trim_str(clean_title)

    local clean_author = author
    local topic_idx = string.find(clean_author, "- Topic", 1, true)
    if topic_idx then
      clean_author = string.sub(clean_author, 1, topic_idx - 1)
    end
    clean_author = nav.trim_str(clean_author)

    local search_query = clean_title .. " " .. clean_author
    local search_data = transport.post_music("search", {
      query = search_query,
      params = "EgWKAQIIAWoOEAUQCRADEAQQChAVEBA%3D"
    }, constants.CLIENT_WEB_REMIX)

    if search_data then
      local candidate_items = {}
      nav.find_music_items(search_data, candidate_items)
      for idx = 1, math.min(#candidate_items, 3) do
        local it = candidate_items[idx]
        local cand_vid = nav.nav(it, { "playlistItemData", "videoId" })
        if cand_vid and cand_vid ~= clean_id and string.len(cand_vid) == 11 then
          local cand_b_id = get_video_lyrics_browse_id(cand_vid)
          if cand_b_id then
            local cand_lyrics, cand_has_cues = fetch_browse_lyrics(cand_b_id)
            if #cand_lyrics > 0 and cand_has_cues then
              return cand_lyrics
            end
          end
        end
      end
    end
  end

  -- 第 3 步：若官方曲库也无精准时间轴，返回自身的兜底歌词
  if #self_lyrics > 0 then
    return self_lyrics
  end

  return {}
end

return lyrics_service
