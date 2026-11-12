import json
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_search(query: str = "iyowa"):
    print(f"\n==========================================")
    print(f" [TEST SEARCH] Query: {query}")
    print(f"==========================================")

    url = f"{HOST_MUSIC}/youtubei/v1/search"
    payload = {
        "query": query
    }

    data = post_innertube(url, payload, CLIENT_WEB_REMIX)
    visitor_data = data.get("responseContext", {}).get("visitorData")
    print(f"VisitorData captured: {visitor_data}")

    # 解析 contents
    contents = (
        data.get("contents", {})
        .get("tabbedSearchResultsRenderer", {})
        .get("tabs", [{}])[0]
        .get("tabRenderer", {})
        .get("content", {})
        .get("sectionListRenderer", {})
        .get("contents", [])
    )

    print(f"Section count: {len(contents)}")
    total_songs = 0
    sample_song = None

    for sec in contents:
        shelf = sec.get("musicShelfRenderer") or sec.get("musicCardShelfRenderer")
        if not shelf:
            continue
        title = shelf.get("title", {}).get("runs", [{}])[0].get("text", "Unknown Section")
        items = shelf.get("contents", [])
        print(f" -> Section '{title}': {len(items)} items")

        for item in items:
            mrir = item.get("musicResponsiveListItemRenderer")
            if not mrir:
                continue
            cols = mrir.get("flexColumns", [])
            col1 = cols[0].get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", [{}])[0].get("text", "")
            play_nav = (
                mrir.get("overlay", {})
                .get("musicItemThumbnailOverlayRenderer", {})
                .get("content", {})
                .get("musicPlayButtonRenderer", {})
                .get("playNavigationEndpoint", {})
                .get("watchEndpoint", {})
            )
            vid = play_nav.get("videoId")
            if vid:
                total_songs += 1
                if not sample_song:
                    sample_song = {"title": col1, "videoId": vid}

    print(f"\nTotal parsed playable songs: {total_songs}")
    if sample_song:
        print(f"First parsed song: {sample_song['title']} (videoId: {sample_song['videoId']})")
    assert total_songs > 0, "No playable songs found in search results!"
    print(">>> SEARCH TEST PASSED <<<")

if __name__ == "__main__":
    test_search("iyowa")
    test_search("初音未来")
