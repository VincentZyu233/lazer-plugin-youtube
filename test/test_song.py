import json
from common import (
    ensure_visitor_data,
    post_innertube,
    HOST_YOUTUBE,
    CLIENT_VISIONOS
)

def test_song(video_id: str = "7MkUDkzsge0"):
    print(f"\n==========================================")
    print(f" [TEST SONG DETAILS] videoId: {video_id}")
    print(f"==========================================")

    visitor_data = ensure_visitor_data()
    url = f"{HOST_YOUTUBE}/youtubei/v1/player?prettyPrint=false"
    payload = {
        "videoId": video_id,
        "playbackContext": {
            "contentPlaybackContext": {
                "html5Preference": "HTML5_PREF_WANTS",
                "signatureTimestamp": 20760
            }
        },
        "contentCheckOk": True,
        "racyCheckOk": True
    }

    extra_headers = {
        "X-YouTube-Client-Name": "101",
        "X-YouTube-Client-Version": "1.02",
        "Origin": "https://www.youtube.com"
    }

    data = post_innertube(url, payload, CLIENT_VISIONOS, extra_headers)
    video_details = data.get("videoDetails", {})
    title = video_details.get("title")
    author = video_details.get("author")
    length_seconds = video_details.get("lengthSeconds")
    thumbnails = video_details.get("thumbnail", {}).get("thumbnails", [])

    print(f"Title: {title}")
    print(f"Author: {author}")
    print(f"LengthSeconds: {length_seconds}s")
    print(f"Thumbnail count: {len(thumbnails)}")
    if thumbnails:
        print(f"Cover URL: {thumbnails[-1].get('url')}")

    assert title, "Missing song title!"
    assert author, "Missing song author!"
    assert int(length_seconds) > 0, "Invalid song duration!"
    print(">>> SONG DETAILS TEST PASSED <<<")

if __name__ == "__main__":
    test_song("7MkUDkzsge0")
