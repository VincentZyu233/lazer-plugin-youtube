local nav = {}

--- ytmusicapi 原生同款深度寻址函数
-- 按照 path 数组依次下钻，遇到任何 nil 或非 table 立即返回 nil，杜绝深度判空异常
function nav.nav(root, path)
  if root == nil or type(path) ~= "table" then return nil end
  local curr = root
  for i = 1, #path do
    if type(curr) ~= "table" then return nil end
    local k = path[i]
    curr = curr[k]
    if curr == nil then return nil end
  end
  return curr
end

--- 在数组中按 key 查找首个匹配对象
function nav.find_object_by_key(list, key)
  if type(list) ~= "table" then return nil end
  for _, item in ipairs(list) do
    if type(item) == "table" and item[key] ~= nil then
      return item[key]
    end
  end
  return nil
end

--- 递归收集页面中所有的 musicResponsiveListItemRenderer
function nav.find_music_items(node, acc)
  if type(node) ~= "table" then return end
  if node.musicResponsiveListItemRenderer then
    table.insert(acc, node.musicResponsiveListItemRenderer)
    return
  end
  for _, v in pairs(node) do
    if type(v) == "table" then
      nav.find_music_items(v, acc)
    end
  end
end

--- 提取 InnerTube runs 或 simpleText 文本
function nav.extract_text(runs_obj)
  if not runs_obj or type(runs_obj) ~= "table" then return "" end
  if runs_obj.simpleText then return tostring(runs_obj.simpleText) end
  if runs_obj.runs and type(runs_obj.runs) == "table" then
    local parts = {}
    for _, r in ipairs(runs_obj.runs) do
      if r.text then table.insert(parts, r.text) end
    end
    return table.concat(parts, "")
  end
  return ""
end

