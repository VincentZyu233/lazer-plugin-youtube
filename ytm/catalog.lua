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

function catalog.set_favorite(args)
  return catalog_service.set_favorite(args)
end

function catalog.playlist(id)
  return catalog_service.playlist(id)
end

function catalog.playlists(args)
  return catalog_service.playlists(args)
end

function catalog.playlist_songs(id, limit, offset)
  return catalog_service.playlist_songs(id, limit, offset)
end

function catalog.album(id)
  return catalog_service.album(id)
end

function catalog.album_songs(id, limit, offset)
  return catalog_service.album_songs(id, limit, offset)
end

function catalog.artist(id)
  return catalog_service.artist(id)
end

function catalog.artist_songs(id, limit, offset)
  return catalog_service.artist_songs(id, limit, offset)
end

function catalog.lyrics(song_id)
  return lyrics_service.get_lyrics(song_id)
end

return catalog
