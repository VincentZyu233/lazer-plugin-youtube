import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def inspect_lyrics(vid: str, name: str = ""):
    print(f"\n==========================================")
    print(f"正在透视曲目: {name or vid} ({vid}) 的歌词元数据...")
    print(f"==========================================")
    url_next = f"{HOST_MUSIC}/youtubei/v1/next"
    data = post_innertube(url_next, {"videoId": vid}, CLIENT_WEB_REMIX)

    tabs = data.get("contents", {}).get("singleColumnMusicWatchNextResultsRenderer", {}).get("tabbedRenderer", {}).get("watchNextTabbedResultsRenderer", {}).get("tabs", [])
    lyrics_tab = None
    for t in tabs:
        tr = t.get("tabRenderer", {})
        title = tr.get("title")
        b_id = tr.get("endpoint", {}).get("browseEndpoint", {}).get("browseId")
        unsel = tr.get("unselectable")
        print(f"Tab: [{title}] -> browseId: {b_id}, unselectable: {unsel}")
        if b_id and (b_id.startswith("MPLY") or title in ["歌词", "Lyrics"]):
            lyrics_tab = tr

    if not lyrics_tab or lyrics_tab.get("unselectable"):
        print("=> 结论: YouTube 官方对此歌曲标记为纯音乐 / 无歌词 (unselectable=True)")
        return

    b_id = lyrics_tab.get("endpoint", {}).get("browseEndpoint", {}).get("browseId")
    print(f"\n正在通过 browseId: {b_id} 拉取 LyricFind 官方歌词正文...")
    url_browse = f"{HOST_MUSIC}/youtubei/v1/browse"
    b_data = post_innertube(url_browse, {"browseId": b_id}, CLIENT_WEB_REMIX)

    secs = b_data.get("contents", {}).get("sectionListRenderer", {}).get("contents", [])
    for s in secs:
        shelf = s.get("musicDescriptionShelfRenderer")
        if shelf:
            runs = shelf.get("description", {}).get("runs", [])
            full_text = "".join(r.get("text", "") for r in runs)
            footer = "".join(r.get("text", "") for r in shelf.get("footer", {}).get("runs", []))
            print(f"版权信息: {footer}")
            print(f"歌词总字符数: {len(full_text)}，前 5 行预览:")
            for line in full_text.splitlines()[:5]:
                if line.strip():
                    print(f"  > {line.strip()}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        inspect_lyrics(sys.argv[1])
    else:
        inspect_lyrics("1LBbOldnZcA", "頬が乾くまで - Iyowa (官方有词)")
        inspect_lyrics("hwpeUW1yEOI", "ミュージック - MIMI (官方无词/未收录)")
