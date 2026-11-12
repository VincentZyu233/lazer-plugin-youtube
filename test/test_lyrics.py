import re
from common import (
    post_innertube,
    HOST_MUSIC,
    CLIENT_WEB_REMIX
)

def fetch_catalog_lyrics(video_id: str):
    """
    模拟 Lua catalog.lyrics(song_id) 的完整双阶段调用：
    1. /next 接口解析歌词标签页与 browseId
    2. /browse 接口抓取 LyricFind 官方歌词正文并合成 LRC
    """
    # 第 1 步：查询 next 接口
    url_next = f"{HOST_MUSIC}/youtubei/v1/next"
    next_data = post_innertube(url_next, {"videoId": video_id}, CLIENT_WEB_REMIX)

    watch_next = next_data.get("contents", {}).get("singleColumnMusicWatchNextResultsRenderer", {})
    tabbed = watch_next.get("tabbedRenderer", {}).get("watchNextTabbedResultsRenderer", {})
    tabs = tabbed.get("tabs", [])

    lyrics_browse_id = None
    is_pure_music = False

    for t in tabs:
        rend = t.get("tabRenderer", {})
        endpoint = rend.get("endpoint", {}).get("browseEndpoint", {})
        b_id = endpoint.get("browseId", "")
        title = rend.get("title", "")
        
        is_lyrics_tab = (isinstance(b_id, str) and b_id.startswith("MPLY")) or title in ("歌词", "Lyrics")
        if is_lyrics_tab:
            if rend.get("unselectable") is True:
                is_pure_music = True
                break
            lyrics_browse_id = b_id
            break

    if is_pure_music or not lyrics_browse_id:
        return {
            "pureMusic": True,
            "lines": [],
            "lrc": None
        }

    # 第 2 步：向 browse 接口抓取歌词
    url_browse = f"{HOST_MUSIC}/youtubei/v1/browse"
    browse_data = post_innertube(url_browse, {"browseId": lyrics_browse_id}, CLIENT_WEB_REMIX)

    contents = browse_data.get("contents", {}).get("sectionListRenderer", {}).get("contents", [])
    raw_text = ""
    footer_text = ""

    for sec in contents:
        shelf = sec.get("musicDescriptionShelfRenderer")
        if shelf:
            runs = shelf.get("description", {}).get("runs", [])
            raw_text = "".join(r.get("text", "") for r in runs if r.get("text"))
            
            f_runs = shelf.get("footer", {}).get("runs", [])
            footer_text = "".join(fr.get("text", "") for fr in f_runs if fr.get("text"))
            if raw_text:
                break

    if not raw_text.strip():
        return {
            "pureMusic": True,
            "lines": [],
            "lrc": None
        }

    # 第 3 步：分行生成平滑时间戳并合成合规 LRC
    lines = []
    lrc_rows = []
    step_ms = 4000
    current_ms = 0

    for line in raw_text.splitlines():
        trimmed = line.strip()
        if trimmed:
            minutes = current_ms // 60000
            seconds = (current_ms % 60000) // 1000
            millis = current_ms % 1000
            stamp = f"[{minutes:02d}:{seconds:02d}.{millis:03d}]"

            lines.append({
                "text": trimmed,
                "startMs": current_ms
            })
            lrc_rows.append(f"{stamp}{trimmed}")
            current_ms += step_ms

    if footer_text.strip():
        minutes = current_ms // 60000
        seconds = (current_ms % 60000) // 1000
        millis = current_ms % 1000
        stamp = f"[{minutes:02d}:{seconds:02d}.{millis:03d}]"
        lines.append({
            "text": footer_text.strip(),
            "startMs": current_ms
        })
        lrc_rows.append(f"{stamp}{footer_text.strip()}")

    return {
        "pureMusic": False,
        "lines": lines,
        "lrc": "\n".join(lrc_rows)
    }

def test_lyrics(video_id: str = "1LBbOldnZcA"):
    print(f"\n==========================================")
    print(f" [TEST LYRICS] videoId: {video_id} (有词歌曲)")
    print(f"==========================================")
    res = fetch_catalog_lyrics(video_id)
    assert not res["pureMusic"], f"Expected lyrics for {video_id}, but got pureMusic"
    assert len(res["lines"]) > 5, f"Expected > 5 lines, got {len(res['lines'])}"
    assert res["lrc"] is not None, "Expected valid LRC string"

    # 验证 LRC 格式
    lrc_pattern = re.compile(r"^\[\d{2}:\d{2}\.\d{3}\].+$")
    valid_lines = [l for l in res["lrc"].splitlines() if lrc_pattern.match(l)]
    assert len(valid_lines) == len(res["lines"]), f"LRC format mismatch: {len(valid_lines)} vs {len(res['lines'])}"
    print(f"Successfully verified {len(res['lines'])} lyric lines for {video_id}")

def test_lyrics_unselectable(video_id: str = "hwpeUW1yEOI"):
    print(f"\n==========================================")
    print(f" [TEST LYRICS UNSELECTABLE] videoId: {video_id} (纯音乐/无词)")
    print(f"==========================================")
    res = fetch_catalog_lyrics(video_id)
    assert res["pureMusic"] is True, f"Expected pureMusic: True for {video_id}, got: {res}"
    assert len(res["lines"]) == 0, f"Expected 0 lines, got {len(res['lines'])}"
    print(f"Successfully verified pureMusic detection for {video_id}")

if __name__ == "__main__":
    test_lyrics("1LBbOldnZcA")
    test_lyrics_unselectable("hwpeUW1yEOI")
