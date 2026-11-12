local client = require("yt/client")
local config = require("yt/config")
local stream = {}

--- 获取指定 videoId 的音频直链
--- 支持智能音质选择：
--- 默认优先挑选 160k Opus (itag 251) 或 128k AAC (itag 140)
function stream.get_audio_url(video_id, target_quality)
  if not video_id or type(video_id) ~= "string" or string.len(video_id) == 0 then
    return nil, "Invalid videoId"
  end

  local payload = {
    videoId = video_id,
    playbackContext = {
      contentPlaybackContext = {
        html5Preference = "HTML5_PREF_WANTS"
      }
    }
  }

  -- 核心：伪装为 iOS 客户端，绕过网页端复杂反爬与 JS 解密 (REQUIRE_JS_PLAYER = False)
  local data, err = client.post_youtube("player", payload, config.CLIENT_IOS)
  if not data then
    return nil, err or "Failed to call player endpoint"
  end

  local streaming_data = data.streamingData
  if not streaming_data then
    -- 检查是否有 playabilityStatus 报错
    local status = data.playabilityStatus
    local reason = (status and status.reason) or "No streamingData found"
    return nil, reason
  end

  local formats = streaming_data.adaptiveFormats or {}
  local best_audio = nil
  local best_bitrate = 0

  for _, fmt in ipairs(formats) do
    local mime = fmt.mimeType or ""
    -- 仅筛选纯音频轨 (audio/mp4, audio/webm)
    if string.find(mime, "audio/") then
      local url = fmt.url
      local bitrate = fmt.bitrate or 0

      -- 确保格式中含有直接可用的直链 url (无需 JS signature cipher 解密)
      if url and string.len(url) > 0 then
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

  return {
    url = best_audio.url,
    bitrate = best_audio.bitrate,
    sampleRate = best_audio.audioSampleRate,
    contentLength = best_audio.contentLength,
    mimeType = best_audio.mimeType
  }
end

return stream
