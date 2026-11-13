import json
from common import post_innertube, HOST_MUSIC, CLIENT_WEB_REMIX

def test_playlist(playlist_id: str = "VLOLAK5uy_nMa6r07BbcC_Q8PrrS1CVHH2aGJRIkWu0"):
    print("==========================================")
    print(f" [TEST PLAYLIST] browseId: {playlist_id}")
    print("==========================================")

    res = post_innertube(f"{HOST_MUSIC}/youtubei/v1/browse", {"browseId": playlist_id}, CLIENT_WEB_REMIX)
    assert res and "contents" in res, "Failed to browse playlist"

    two_col = res.get("contents", {}).get("twoColumnBrowseResultsRenderer", {})
    hdr = two_col.get("tabs", [{}])[0].get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [{}])[0].get("musicResponsiveHeaderRenderer", {})
    title = "".join(x.get("text", "") for x in hdr.get("title", {}).get("runs", []))
    print(f"Playlist Title: {title}")
    assert len(title) > 0, "Empty playlist title"

    sec_contents = two_col.get("secondaryContents", {}).get("sectionListRenderer", {}).get("contents", [])
    assert len(sec_contents) > 0, "No tracks section"
    shelf = sec_contents[0].get("musicPlaylistShelfRenderer") or sec_contents[0].get("musicShelfRenderer")
    items = shelf.get("contents", []) if shelf else []
    print(f"Playlist track items count: {len(items)}")
    assert len(items) > 0, "No tracks in playlist"

    first_item = items[0].get("musicResponsiveListItemRenderer", {})
    vid = first_item.get("playlistItemData", {}).get("videoId")
    print(f"First track videoId: {vid}")
    assert vid and len(vid) == 11, f"Invalid videoId: {vid}"

    print(">>> PLAYLIST TEST PASSED <<<")
    return True

if __name__ == "__main__":
    test_playlist()
