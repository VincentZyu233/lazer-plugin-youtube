local catalog = require("yt/catalog")
local stream = require("yt/stream")

local plugin = {}

--- 插件初始化
function plugin.init()
  return true
end

--- 会话状态检查
function plugin.checkSession()
  return {
    valid = true,
    user = {
      id = "guest",
      name = "YouTube Guest",
      avatar = "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
    }
  }
end

--- 综合搜索
function plugin.search(query, page, limit)
  return catalog.search(query, page, limit)
end

--- 获取音频播放直链
function plugin.stream(track_id, quality)
  local result, err = stream.get_audio_url(track_id, quality)
  if not result then
    return nil, err
  end
  return {
    url = result.url,
    bitrate = result.bitrate,
    format = "m4a"
  }
end

--- 单曲详情
function plugin.song(track_id)
  return {
    id = track_id,
    name = "YouTube Track (" .. tostring(track_id) .. ")",
    cover = "https://i.ytimg.com/vi/" .. tostring(track_id) .. "/hqdefault.jpg"
  }
end

--- 歌词占位
function plugin.lyrics(track_id)
  return {
    lrc = ""
  }
end

return plugin
