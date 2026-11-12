local client = require("ytm.client")
local config = require("ytm.config")
local stream = {}

--- 获取指定 videoId 的音频直链
--- 优先选用 WebM/Opus (itag 251)，原生流式封装容错高，防范单点卡断；无 WebM 时选用 M4A (itag 140)
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

  -- 智能流速适配算法 (Anti-Throttling & Buffer-Starvation Prevention)
  -- Google CDN 对单 TCP 连接有限速（~15.4 KB/s）。
  -- itag 251 (~170kbps = 21.3 KB/s) 消耗速度大于传输速度，24秒必然耗尽缓冲；
  -- itag 250 (~90kbps = 11.4 KB/s) 消耗速度小于传输速度，缓冲持续增长，完美流畅永不卡顿；
  -- Opus 90kbps 音质等效 MP3 192kbps，高保真同时提供稳定无阻断的收听体验。
  local selected = nil
  local q = string.lower(tostring(target_quality or "high"))

  if q == "original" or q == "lossless" then
    -- 无损/原生模式：允许挑战最高码率
    selected = itag_map[251] or itag_map[250] or itag_map[140] or itag_map[249]
  elseif q == "low" or q == "standard" then
    -- 省流模式：itag 249 (Opus ~70k) 或 139 (AAC ~48k)
    selected = itag_map[249] or itag_map[139] or itag_map[250] or itag_map[140]
  else
    -- 默认/极高/较高模式：首选 itag 250，坚决保证缓冲跑赢播放
    selected = itag_map[250] or itag_map[249] or itag_map[140] or itag_map[251]
  end

  if not selected then
    selected = webm_list[1] or m4a_list[1]
  end

  if not selected or not selected.url then
    error("No unencrypted direct audio stream found for video: " .. video_id, 0)
  end

  local mime = selected.mimeType or "audio/webm; codecs=\"opus\""
  local suffix = "webm"
  if string.find(mime, "mp4") or string.find(mime, "m4a") then
    suffix = "m4a"
  end

  local reported_size = tonumber(selected.contentLength)

  local stream_headers = {
    ["User-Agent"] = ua,
    ["Origin"] = "https://www.youtube.com",
    ["Referer"] = "https://www.youtube.com/"
  }

  local user_cookie = host.storage_get("user_cookie")
  if user_cookie and string.len(user_cookie) > 0 then
    stream_headers["Cookie"] = user_cookie
  end

  return {
    url = selected.url,
    bitRate = selected.bitrate or 96000,
    suffix = suffix,
    contentType = mime,
    size = reported_size,
    transcoded = false,
    headers = stream_headers
  }
end

return stream
