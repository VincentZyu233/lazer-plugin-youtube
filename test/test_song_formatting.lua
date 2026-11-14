-- test/test_song_formatting.lua
-- 单元测试：脱敏 Mock 单曲卡片解析、播放量前缀净化与 [Unknown Plays] 消除验证

package.path = "?.lua;ytm/?.lua;" .. package.path

local search_parser = require("ytm.parsers.search")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s | Expected: %s, Actual: %s", tostring(msg), tostring(expected), tostring(actual)), 2)
  end
end

print(">>> [Test 1] 验证包含播放量的搜索卡片解析 (带 [17M Plays] 前缀)...")

local mock_search_item = {
  playlistItemData = { videoId = "abc12345678" },
  flexColumns = {
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "ももいろの鍵", navigationEndpoint = { watchEndpoint = { videoId = "abc12345678" } } }
          }
        }
      }
    },
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "歌曲" },
            { text = " • " },
            { text = "3:23" }
          }
        }
      }
    },
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "播放次数：1743万" }
          }
        }
      }
    }
  }
}

local default_artist = { id = "UC_mock_artist", name = "Iyowa", coverUrl = "" }
local res1 = search_parser.parse_song_item(mock_search_item, "iyowa", {}, default_artist)

assert_eq(res1.id, "abc12345678", "Song ID")
assert_eq(res1.title, "ももいろの鍵", "Song Title")
assert_eq(res1.artists[1].name, "Iyowa", "Artist Name")
assert_eq(res1.albumName, "[17M Plays] ももいろの鍵", "AlbumName with play count")
print(">>> [Test 1] 通过！albumName: " .. tostring(res1.albumName))

print(">>> [Test 2] 验证无播放量卡片解析 (绝不允许出现 [Unknown Plays] 伪前缀)...")

local mock_playlist_item = {
  playlistItemData = { videoId = "xyz12345678" },
  flexColumns = {
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "1000年生きてる", navigationEndpoint = { watchEndpoint = { videoId = "xyz12345678" } } }
          }
        }
      }
    },
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "iyowa", navigationEndpoint = { browseEndpoint = { browseId = "UC_mock_iyowa", browseEndpointContextSupportedConfigs = { browseEndpointContextMusicConfig = { pageType = "MUSIC_PAGE_TYPE_ARTIST" } } } } },
            { text = " • " },
            {
              text = "わたしのヘリテージ",
              navigationEndpoint = {
                browseEndpoint = {
                  browseId = "MPREb_mock_heritage",
                  browseEndpointContextSupportedConfigs = {
                    browseEndpointContextMusicConfig = {
                      pageType = "MUSIC_PAGE_TYPE_ALBUM"
                    }
                  }
                }
              }
            },
            { text = " • " },
            { text = "3:21" }
          }
        }
      }
    }
  }
}

local res2 = search_parser.parse_song_item(mock_playlist_item, "iyowa", {}, default_artist)

assert_eq(res2.id, "xyz12345678", "Song ID")
assert_eq(res2.title, "1000年生きてる", "Song Title")
-- 核心断言：绝对不能含有 "[Unknown Plays]" 字符
if string.find(res2.albumName, "Unknown Plays", 1, true) then
  error("FAILED: 严重缺陷：albumName 依然残留 [Unknown Plays] 字符串: " .. res2.albumName)
end
assert_eq(res2.albumName, "わたしのヘリテージ", "Clean album name")
print(">>> [Test 2] 通过！纯净专辑名: " .. tostring(res2.albumName))

print(">>> [OK] test_song_formatting.lua 测试套件执行完毕，全部断言通过！")
