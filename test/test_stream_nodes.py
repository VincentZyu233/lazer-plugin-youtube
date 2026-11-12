import time
import urllib.request
from common import (
    ensure_visitor_data,
    post_innertube,
    get_opener,
    HOST_YOUTUBE,
    CLIENT_VISIONOS
)

def test_stream_nodes(video_id: str = "1LBbOldnZcA"):
    print(f"\n==========================================")
    print(f" [TEST STREAM NODES] videoId: {video_id}")
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
    fmts = data.get("streamingData", {}).get("adaptiveFormats", [])
    assert fmts, "No adaptiveFormats returned"

    opener = get_opener()
    tested = 0
    # 测试主力格式：250 (Opus ~90kbps), 249 (Opus ~50kbps), 140 (AAC 128kbps)
    for itag in [250, 249, 140]:
        matches = [f for f in fmts if f.get("itag") == itag and f.get("url")]
        if not matches:
            continue
        f = matches[0]
        stream_url = f["url"]
        bitrate_kbs = f.get("bitrate", 0) // 8000
        
        t0 = time.time()
        d_req = urllib.request.Request(
            stream_url,
            headers={
                "User-Agent": CLIENT_VISIONOS["userAgent"],
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
                "Range": "bytes=0-262143"
            }
        )
        with opener.open(d_req, timeout=10) as d_res:
            assert d_res.status in (200, 206), f"Expected HTTP 200/206, got {d_res.status}"
            chunk = d_res.read(256 * 1024)
            dt = time.time() - t0
            speed = (len(chunk) / 1024) / max(0.001, dt)
            print(f"  > itag {itag} ({f.get('mimeType', '').split(';')[0]}): {len(chunk)} bytes in {dt:.2f}s -> {speed:.1f} KB/s (need {bitrate_kbs} KB/s)")
            tested += 1

    assert tested > 0, "No target audio itags tested successfully"
    print(f"Stream nodes testing passed ({tested} formats verified)")

if __name__ == "__main__":
    test_stream_nodes("1LBbOldnZcA")
