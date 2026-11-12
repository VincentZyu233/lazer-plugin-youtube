local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local store = require("ytm.core.store")
local stream_parser = require("ytm.parsers.stream")

local stream_service = {}

--- 获取指定 videoId 的高保真防卡断音频直链
function stream_service.get_audio_url(video_id, target_quality)
  if not video_id or type(video_id) ~= "string" or string.len(video_id) == 0 then
    error("Invalid videoId", 0)
  end

  transport.ensure_visitor_data()

  local payload = {
    videoId = video_id,
    playbackContext = {
      contentPlaybackContext = {
        html5Preference = "HTML5_PREF_WANTS",
        signatureTimestamp = 20760
      }
    },
    contentCheckOk = true,
    racyCheckOk = true
  }

  local res, err = transport.post_youtube("player?prettyPrint=false", payload, constants.CLIENT_VISIONOS)
  if not res then
    error("YouTube player request failed: " .. tostring(err), 0)
  end

  local parsed = stream_parser.parse_audio_stream(res, video_id, target_quality)

  local ua = constants.CLIENT_VISIONOS.userAgent
  local stream_headers = {
    ["User-Agent"] = ua,
    ["Origin"] = "https://www.youtube.com",
    ["Referer"] = "https://www.youtube.com/",
    ["Range"] = "bytes=0-",
    ["Accept"] = "*/*",
    ["Accept-Encoding"] = "identity",
    ["Connection"] = "keep-alive"
  }

  local user_cookie = store.get_cookie()
  if user_cookie and string.len(user_cookie) > 0 then
    stream_headers["Cookie"] = user_cookie
  end

  return {
    url = parsed.url,
    bitRate = parsed.bitRate,
    suffix = parsed.suffix,
    contentType = parsed.contentType,
    size = parsed.size,
    transcoded = false,
    headers = stream_headers
  }
end

return stream_service
