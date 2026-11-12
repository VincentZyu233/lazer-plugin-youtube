local nav = require("ytm.core.navigation")
local constants = require("ytm.core.constants")

local lyrics_parser = {}

--- 从 /next 响应中提取歌词 Tab 的 browseId 或检测是否纯音乐
-- 返回: browse_id (string 或 nil), is_pure_music (boolean)
function lyrics_parser.extract_browse_id(next_data)
  if not next_data or type(next_data) ~= "table" then
    return nil, false
  end

  local tabs = nav.nav(next_data, {
    "contents",
    "singleColumnMusicWatchNextResultsRenderer",
    "tabbedRenderer",
    "watchNextTabbedResultsRenderer",
    "tabs"
  })

  if not tabs or type(tabs) ~= "table" then
    return nil, false
  end

  for _, t in ipairs(tabs) do
    local rend = t.tabRenderer
    if rend then
      local endpoint = rend.endpoint and rend.endpoint.browseEndpoint
      local b_id = endpoint and endpoint.browseId
      local is_lyrics_tab = (b_id and type(b_id) == "string" and string.sub(b_id, 1, 4) == "MPLY")
                            or rend.title == "歌词" or rend.title == "Lyrics"

      if is_lyrics_tab then
        if rend.unselectable == true then
          return nil, true
        end
        return b_id, false
      end
    end
  end

  return nil, false
end

--- 解析 /browse 返回的歌词 JSON
-- 返回: results (table), has_precise_cues (boolean)
function lyrics_parser.parse_lyrics(browse_data)
  if not browse_data or type(browse_data) ~= "table" then
    return {}, false
  end

  -- ==========================================================
  -- 分支 1: 毫秒级时间戳歌词 (ANDROID_MUSIC timedLyricsData)
  -- ==========================================================
  local timed_model = nav.nav(browse_data, constants.PATHS.TIMESTAMPED_LYRICS)
  local timed_items = timed_model and timed_model.timedLyricsData

  if timed_items and type(timed_items) == "table" and #timed_items > 0 then
    local lines = {}
    local lrc_rows = {}
    local current_stepped_ms = 0
    local step_ms = 4000
    local has_cues = false

    for _, item in ipairs(timed_items) do
      local line_text = nav.trim_str(item.lyricLine or "")
      local cue = item.cueRange
      local start_ms = nil
      if cue and cue.startTimeMilliseconds then
        start_ms = tonumber(cue.startTimeMilliseconds)
        has_cues = true
      end

      if not start_ms then
        start_ms = current_stepped_ms
        current_stepped_ms = current_stepped_ms + step_ms
      else
        current_stepped_ms = start_ms + step_ms
      end

      if string.len(line_text) > 0 then
        local stamp = nav.ms_to_lrc_tag(start_ms)
        table.insert(lines, {
          text = line_text,
          startMs = start_ms
        })
        table.insert(lrc_rows, stamp .. line_text)
      end
    end

    if #lines > 0 then
      return {
        {
          lines = lines,
          synced = true,
          lrc = table.concat(lrc_rows, "\n")
        }
      }, has_cues
    end
  end

  -- ==========================================================
  -- 分支 2: 静态全本歌词回退 (WEB_REMIX musicDescriptionShelfRenderer)
  -- ==========================================================
  local section_list = nav.nav(browse_data, { "contents", "sectionListRenderer", "contents" })
  local raw_text = ""
  local footer_text = ""

  if section_list and type(section_list) == "table" then
    for _, sec in ipairs(section_list) do
      local shelf = sec.musicDescriptionShelfRenderer
      if shelf then
        if shelf.description and shelf.description.runs then
          local parts = {}
          for _, r in ipairs(shelf.description.runs) do
            if r.text then table.insert(parts, r.text) end
          end
          raw_text = table.concat(parts, "")
        end
        if shelf.footer and shelf.footer.runs then
          local f_parts = {}
          for _, fr in ipairs(shelf.footer.runs) do
            if fr.text then table.insert(f_parts, fr.text) end
          end
          footer_text = table.concat(f_parts, "")
        end
        if string.len(raw_text) > 0 then break end
      end
    end
  end

  if string.len(raw_text) == 0 then
    return {}, false
  end

  local lines = {}
  local lrc_rows = {}
  local step_ms = 4000
  local current_ms = 0

  for _, line in ipairs(nav.split_lines(raw_text)) do
    local trimmed = nav.trim_str(line)
    if string.len(trimmed) > 0 then
      local stamp = nav.ms_to_lrc_tag(current_ms)
      table.insert(lines, {
        text = trimmed,
        startMs = current_ms
      })
      table.insert(lrc_rows, stamp .. trimmed)
      current_ms = current_ms + step_ms
    end
  end

  if #lines == 0 then
    return {}, false
  end

  if string.len(footer_text) > 0 then
    local stamp = nav.ms_to_lrc_tag(current_ms)
    table.insert(lines, {
      text = footer_text,
      startMs = current_ms
    })
    table.insert(lrc_rows, stamp .. footer_text)
  end

  return {
    {
      lines = lines,
      synced = true,
      lrc = table.concat(lrc_rows, "\n")
    }
  }, false
end

return lyrics_parser
