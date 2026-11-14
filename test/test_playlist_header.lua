-- test/test_playlist_header.lua
-- 回归测试：歌单头部曲目数解析
-- 核心约束：宿主 string.match 不支持 (%d+) 捕获，必须改用纯字节扫描，
-- 否则 songCount 恒为 0。

package.path = "?.lua;ytm/?.lua;" .. package.path

local browse_parser = require("ytm.parsers.browse")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s | Expected: %s, Actual: %s", tostring(msg), tostring(expected), tostring(actual)), 2)
  end
end

local function make_data(second_subtitle)
  return {
    contents = {
      twoColumnBrowseResultsRenderer = {
        tabs = {
          {
            tabRenderer = {
              content = {
                sectionListRenderer = {
                  contents = {
                    {
                      musicResponsiveHeaderRenderer = {
                        title = { runs = { { text = "My List" } } },
                        subtitle = { runs = { { text = "VincentZyu233" } } },
                        secondSubtitle = second_subtitle
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
end

print(">>> [Test 1] 英文歌单曲目数...")
local header = browse_parser.parse_playlist_header(
  make_data({ runs = { { text = "123 songs" } } }),
  "PL1"
)
assert_eq(header.songCount, 123, "123 songs")

print(">>> [Test 2] 千分位逗号...")
header = browse_parser.parse_playlist_header(
  make_data({ runs = { { text = "1,234 songs" } } }),
  "PL1"
)
assert_eq(header.songCount, 1234, "1,234 songs")

print(">>> [Test 3] 中文单位...")
header = browse_parser.parse_playlist_header(
  make_data({ runs = { { text = "123 首歌曲" } } }),
  "PL1"
)
assert_eq(header.songCount, 123, "123 首歌曲")

print(">>> [Test 4] 小数不得保留...")
header = browse_parser.parse_playlist_header(
  make_data({ runs = { { text = "3.4M views" } } }),
  "PL1"
)
assert_eq(header.songCount, 3, "3.4M 取整数部分")

print(">>> [Test 5] 无 secondSubtitle 时为 0...")
header = browse_parser.parse_playlist_header(make_data(nil), "PL1")
assert_eq(header.songCount, 0, "缺省 0")

print(">>> [Test 6] 无数字文本时为 0...")
header = browse_parser.parse_playlist_header(
  make_data({ runs = { { text = "暂无歌曲" } } }),
  "PL1"
)
assert_eq(header.songCount, 0, "无数字 0")

print(">>> [OK] test_playlist_header.lua 测试套件执行完毕，全部断言通过！")
