local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local lyrics_parser = require("ytm.parsers.lyrics")

local lyrics_service = {}

--- 获取指定歌曲的歌词
-- 自动编排 /next 探查、ANDROID_MUSIC 毫秒级时间戳获取与 Web 静态回退
function lyrics_service.get_lyrics(song_id)
  if not song_id or type(song_id) ~= "string" or string.len(song_id) == 0 then
    return {}
  end

  -- 第 1 步：向 next 接口查询歌词专属 browseId 与纯音乐状态
  local next_data, next_err = transport.post_music("next", {
    videoId = song_id
  }, constants.CLIENT_WEB_REMIX)

  if not next_data then
    return {}
  end

  local lyrics_browse_id, is_pure_music = lyrics_parser.extract_browse_id(next_data)
  if is_pure_music or not lyrics_browse_id then
    return {}
  end

  -- 第 2 步：优先向 ANDROID_MUSIC 客户端拉取带毫秒级精准时间戳的歌词
  local android_data, android_err = transport.post_music("browse", {
    browseId = lyrics_browse_id
  }, constants.CLIENT_ANDROID_MUSIC)

  if android_data then
    local timed_result = lyrics_parser.parse_lyrics(android_data)
    if #timed_result > 0 then
      return timed_result
    end
  end

  -- 第 3 步：若 Android 客户端未命中任何词，回退至 WEB_REMIX 客户端获取静态文本
  local web_data, web_err = transport.post_music("browse", {
    browseId = lyrics_browse_id
  }, constants.CLIENT_WEB_REMIX)

  if web_data then
    return lyrics_parser.parse_lyrics(web_data)
  end

  return {}
end

return lyrics_service
