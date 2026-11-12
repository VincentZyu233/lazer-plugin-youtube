local client = require("yt.client")
local config = require("yt.config")
local catalog = {}

-- 提取文本（兼容 runs 结构与 simpleText）
local function extract_text(obj)
  if not obj then return "" end
  if type(obj) == "string" then return obj end
  if obj.simpleText then return obj.simpleText end
  if obj.runs and type(obj.runs) == "table" then
    local parts = {}
    for _, r in ipairs(obj.runs) do
      if r.text then
        table.insert(parts, r.text)
      end
    end
    return table.concat(parts, "")
  end
  return ""
end

-- 提取最佳缩略图
local function extract_thumbnail(thumbnails)
  if not thumbnails or type(thumbnails) ~= "table" then
    return ""
  end
  local best_url = ""
  local max_w = 0
  for _, item in ipairs(thumbnails) do
    local w = item.width or 0
    if w >= max_w and item.url then
      max_w = w
      best_url = item.url
    end
  end
  return best_url
end

--- 尝试从用户输入中提取 YouTube 11位视频 ID
local function try_extract_video_id(input)
  if not input or type(input) ~= "string" then return nil end
  local id = string.match(input, "youtu%.be/([%w%-_]+)")
  if id and string.len(id) == 11 then return id end

  id = string.match(input, "[%?&]v=([%w%-_]+)")
  if id and string.len(id) == 11 then return id end

  if string.len(input) == 11 and string.match(input, "^[%w%-_]+$") then
    return input
  end
  return nil
end

--- 搜索单曲与视频
function catalog.search(args)
  local query = tostring(args and args.query or "")
  if string.len(query) == 0 then
    return { songs = {}, albums = {}, artists = {}, playlists = {} }
  end

  -- 特性 1：如果用户粘贴了 YouTube 链接，秒开对应视频
  local direct_id = try_extract_video_id(query)
  if direct_id then
    return {
      songs = {
        {
          id = direct_id,
          name = "YouTube Video (" .. direct_id .. ")",
          artists = { { id = "yt_channel", name = "YouTube" } },
          album = { id = "yt_album_" .. direct_id, name = "YouTube Single", cover = "https://i.ytimg.com/vi/" .. direct_id .. "/hqdefault.jpg" },
          cover = "https://i.ytimg.com/vi/" .. direct_id .. "/hqdefault.jpg",
          duration = 0
        }
      },
      albums = {},
      artists = {},
      playlists = {}
    }
  end

  -- 特性 2：通过 InnerTube 进行关键词多维搜索
  local payload = {
    query = query
  }
  local data, err = client.post_youtube("search", payload, config.CLIENT_IOS)
  if not data then
    return { songs = {}, albums = {}, artists = {}, playlists = {} }
  end

  local songs = {}
  local contents = data.contents
  local section_list = contents and contents.sectionListRenderer
  local sections = (section_list and section_list.contents) or {}

  for _, sec in ipairs(sections) do
    local item_section = sec.itemSectionRenderer
    local items = (item_section and item_section.contents) or {}
    for _, it in ipairs(items) do
      local vr = it.videoRenderer or it.compactVideoRenderer
      if vr and vr.videoId then
        local vid = vr.videoId
        local title = extract_text(vr.title)
        local artist_name = extract_text(vr.ownerText or vr.shortBylineText)
        local cover_url = extract_thumbnail(vr.thumbnail and vr.thumbnail.thumbnails)
        if string.len(cover_url) == 0 then
          cover_url = "https://i.ytimg.com/vi/" .. vid .. "/hqdefault.jpg"
        end

        local dur_sec = 0
        local dur_text = extract_text(vr.lengthText)
        if dur_text and string.len(dur_text) > 0 then
          local min, sec_part = string.match(dur_text, "(%d+):(%d+)")
          if min and sec_part then
            dur_sec = (tonumber(min) or 0) * 60 + (tonumber(sec_part) or 0)
          end
        end

        table.insert(songs, {
          id = vid,
          name = title,
          artists = {
            { id = "yt_artist_" .. vid, name = string.len(artist_name) > 0 and artist_name or "YouTube" }
          },
          album = {
            id = "yt_album_" .. vid,
            name = "YouTube Single",
            cover = cover_url
          },
          cover = cover_url,
          duration = dur_sec
        })
      end
    end
  end

  return {
    songs = songs,
    albums = {},
    artists = {},
    playlists = {}
  }
end

function catalog.song(id)
  return {
    id = id,
    name = "YouTube Video (" .. tostring(id) .. ")",
    artists = { { id = "yt_channel", name = "YouTube" } },
    album = { id = "yt_album_" .. tostring(id), name = "YouTube Audio" },
    cover = "https://i.ytimg.com/vi/" .. tostring(id) .. "/hqdefault.jpg",
    duration = 0
  }
end

return catalog
