local stream_parser = {}

--- 解析 player 接口返回的 streamingData，选择最优音频流
function stream_parser.parse_audio_stream(data, video_id, target_quality)
  if not data or type(data) ~= "table" then
    error("Invalid player response", 0)
  end

  local streaming_data = data.streamingData
  if not streaming_data then
    local status = data.playabilityStatus
    local reason = (status and status.reason) or "No streamingData found"
    error("YouTube playback error: " .. reason, 0)
  end

  local formats = streaming_data.adaptiveFormats or {}
  local itag_map = {}
  local webm_list = {}
  local m4a_list = {}

  for _, fmt in ipairs(formats) do
    local mime = fmt.mimeType or ""
    if string.find(mime, "audio/") then
      local audio_url = fmt.url
      if audio_url and string.len(audio_url) > 0 then
        local itag = tonumber(fmt.itag)
        if itag then
          itag_map[itag] = fmt
        end
        if string.find(mime, "webm") or string.find(mime, "opus") then
          table.insert(webm_list, fmt)
        else
          table.insert(m4a_list, fmt)
        end
      end
    end
  end

  -- 智能流速适配算法 (Anti-Throttling)
  -- 首选 itag 250 (~90kbps = 11.4 KB/s)，缓冲持续增长，完美流畅永不卡顿
  local selected = nil
  local q = string.lower(tostring(target_quality or "high"))

  if q == "original" or q == "lossless" then
    selected = itag_map[251] or itag_map[250] or itag_map[140] or itag_map[249]
  elseif q == "low" or q == "standard" then
    selected = itag_map[249] or itag_map[139] or itag_map[250] or itag_map[140]
  else
    selected = itag_map[250] or itag_map[249] or itag_map[140] or itag_map[251]
  end

  if not selected then
    selected = webm_list[1] or m4a_list[1]
  end

  if not selected or not selected.url then
    error("No unencrypted direct audio stream found for video: " .. tostring(video_id), 0)
  end

  local mime = selected.mimeType or "audio/webm; codecs=\"opus\""
  local suffix = "webm"
  if string.find(mime, "mp4") or string.find(mime, "m4a") then
    suffix = "m4a"
  end

  return {
    url = selected.url,
    bitRate = selected.bitrate or 96000,
    suffix = suffix,
    contentType = mime,
    size = tonumber(selected.contentLength)
  }
end

return stream_parser
