local config = {}

config.HOST_MUSIC = "https://music.youtube.com"
config.HOST_YOUTUBE = "https://www.youtube.com"
config.API_VERSION = "v1"

-- InnerTube 客户端预设（与 yt-dlp 核心定义对齐）
config.CLIENT_IOS = {
  clientName = "IOS",
  clientVersion = "21.26.4",
  deviceMake = "Apple",
  deviceModel = "iPhone16,2",
  userAgent = "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
  osName = "iPhone",
  osVersion = "18.3.2.22D82",
  hl = "zh-CN",
  gl = "US"
}

config.CLIENT_WEB_REMIX = {
  clientName = "WEB_REMIX",
  clientVersion = "1.20260707.12.00",
  hl = "zh-CN",
  gl = "US"
}

return config
