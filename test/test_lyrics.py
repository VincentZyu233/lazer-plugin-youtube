import re
from common import (
    post_innertube,
    HOST_MUSIC,
    HOST_YOUTUBE,
    CLIENT_WEB_REMIX,
    CLIENT_ANDROID_MUSIC,
    CLIENT_VISIONOS
)

def fetch_single_browse_lyrics(browse_id: str):
    url_browse = f"{HOST_MUSIC}/youtubei/v1/browse"
    android_data = post_innertube(url_browse, {"browseId": browse_id}, CLIENT_ANDROID_MUSIC)
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

    # 回退到 WEB_REMIX 静态歌词
    web_data = post_innertube(url_browse, {"browseId": browse_id}, CLIENT_WEB_REMIX)
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
        return None

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

def get_lyrics_browse_id(video_id: str):
    url_next = f"{HOST_MUSIC}/youtubei/v1/next"
    next_data = post_innertube(url_next, {"videoId": video_id}, CLIENT_WEB_REMIX)

    watch_next = next_data.get("contents", {}).get("singleColumnMusicWatchNextResultsRenderer", {})
    tabbed = watch_next.get("tabbedRenderer", {}).get("watchNextTabbedResultsRenderer", {})
    tabs = tabbed.get("tabs", [])

    for t in tabs:
        rend = t.get("tabRenderer", {})
        endpoint = rend.get("endpoint", {}).get("browseEndpoint", {})
        b_id = endpoint.get("browseId", "")
        title = rend.get("title", "")

        is_lyrics_tab = (isinstance(b_id, str) and b_id.startswith("MPLY")) or title in ("歌词", "Lyrics")
        if is_lyrics_tab:
            if rend.get("unselectable") is True:
                return None, True
            return b_id, False
    return None, False

def fetch_service_lyrics(video_id: str):
    """
    模拟 Lua ytm.services.lyrics.get_lyrics(song_id) 增强链路：
    1. 自身歌词查询
    2. 若无精准时间戳，自动检索官方录音室音源版 (ATV)
    3. 兜底平滑歌词
    """
    self_b_id, is_pure = get_lyrics_browse_id(video_id)
    if is_pure:
        return {"pureMusic": True, "lines": [], "lrc": None, "hasTimestamps": False}

    self_lyrics = fetch_single_browse_lyrics(self_b_id) if self_b_id else None
    if self_lyrics and self_lyrics.get("hasTimestamps"):
        return self_lyrics

    # 尝试关联官方音源
    player_res = post_innertube(f"{HOST_YOUTUBE}/youtubei/v1/player", {"videoId": video_id}, CLIENT_VISIONOS)
    vd = player_res.get("videoDetails", {})
    title = vd.get("title", "")
    author = vd.get("author", "")

    if title:
        clean_title = title.split("MV")[0].split("Official")[0].split("【")[0].strip()
        clean_author = author.replace("- Topic", "").strip()
        q = f"{clean_title} {clean_author}".strip()

        search_data = post_innertube(f"{HOST_MUSIC}/youtubei/v1/search", {
            "query": q,
            "params": "EgWKAQIIAWoOEAUQCRADEAQQChAVEBA%3D"
        }, CLIENT_WEB_REMIX)

        items = []
        def find_items(node):
            if isinstance(node, dict):
                if "musicResponsiveListItemRenderer" in node:
                    items.append(node["musicResponsiveListItemRenderer"])
                for v in node.values():
                    find_items(v)
            elif isinstance(node, list):
                for v in node:
                    find_items(v)
        find_items(search_data)

        for it in items[:3]:
            cand_vid = it.get("playlistItemData", {}).get("videoId")
            if cand_vid and cand_vid != video_id and len(cand_vid) == 11:
                cand_b_id, cand_pure = get_lyrics_browse_id(cand_vid)
                if cand_b_id and not cand_pure:
                    cand_lyrics = fetch_single_browse_lyrics(cand_b_id)
                    if cand_lyrics and cand_lyrics.get("hasTimestamps"):
                        return cand_lyrics

    if self_lyrics:
        return self_lyrics

    return {"pureMusic": True, "lines": [], "lrc": None, "hasTimestamps": False}

def test_lyrics_timed(video_id: str = "hpSrLjc5SMs"):
    print(f"\n==========================================")
    print(f" [TEST TIMED LYRICS] videoId: {video_id} (Oasis - Wonderwall 原生毫秒级时间戳)")
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

def test_lyrics_mv_auto_resolution(video_id: str = "aBZqxfnvaVA"):
    print(f"\n==========================================")
    print(f" [TEST MV AUTO RESOLUTION] videoId: {video_id} (パジャミィ MV 自动关联录音室时间轴)")
    print(f"==========================================")
    res = fetch_service_lyrics(video_id)
    assert not res["pureMusic"], f"Expected lyrics for {video_id}"
    assert res["hasTimestamps"] is True, f"Expected MV auto resolution to find timestamps for {video_id}"
    assert len(res["lines"]) >= 25, f"Expected >= 25 lines, got {len(res['lines'])}"

    lrc_pattern = re.compile(r"^\[\d{2}:\d{2}\.\d{2}\].+$")
    valid_lines = [l for l in res["lrc"].splitlines() if lrc_pattern.match(l)]
    print(f"First resolved timed line: {valid_lines[0]}")
    print(f"Second resolved timed line: {valid_lines[1]}")
    print(f"Successfully verified MV auto-resolution to {len(res['lines'])} TIMED lyric lines for {video_id}")

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
    test_lyrics_mv_auto_resolution("aBZqxfnvaVA")
    test_lyrics_fallback("1LBbOldnZcA")
    test_lyrics_unselectable("hwpeUW1yEOI")