--- 从封面列表选取最高清 URL
function nav.extract_thumbnail(thumbnails)
  if not thumbnails or type(thumbnails) ~= "table" or #thumbnails == 0 then
    return ""
  end
  local best_url = ""
  local max_w = 0
  for _, t in ipairs(thumbnails) do
    local w = tonumber(t.width) or 0
    if w >= max_w and t.url then
      max_w = w
      best_url = t.url
    end
  end
  if best_url == "" and thumbnails[#thumbnails] and thumbnails[#thumbnails].url then
    best_url = thumbnails[#thumbnails].url
  end
  if string.sub(best_url, 1, 2) == "//" then
    best_url = "https:" .. best_url
  end
  return best_url
end

--- 格式化时间字符串（如 "03:45" 或 "1:02:15"）为毫秒数
function nav.parse_time_to_ms(str)
  if not str or type(str) ~= "string" or string.len(str) == 0 then return 0 end
  local parts = {}
  local pos = 1
  local len = string.len(str)
  while pos <= len do
    local colon = string.find(str, ":", pos, true)
    if colon then
      local seg = string.sub(str, pos, colon - 1)
      local num = tonumber(seg)
      if num then table.insert(parts, num) else return 0 end
      pos = colon + 1
    else
      local seg = string.sub(str, pos)
      local num = tonumber(seg)
      if num then table.insert(parts, num) else return 0 end
      break
    end
  end

  if #parts == 2 then
    return (parts[1] * 60 + parts[2]) * 1000
  elseif #parts == 3 then
    return (parts[1] * 3600 + parts[2] * 60 + parts[3]) * 1000
  end
  return 0
end

--- 毫秒转换为标准 LRC 时间戳标签 [mm:ss.xx]
function nav.ms_to_lrc_tag(ms)
  local total_ms = tonumber(ms) or 0
  if total_ms < 0 then total_ms = 0 end
  local minutes = math.floor(total_ms / 60000)
  local seconds = math.floor((total_ms % 60000) / 1000)
  local centis = math.floor((total_ms % 1000) / 10)
  return string.format("[%02d:%02d.%02d]", minutes, seconds, centis)
end

--- 纯文本修剪前后空白
function nav.trim_str(s)
  if not s or type(s) ~= "string" then return "" end
  local len = string.len(s)
  local start_i = 1
  while start_i <= len do
    local b = string.byte(s, start_i)
    if b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then break end
    start_i = start_i + 1
  end
  local end_i = len
  while end_i >= start_i do
    local b = string.byte(s, end_i)
    if b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 then break end
    end_i = end_i - 1
  end
  if start_i > end_i then return "" end
  return string.sub(s, start_i, end_i)
end

--- 安全纯文本按行切分
-- 彻底规避 Dart lua_dardo_plus 在 string.gmatch 上的 RangeError 越界缺陷
function nav.split_lines(str)
  local lines = {}
  if not str or type(str) ~= "string" or string.len(str) == 0 then
    return lines
  end
  local pos = 1
  local len = string.len(str)
  while pos <= len do
    local nl_pos = string.find(str, "\n", pos, true)
    if nl_pos then
      local line = string.sub(str, pos, nl_pos - 1)
      if string.len(line) > 0 and string.sub(line, -1) == "\r" then
        line = string.sub(line, 1, -2)
      end
      table.insert(lines, line)
      pos = nl_pos + 1
    else
      local line = string.sub(str, pos)
      if string.len(line) > 0 and string.sub(line, -1) == "\r" then
        line = string.sub(line, 1, -2)
      end
      table.insert(lines, line)
      break
    end
  end
  return lines
end

--- 纯字符流提取数字 (完全脱离任何 Lua 正则 / 模式串，100% 兼容 Dart lua_dardo_plus 沙箱)
local function extract_number(str)
  if not str or type(str) ~= "string" then return nil end
  local len = string.len(str)
  local in_num = false
  local num_chars = {}
  local has_dot = false
  for i = 1, len do
    local b = string.byte(str, i)
    if b >= 48 and b <= 57 then
      in_num = true
      table.insert(num_chars, string.char(b))
    elseif b == 46 and in_num and not has_dot then
      has_dot = true
      table.insert(num_chars, ".")
    elseif in_num and b ~= 44 then -- 遇到千分位逗号静默忽略，遇到其他非数字跳出
      break
    end
  end
  if #num_chars > 0 then
    return tonumber(table.concat(num_chars))
  end
  return nil
end

--- 判断是否为播放量/统计数文本 (如 "播放次数：1743万", "17M views", "850K", "每月听众：70.4万")
function nav.is_play_count(str)
  if not str or type(str) ~= "string" or string.len(str) == 0 then return false end
  local s = nav.trim_str(str)

  -- 排除时长文本 (如 "3:23", "04:15")，除非明确包含 "播放" 等统计词根
  if string.find(s, ":", 1, true) or string.find(s, "：", 1, true) then
    if not (string.find(s, "播放", 1, true) or string.find(s, "視聴", 1, true) or string.find(s, "view", 1, true)) then
      return false
    end
  end

  if string.find(s, "播放", 1, true)
     or string.find(s, "視聴", 1, true)
     or string.find(s, "views", 1, true)
     or string.find(s, "view", 1, true)
     or string.find(s, "次观看", 1, true)
     or string.find(s, "回視聴", 1, true)
     or string.find(s, "听众", 1, true)
     or string.find(s, "订阅", 1, true)
     or string.find(s, "subscriber", 1, true) then
    return true
  end

  -- 中文单位判定: 包含万、亿，且包含任意数字字节
  if string.find(s, "万", 1, true) or string.find(s, "亿", 1, true) then
    for i = 1, string.len(s) do
      local b = string.byte(s, i)
      if b >= 48 and b <= 57 then return true end
    end
  end

  -- 英文缩写单位: 以数字开头并包含 K / M / B (如 "850K", "17M")
  local has_kmb = string.find(s, "K", 1, true) or string.find(s, "k", 1, true)
               or string.find(s, "M", 1, true) or string.find(s, "m", 1, true)
               or string.find(s, "B", 1, true) or string.find(s, "b", 1, true)
  if has_kmb then
    local first_b = string.byte(s, 1)
    if first_b and first_b >= 48 and first_b <= 57 then
      return true
    end
  end

  return false
end

--- 格式化播放量为 YouTube 常见的 K / M / B 字符串 (如 "17M", "3.4M", "850K")
-- 彻底规避任何 Lua 模式匹配（规避 Dart RegExp %d 陷阱与多捕获组丢失）
function nav.format_play_count(str)
  if not nav.is_play_count(str) then return nil end
  local s = nav.trim_str(str)
  local num = extract_number(s)
  if not num then return nil end

  local total = nil

  if string.find(s, "亿", 1, true) then
    total = num * 100000000
  elseif string.find(s, "万", 1, true) then
    total = num * 10000
  else
    local has_b = string.find(s, "B", 1, true) or string.find(s, "b", 1, true)
    local has_m = string.find(s, "M", 1, true) or string.find(s, "m", 1, true)
    local has_k = string.find(s, "K", 1, true) or string.find(s, "k", 1, true)
    if has_b then
      total = num * 1000000000
    elseif has_m then
      total = num * 1000000
    elseif has_k then
      total = num * 1000
    else
      total = num
    end
  end

  if not total then return nil end

  if total >= 1000000000 then
    local b = total / 1000000000
    return string.format("%.1fB", b)
  elseif total >= 10000000 then
    local m = math.floor(total / 1000000 + 0.5)
    return string.format("%dM", m)
  elseif total >= 1000000 then
    local m = total / 1000000
    return string.format("%.1fM", m)
  elseif total >= 1000 then
    local k = math.floor(total / 1000 + 0.5)
    return string.format("%dK", k)
  else
    return string.format("%d", math.floor(total))
  end
end

return nav
