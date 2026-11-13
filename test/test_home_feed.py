import json
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_home_feed():
    print("==========================================")
    print(" [TEST HOME FEED] FEmusic_home & Sections")
    print("==========================================")

    res = post_innertube(f"{HOST_MUSIC}/youtubei/v1/browse", {"browseId": "FEmusic_home"}, CLIENT_WEB_REMIX)
    assert res and "contents" in res, "Failed to fetch FEmusic_home"

    tabs = res.get("contents", {}).get("singleColumnBrowseResultsRenderer", {}).get("tabs", [])
    assert len(tabs) > 0, "No tabs in FEmusic_home"

    sec_list = tabs[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [])
    assert len(sec_list) > 0, "No sections in FEmusic_home"

    playlists = []
    for sec in sec_list:
        carousel = sec.get("musicCarouselShelfRenderer", {})
        for it in carousel.get("contents", []):
            r = it.get("musicTwoRowItemRenderer")
            if r:
                t = "".join(x.get("text", "") for x in r.get("title", {}).get("runs", []))
                endpoint = r.get("navigationEndpoint", {}).get("browseEndpoint", {})
                b_id = endpoint.get("browseId")
                if b_id and t:
                    playlists.append({"id": b_id, "name": t})

    print(f"Total playlists discovered from home: {len(playlists)}")
    assert len(playlists) >= 5, f"Expected at least 5 playlists, got {len(playlists)}"
    for pl in playlists[:3]:
        print(f"  -> Playlist: {pl['name']} ({pl['id']})")

    # Verify fetching tracks of the first playlist to ensure quick/daily population
    first_pid = playlists[0]["id"]
    pl_res = post_innertube(f"{HOST_MUSIC}/youtubei/v1/browse", {"browseId": first_pid}, CLIENT_WEB_REMIX)
    two_col = pl_res.get("contents", {}).get("twoColumnBrowseResultsRenderer", {})
    sec_contents = two_col.get("secondaryContents", {}).get("sectionListRenderer", {}).get("contents", [])
    assert len(sec_contents) > 0, "No secondaryContents in playlist"

    shelf = sec_contents[0].get("musicPlaylistShelfRenderer") or sec_contents[0].get("musicShelfRenderer")
    items = shelf.get("contents", []) if shelf else []
    print(f"First playlist tracks count: {len(items)}")
    assert len(items) > 0, "First playlist has no tracks"

    print(">>> HOME FEED TEST PASSED <<<")
    return True

if __name__ == "__main__":
    test_home_feed()
