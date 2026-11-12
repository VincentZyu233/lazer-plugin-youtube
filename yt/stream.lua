local client = require("yt.client")
local config = require("yt.config")
local stream = {}

--- 获取指定 videoId 的音频直链
--- 采用 VisionOS 客户端与 Visitor 会话签名，直出无加密 Opus/AAC 直链
function stream.get_audio_url(video_id, target_quality)
  if not video_id or type(video_id) ~= "string" or string.len(video_id) == 0 then
    error("Invalid videoId", 0)
  end

  local visitor_data = client.ensure_visitor_data()

  local client_ctx = {}
  for k, v in pairs(config.CLIENT_VISIONOS) do
    client_ctx[k] = v
  end
  if visitor_data and string.len(visitor_data) > 0 then
    client_ctx.visitorData = visitor_data
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
    racyCheckOk = true,
    context = {
      client = client_ctx
    }
  }

  local ua = config.CLIENT_VISIONOS.userAgent
  local headers = {
    ["X-YouTube-Client-Name"] = "101",
    ["X-YouTube-Client-Version"] = "1.02",
    ["Origin"] = "https://www.youtube.com",
    ["User-Agent"] = ua,
    ["Content-Type"] = "application/json"
  }

  if visitor_data and string.len(visitor_data) > 0 then
    headers["X-Goog-Visitor-Id"] = visitor_data
  end

  local cookie = client.get_cookie()
  if cookie and string.len(cookie) > 0 then
    headers["Cookie"] = cookie
  end

  local url = config.HOST_YOUTUBE .. "/youtubei/v1/player?prettyPrint=false"
  local res = host.http({
    url = url,
    method = "POST",
    headers = headers,
    body = host.json_encode(payload)
  })

  if not res or res.status ~= 200 then
    error("YouTube player request failed: HTTP " .. tostring(res and res.status or "nil"), 0)
  end

  local ok, data = pcall(host.json_decode, res.body)
  if not ok or not data then
    error("Failed to parse YouTube player response", 0)
  end

  if data.responseContext and data.responseContext.visitorData then
    client.set_visitor_data(data.responseContext.visitorData)
  end

  local streaming_data = data.streamingData
  if not streaming_data then
    local status = data.playabilityStatus
    local reason = (status and status.reason) or "No streamingData found"
    error("YouTube playback error: " .. reason, 0)
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
    error("No unencrypted direct audio stream found for video: " .. video_id, 0)
  end

  local mime = best_audio.mimeType or "audio/webm"
  local suffix = "webm"
  if string.find(mime, "mp4") or string.find(mime, "m4a") then
    suffix = "m4a"
  end

  -- 对齐 Lazer 宿主 MusicStream 契约字段
  return {
    url = best_audio.url,
    bitRate = best_audio.bitrate or 128000,
    suffix = suffix,
    contentType = mime,
    transcoded = false,
    headers = {
      ["User-Agent"] = ua,
      ["Origin"] = "https://www.youtube.com"
    }
  }
end

return stream
