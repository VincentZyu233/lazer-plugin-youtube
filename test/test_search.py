import json
import re
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_search(query: str = "iyowa"):
    print(f"\n==========================================")
    print(f" [TEST SEARCH] Query: {query}")
    print(f"==========================================")

    url = f"{HOST_MUSIC}/youtubei/v1/search"
    payload = {
        "query": query,
        "params": "EgWKAQIIAWoOEAUQCRADEAQQChAVEBA%3D"
    }

    data = post_innertube(url, payload, CLIENT_WEB_REMIX)
    visitor_data = data.get("responseContext", {}).get("visitorData")
    print(f"VisitorData captured: {visitor_data}")

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

    find_items(data)
    print(f"Found {len(items)} musicResponsiveListItemRenderer items")

    parsed_songs = []
    for it in items:
        # 提取 videoId
        vid = it.get("playlistItemData", {}).get("videoId")
        if not vid or len(vid) != 11:
            overlay = it.get("overlay", {}).get("musicItemThumbnailOverlayRenderer", {})
            c = overlay.get("content", {}).get("musicPlayButtonRenderer", {})
            vid = c.get("playNavigationEndpoint", {}).get("watchEndpoint", {}).get("videoId")

        if not vid or len(vid) != 11:
            continue

        cols = it.get("flexColumns", [])
        title = ""
        if cols:
            runs = cols[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [])
            if runs:
                title = runs[0].get("text", "")

        artists = []
        album_name = ""
        dur_ms = 0

        for col in cols[1:]:
            rend = col.get("musicResponsiveListItemFlexColumnRenderer", {})
            runs = rend.get("text", {}).get("runs", [])
            for r in runs:
                t = r.get("text", "").strip()
                ep = r.get("navigationEndpoint", {}).get("browseEndpoint", {})
                cfg = ep.get("browseEndpointContextSupportedConfigs", {}).get("browseEndpointContextMusicConfig", {})
                page_type = cfg.get("pageType")

                if page_type in ("MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL"):
                    if t and t not in ("•", "·"):
                        artists.append(t)
                elif page_type == "MUSIC_PAGE_TYPE_ALBUM":
                    album_name = t
                else:
                    m = re.match(r"^(\d+):(\d+)$", t)
                    if m:
                        mins, secs = int(m.group(1)), int(m.group(2))
                        dur_ms = (mins * 60 + secs) * 1000

        parsed_songs.append({
            "videoId": vid,
            "title": title,
            "artists": artists,
            "album": album_name,
            "durationMs": dur_ms
        })

    print(f"Total parsed songs: {len(parsed_songs)}")
    assert len(parsed_songs) > 0, "No songs parsed!"

    # 验证前 5 首
    for s in parsed_songs[:5]:
        print(f" -> [{s['durationMs']//1000//60:02d}:{s['durationMs']//1000%60:02d}] {s['title']} | 歌手: {' / '.join(s['artists'])} | 专辑: 《{s['album']}》")
        assert len(s["title"]) > 0, "Empty song title"
        assert len(s["artists"]) > 0, f"No artists for {s['title']}"
        assert s["artists"][0] not in ("•", "·"), f"Invalid artist '{s['artists'][0]}'"
        assert s["durationMs"] > 0, f"Duration is 0 for {s['title']}"

    print(">>> SEARCH TEST PASSED <<<")

if __name__ == "__main__":
    test_search("iyowa")
    test_search("初音未来")
