local constants = {}

constants.HOST_MUSIC = "https://music.youtube.com"
constants.HOST_YOUTUBE = "https://www.youtube.com"
constants.API_VERSION = "v1"

-- InnerTube 搜索与常规目录客户端 (Web Remix，目录丰富，分类最全)
constants.CLIENT_WEB_REMIX = {
  clientName = "WEB_REMIX",
  clientVersion = "1.20260707.12.00",
  hl = "zh-CN",
  gl = "US",
  userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
}

-- InnerTube 官方移动客户端 (Android Music，专用于抓取毫秒级精准时间戳歌词)
constants.CLIENT_ANDROID_MUSIC = {
  clientName = "ANDROID_MUSIC",
  clientVersion = "7.21.50",
  hl = "zh-CN",
  gl = "US",
  userAgent = "com.google.android.apps.youtube.music/7.21.50 (Linux; U; Android 14; en_US; Pixel 8 Pro)"
}

-- InnerTube 播放流客户端 (VisionOS，原生直链免解密)
constants.CLIENT_VISIONOS = {
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

-- InnerTube 常用 JSON Navigation 路径常量 (借鉴 ytmusicapi)
constants.PATHS = {
  TIMESTAMPED_LYRICS = {
    "contents",
    "elementRenderer",
    "newElement",
    "type",
    "componentType",
    "model",
    "timedLyricsModel",
    "lyricsData"
  },
  DESCRIPTION_SHELF = {
    "musicDescriptionShelfRenderer"
  }
}

return constants
