-- test/test_search_episode_filter.lua
-- 单元测试：播客分集/非音乐条目过滤与歌曲识别验证

package.path = "?.lua;ytm/?.lua;" .. package.path

local search_parser = require("ytm.parsers.search")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s | Expected: %s, Actual: %s", tostring(msg), tostring(expected), tostring(actual)), 2)
  end
end

print(">>> [Test 1] 验证播客分集 (分集 / 播客 / Episode) 必须被过滤为 nil...")

local mock_episode_item = {
  playlistItemData = { videoId = "ep123456789" },
  flexColumns = {
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "#7 完璧なVtuberが誕生！" }
          }
        }
      }
    },
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "分集" },
            { text = " • " },
            { text = "28:15" }
          }
        }
      }
    }
  }
}

local res_ep = search_parser.parse_song_item(mock_episode_item, "iyowa", {})
assert_eq(res_ep, nil, "Episode item must be parsed as nil")
print(">>> [Test 1] 通过！播客分集成功被过滤！")

print(">>> [Test 2] 验证通过 pageType (MUSIC_PAGE_TYPE_EPISODE) 标记的条目必须被过滤...")

local mock_episode_pt = {
  playlistItemData = { videoId = "ep987654321" },
  flexColumns = {
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "#18 浦島太郎とは違って歳はとりません♪今年も12歳♪" }
          }
        }
      }
    },
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            {
              text = "播客单集",
              navigationEndpoint = {
                browseEndpoint = {
                  browseEndpointContextSupportedConfigs = {
                    browseEndpointContextMusicConfig = {
                      pageType = "MUSIC_PAGE_TYPE_EPISODE"
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

local res_pt = search_parser.parse_song_item(mock_episode_pt, "iyowa", {})
assert_eq(res_pt, nil, "MUSIC_PAGE_TYPE_EPISODE must be parsed as nil")
print(">>> [Test 2] 通过！MUSIC_PAGE_TYPE_EPISODE 成功被过滤！")

print(">>> [Test 3] 验证正常歌曲正常保留...")

local mock_song_item = {
  playlistItemData = { videoId = "JMAJS_s99Ho" },
  flexColumns = {
    {
      musicResponsiveListItemFlexColumnRenderer = {
        text = {
          runs = {
            { text = "きゅうくらりん" }
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
            {
              text = "Iyowa",
              navigationEndpoint = {
                browseEndpoint = {
                  browseId = "UCxxxxxx",
                  browseEndpointContextSupportedConfigs = {
                    browseEndpointContextMusicConfig = {
                      pageType = "MUSIC_PAGE_TYPE_ARTIST"
                    }
                  }
                }
              }
            },
            { text = " • " },
            { text = "3:38" }
          }
        }
      }
    }
  }
}

local res_song = search_parser.parse_song_item(mock_song_item, "iyowa", {})
assert_eq(res_song ~= nil, true, "Valid song must not be nil")
assert_eq(res_song.id, "JMAJS_s99Ho", "Song ID matches")
assert_eq(res_song.title, "きゅうくらりん", "Song Title matches")
print(">>> [Test 3] 通过！正常歌曲正常解析保留！")

print(">>> [OK] test_search_episode_filter.lua 验证全部通过！")
