local catalog_service = require("ytm.services.catalog")
local lyrics_service = require("ytm.services.lyrics")

local catalog = {}

function catalog.search(args)
  return catalog_service.search(args)
end

function catalog.song(id)
  return catalog_service.song(id)
end

function catalog.favorites(args)
  return catalog_service.favorites(args)
end

function catalog.lyrics(song_id)
  return lyrics_service.get_lyrics(song_id)
end

return catalog
