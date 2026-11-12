local catalog = require("yt.catalog")
local stream = require("yt.stream")

local plugin = {}

function plugin.call(operation, args)
  args = args or {}

  -- 1. 声明平台能力与元数据
  if operation == "describe" then
    return {
      providers = {
        {
          id = "youtube",
          name = "YouTube Music",
          auth = {},
          capabilities = {
            "search",
            "lyrics",
            "homeFeed",
            "radio",
            "recommendations"
          },
          loginHint = "免登录即用",
          cookieHint = "支持全球歌曲与视频音频流"
        }
      }
    }
  end

  -- 2. 伪会话（免登录）
  if operation == "session" then
    return {
      valid = true,
      user = {
        id = "guest",
        name = "YouTube Guest",
        avatar = "https://www.youtube.com/s/desktop/9906d203/img/favicon_144x144.png"
      }
    }
  end

  -- 3. 搜索与音频流
  if operation == "search" then
    return catalog.search(args)
  elseif operation == "stream" then
    local song_id = args.id or args.songId or ""
    local quality = args.quality or "standard"
    return stream.get_audio_url(song_id, quality)
  elseif operation == "song" then
    local song_id = args.id or args.songId or ""
    return catalog.song(song_id)
  elseif operation == "lyrics" then
    return { lrc = "" }
  elseif operation == "homeFeed" then
    return { sections = {} }
  end

  return nil
end

return plugin
