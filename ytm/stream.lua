local stream_service = require("ytm.services.stream")

local stream = {}

function stream.get_audio_url(video_id, target_quality)
  return stream_service.get_audio_url(video_id, target_quality)
end

return stream
