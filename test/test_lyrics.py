import re
from common import (
    post_innertube,
    HOST_MUSIC,
    CLIENT_WEB_REMIX,
    CLIENT_ANDROID_MUSIC
)

def fetch_service_lyrics(video_id: str):
    """
    模拟 Lua ytm.services.lyrics.get_lyrics(song_id) 的完整三阶段调用：
    1. /next 接口探查歌词 Tab 与 browseId
    2. 优先 /browse 接口使用 ANDROID_MUSIC 获取毫秒级时间戳 (timedLyricsData)
    3. 若 Android 接口无有效时间戳，回退至 WEB_REMIX 抓取 LyricFind 官方全本静态歌词
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
            "lrc": None,
            "hasTimestamps": False
        }

    # 第 2 步：优先尝试 ANDROID_MUSIC
    url_browse = f"{HOST_MUSIC}/youtubei/v1/browse"
    android_data = post_innertube(url_browse, {"browseId": lyrics_browse_id}, CLIENT_ANDROID_MUSIC)

    elem = android_data.get("contents", {}).get("elementRenderer", {})
    timed_model = elem.get("newElement", {}).get("type", {}).get("componentType", {}).get("model", {}).get("timedLyricsModel", {})
    timed_data = timed_model.get("lyricsData", {}).get("timedLyricsData", [])

    if timed_data:
        lines = []
        lrc_rows = []
        has_precise_cue = False
        current_stepped_ms = 0
        step_ms = 4000

        for item in timed_data:
            line_text = (item.get("lyricLine") or "").strip()
            cue = item.get("cueRange")
            start_ms = None
            if cue and "startTimeMilliseconds" in cue:
                start_ms = int(cue["startTimeMilliseconds"])
                has_precise_cue = True

            if start_ms is None:
                start_ms = current_stepped_ms
                current_stepped_ms += step_ms
            else:
                current_stepped_ms = start_ms + step_ms

            if line_text:
                minutes = start_ms // 60000
                seconds = (start_ms % 60000) // 1000
                centis = (start_ms % 1000) // 10
                stamp = f"[{minutes:02d}:{seconds:02d}.{centis:02d}]"

                lines.append({
                    "text": line_text,
                    "startMs": start_ms
                })
                lrc_rows.append(f"{stamp}{line_text}")

        if lines:
            return {
                "pureMusic": False,
                "lines": lines,
                "lrc": "\n".join(lrc_rows),
                "hasTimestamps": has_precise_cue
            }

    # 第 3 步：回退到 WEB_REMIX 静态歌词
    web_data = post_innertube(url_browse, {"browseId": lyrics_browse_id}, CLIENT_WEB_REMIX)
    contents = web_data.get("contents", {}).get("sectionListRenderer", {}).get("contents", [])
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
            "lrc": None,
            "hasTimestamps": False
        }

    lines = []
    lrc_rows = []
    step_ms = 4000
    current_ms = 0

    for line in raw_text.splitlines():
        trimmed = line.strip()
        if trimmed:
            minutes = current_ms // 60000
            seconds = (current_ms % 60000) // 1000
            centis = (current_ms % 1000) // 10
            stamp = f"[{minutes:02d}:{seconds:02d}.{centis:02d}]"

            lines.append({
                "text": trimmed,
                "startMs": current_ms
            })
            lrc_rows.append(f"{stamp}{trimmed}")
            current_ms += step_ms

    if footer_text.strip():
        minutes = current_ms // 60000
        seconds = (current_ms % 60000) // 1000
        centis = (current_ms % 1000) // 10
        stamp = f"[{minutes:02d}:{seconds:02d}.{centis:02d}]"
        lines.append({
            "text": footer_text.strip(),
            "startMs": current_ms
        })
        lrc_rows.append(f"{stamp}{footer_text.strip()}")

    return {
        "pureMusic": False,
        "lines": lines,
        "lrc": "\n".join(lrc_rows),
        "hasTimestamps": False
    }

def test_lyrics_timed(video_id: str = "hpSrLjc5SMs"):
    print(f"\n==========================================")
    print(f" [TEST TIMED LYRICS] videoId: {video_id} (Oasis - Wonderwall 毫秒级时间戳)")
    print(f"==========================================")
    res = fetch_service_lyrics(video_id)
    assert not res["pureMusic"], f"Expected lyrics for {video_id}, but got pureMusic"
    assert res["hasTimestamps"] is True, f"Expected hasTimestamps: True for {video_id}"
    assert len(res["lines"]) >= 20, f"Expected >= 20 lines, got {len(res['lines'])}"

    lrc_pattern = re.compile(r"^\[\d{2}:\d{2}\.\d{2}\].+$")
    valid_lines = [l for l in res["lrc"].splitlines() if lrc_pattern.match(l)]
    assert len(valid_lines) == len(res["lines"]), f"LRC format mismatch: {len(valid_lines)} vs {len(res['lines'])}"
    print(f"Sample LRC line 1: {valid_lines[0]}")
    print(f"Sample LRC line 2: {valid_lines[1]}")
    print(f"Successfully verified {len(res['lines'])} TIMED lyric lines for {video_id}")

def test_lyrics_fallback(video_id: str = "1LBbOldnZcA"):
    print(f"\n==========================================")
    print(f" [TEST FALLBACK LYRICS] videoId: {video_id} (回退歌词)")
    print(f"==========================================")
    res = fetch_service_lyrics(video_id)
    assert not res["pureMusic"], f"Expected lyrics for {video_id}, but got pureMusic"
    assert len(res["lines"]) > 5, f"Expected > 5 lines, got {len(res['lines'])}"
    assert res["lrc"] is not None, "Expected valid LRC string"

    lrc_pattern = re.compile(r"^\[\d{2}:\d{2}\.\d{2}\].+$")
    valid_lines = [l for l in res["lrc"].splitlines() if lrc_pattern.match(l)]
    assert len(valid_lines) == len(res["lines"]), f"LRC format mismatch: {len(valid_lines)} vs {len(res['lines'])}"
    print(f"Successfully verified {len(res['lines'])} fallback lyric lines for {video_id}")

def test_lyrics_unselectable(video_id: str = "hwpeUW1yEOI"):
    print(f"\n==========================================")
    print(f" [TEST LYRICS UNSELECTABLE] videoId: {video_id} (纯音乐/无词)")
    print(f"==========================================")
    res = fetch_service_lyrics(video_id)
    assert res["pureMusic"] is True, f"Expected pureMusic: True for {video_id}, got: {res}"
    assert len(res["lines"]) == 0, f"Expected 0 lines, got {len(res['lines'])}"
    print(f"Successfully verified pureMusic detection for {video_id}")

if __name__ == "__main__":
    test_lyrics_timed("hpSrLjc5SMs")
    test_lyrics_fallback("1LBbOldnZcA")
    test_lyrics_unselectable("hwpeUW1yEOI")
