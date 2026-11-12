local config = {}

config.HOST_MUSIC = "https://music.youtube.com"
config.HOST_YOUTUBE = "https://www.youtube.com"
config.API_VERSION = "v1"

-- InnerTube 搜索客户端（Web Remix，深度浅，分类全）
config.CLIENT_WEB_REMIX = {
  clientName = "WEB_REMIX",
  clientVersion = "1.20260707.12.00",
  hl = "zh-CN",
  gl = "US"
}

-- InnerTube 播放流客户端（VisionOS，yt-dlp 官方验证：直出无加密直链，无需 JS 求解器）
config.CLIENT_VISIONOS = {
  clientName = "VISIONOS",
  clientVersion = "1.02",
  deviceMake = "Apple",
  deviceModel = "RealityDevice17,1",
  userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
  osName = "visionOS",
  osVersion = "26.5.23O471",
  hl = "en",
  timeZone = "UTC",
  utcOffsetMinutes = 0
}

return config
