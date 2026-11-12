local transport = require("ytm.core.transport")
local constants = require("ytm.core.constants")
local nav = require("ytm.core.navigation")
local search_parser = require("ytm.parsers.search")

local discover_service = {}

--- 首页探索推荐流
function discover_service.home_feed()
  transport.ensure_visitor_data()
  local payload = {
    browseId = "FEmusic_home"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  if not data then return { sections = {} } end

  local music_items = {}
  nav.find_music_items(data, music_items)

  local songs = {}
  local seen_songs = {}
  for _, it in ipairs(music_items) do
    local s = search_parser.parse_song_item(it, nil, seen_songs)
    if s then table.insert(songs, s) end
  end

  return {
    sections = {
      {
        title = "YouTube Music 推荐",
        items = songs
      }
    }
  }
end

--- 排行榜
function discover_service.charts()
  transport.ensure_visitor_data()
  local payload = {
    browseId = "FEmusic_charts"
  }
  local data = transport.post_music("browse", payload, constants.CLIENT_WEB_REMIX)
  if not data then return { charts = {} } end

  local music_items = {}
  nav.find_music_items(data, music_items)

  local songs = {}
  local seen_songs = {}
  for _, it in ipairs(music_items) do
    local s = search_parser.parse_song_item(it, nil, seen_songs)
    if s then table.insert(songs, s) end
  end

  return {
    charts = {
      {
        id = "yt_charts_top",
        title = "热门榜单",
        items = songs
      }
    }
  }
end

--- 电台
function discover_service.radio(args)
  return { items = {} }
end

return discover_service
