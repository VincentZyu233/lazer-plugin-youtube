-- test/test_digit_extractor.lua
-- 单元测试：纯字符流国际化播放量识别与数字提取器
-- 验证核心：彻底规避 Lua 正则表达式转义，兼容 Lazer Dart 运行沙箱

package.path = "?.lua;ytm/?.lua;" .. package.path

local nav = require("ytm.core.navigation")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s | Expected: %s, Actual: %s", tostring(msg), tostring(expected), tostring(actual)), 2)
  end
end

print(">>> [Test 1] 验证播放量识别与格式化 (中/英/日多语言)...")

local test_cases = {
  -- 中文
  { input = "播放次数：1743万", expected_is = true, expected_fmt = "17M Plays" },
  { input = "1743万次播放", expected_is = true, expected_fmt = "17M Plays" },
  { input = "340万次播放", expected_is = true, expected_fmt = "3.4M Plays" },
  { input = "850K次播放", expected_is = true, expected_fmt = "850K Plays" },
  { input = "1.2亿次播放", expected_is = true, expected_fmt = "120M Plays" },

  -- 日文
  { input = "1743万回視聴", expected_is = true, expected_fmt = "17M Plays" },
  { input = "44M 回視聴", expected_is = true, expected_fmt = "44M Plays" },
  { input = "3.4M 回視聴", expected_is = true, expected_fmt = "3.4M Plays" },
  { input = "960K 回視聴", expected_is = true, expected_fmt = "960K Plays" },
  { input = "160M 回視聴", expected_is = true, expected_fmt = "160M Plays" },

  -- 英文
  { input = "17M views", expected_is = true, expected_fmt = "17M Plays" },
  { input = "3.4M views", expected_is = true, expected_fmt = "3.4M Plays" },
  { input = "850K views", expected_is = true, expected_fmt = "850K Plays" },
  { input = "1.2B views", expected_is = true, expected_fmt = "1.2B Plays" },

  -- 边界与误判防御 (时长、普通词汇不能被识别为播放量)
  { input = "3:23", expected_is = false, expected_fmt = nil },
  { input = "04:15", expected_is = false, expected_fmt = nil },
  { input = "1:02:45", expected_is = false, expected_fmt = nil },
  { input = "歌曲", expected_is = false, expected_fmt = nil },
  { input = "单曲", expected_is = false, expected_fmt = nil },
  { input = "ももいろの鍵", expected_is = false, expected_fmt = nil },
  { input = "わたしのヘリテージ", expected_is = false, expected_fmt = nil },
  { input = "", expected_is = false, expected_fmt = nil },
  { input = nil, expected_is = false, expected_fmt = nil }
}

for i, tc in ipairs(test_cases) do
  local is_play = nav.is_play_count(tc.input)
  assert_eq(is_play, tc.expected_is, "is_play_count(" .. tostring(tc.input) .. ")")
  if tc.expected_is then
    local fmt = nav.format_play_count(tc.input)
    assert_eq(fmt, tc.expected_fmt, "format_play_count(" .. tostring(tc.input) .. ")")
  end
end

print(">>> [Test 1] 全部通过！")

print(">>> [Test 2] 纯字符字节流数字提取器边界测试 (extract_number)...")
local num_tests = {
  { input = "1743万", expected = 1743 },
  { input = "3.4M", expected = 3.4 },
  { input = "0.96", expected = 0.96 },
  { input = "播放次数：850K", expected = 850 },
  { input = "无数字文本", expected = nil }
}

for _, nt in ipairs(num_tests) do
  local res = nav.extract_number(nt.input)
  assert_eq(res, nt.expected, "extract_number(" .. tostring(nt.input) .. ")")
end

print(">>> [Test 2] 全部通过！\n>>> [OK] test_digit_extractor.lua 测试套件执行完毕，全用例验证成功！")
