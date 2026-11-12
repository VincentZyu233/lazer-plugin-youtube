local client = require("yt.client")
local config = require("yt.config")
local stream = {}

--- 获取指定 videoId 的音频直链
--- 优先挑选 160k Opus (itag 251) 或 128k AAC (itag 140)
function stream.get_audio_url(video_id, target_quality)
  if not video_id or type(video_id) ~= "string" or string.len(video_id) == 0 then
    return nil, "Invalid videoId"
  end

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

  local ctx = {
    client = config.CLIENT_VISIONOS
  }
  payload.context = ctx

  local headers = {
    ["X-YouTube-Client-Name"] = "101",
    ["X-YouTube-Client-Version"] = "1.02",
    ["Origin"] = "https://www.youtube.com",
    ["User-Agent"] = config.CLIENT_VISIONOS.userAgent,
    ["Content-Type"] = "application/json"
  }

  local url = config.HOST_YOUTUBE .. "/youtubei/v1/player"
  local res = host.http({
    url = url,
    method = "POST",
    headers = headers,
    body = host.json_encode(payload)
  })

  if not res or res.status ~= 200 then
    return nil, "HTTP " .. tostring(res and res.status or "nil")
  end

  local ok, data = pcall(host.json_decode, res.body)
  if not ok or not data then
    return nil, "Failed to parse player response"
  end

  local streaming_data = data.streamingData
  if not streaming_data then
    local status = data.playabilityStatus
    local reason = (status and status.reason) or "No streamingData found"
    return nil, reason
  end

  local formats = streaming_data.adaptiveFormats or {}
  local best_audio = nil
  local best_bitrate = 0

  for _, fmt in ipairs(formats) do
    local mime = fmt.mimeType or ""
    if string.find(mime, "audio/") then
      local audio_url = fmt.url
      local bitrate = fmt.bitrate or 0

      if audio_url and string.len(audio_url) > 0 then
        if bitrate > best_bitrate then
          best_bitrate = bitrate
          best_audio = fmt
        end
      end
    end
  end

  if not best_audio or not best_audio.url then
    return nil, "No unencrypted direct audio stream found"
  end

  local mime = best_audio.mimeType or ""
  local ext = "m4a"
  if string.find(mime, "webm") or string.find(mime, "opus") then
    ext = "webm"
  end

  return {
    url = best_audio.url,
    bitrate = best_audio.bitrate or 128000,
    format = ext,
    duration = math.floor((tonumber(best_audio.approxDurationMs) or 0) / 1000)
  }
end

return stream
