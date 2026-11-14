-- ====================================================================
-- Regression Test: Continuation Items Unwrap and Track Parsing
-- 对齐 ytm/parsers/browse.lua: parse_continuation_songs
-- 验证对包裹节点 (musicResponsiveListItemRenderer) 与裸节点的双模兼容
-- 纯脱敏 Mock 数据，无需网络和宿主依赖
-- ====================================================================

local nav = require("ytm.core.navigation")
local browse_parser = require("ytm.parsers.browse")

local mock_continuation_data = {
  continuationContents = {
    musicPlaylistShelfContinuation = {
      continuations = {
        {
          nextContinuationData = {
            continuation = "mock_continuation_token_page_3"
          }
        }
      },
      contents = {
        -- 模式 1: 带有 musicResponsiveListItemRenderer 外层包裹
        {
          musicResponsiveListItemRenderer = {
            playlistItemData = {
              videoId = "abc12345678"
            },
            flexColumns = {
              {
                musicResponsiveListItemFlexColumnRenderer = {
                  text = {
                    runs = {
                      { text = "Unwrapped Song 1" }
                    }
                  }
                }
              },
              {
                musicResponsiveListItemFlexColumnRenderer = {
                  text = {
                    runs = {
                      { text = "Mock Artist" },
                      { text = " • " },
                      { text = "Mock Album" },
                      { text = " • " },
                      { text = "3:30" }
                    }
                  }
                }
              }
            }
          }
        },
        -- 模式 2: 裸节点形式 (未包裹)
        {
          playlistItemData = {
            videoId = "xyz87654321"
          },
          flexColumns = {
            {
              musicResponsiveListItemFlexColumnRenderer = {
                text = {
                  runs = {
                    { text = "Unwrapped Song 2" }
                  }
                }
              }
            },
            {
              musicResponsiveListItemFlexColumnRenderer = {
                text = {
                  runs = {
                    { text = "Another Artist" },
                    { text = " • " },
                    { text = "Another Album" },
                    { text = " • " },
                    { text = "4:15" }
                  }
                }
              }
            }
          }
        },
        -- 重复节点 (用于验证去重机制)
        {
          musicResponsiveListItemRenderer = {
            playlistItemData = {
              videoId = "abc12345678"
            },
            flexColumns = {}
          }
        },
        -- Continuation 翻页标记节点 (appendContinuationItemsAction)
        {
          continuationItemRenderer = {
            continuationEndpoint = {
              continuationCommand = {
                token = "mock_continuation_token_page_3"
              }
            }
          }
        }
      }
    }
  }
}

local seen = {}
local songs, next_token = browse_parser.parse_continuation_songs(mock_continuation_data, seen)

assert(#songs == 2, string.format("Expected 2 deduplicated songs, got %d", #songs))
assert(songs[1].id == "abc12345678", "First song ID mismatch")
assert(songs[1].title == "Unwrapped Song 1", "First song title mismatch")
assert(songs[1].durationMs == 210000, string.format("First song durationMs mismatch (expected 210000, got %s)", tostring(songs[1].durationMs)))

assert(songs[2].id == "xyz87654321", "Second song ID mismatch")
assert(songs[2].title == "Unwrapped Song 2", "Second song title mismatch")
assert(songs[2].durationMs == 255000, string.format("Second song durationMs mismatch (expected 255000, got %s)", tostring(songs[2].durationMs)))

assert(next_token == "mock_continuation_token_page_3", "Next continuation token mismatch")

print("==================================================")
print(" All continuation unwrap tests passed successfully!")
print("==================================================")
