import sys
import os
import urllib.parse
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from common import post_innertube, HOST_YOUTUBE, CLIENT_VISIONOS, ensure_visitor_data

def get_format(vid: str, itag: int = 250):
    ensure_visitor_data()
    url = f"{HOST_YOUTUBE}/youtubei/v1/player?prettyPrint=false"
    payload = {
        "videoId": vid,
        "playbackContext": {"contentPlaybackContext": {"html5Preference": "HTML5_PREF_WANTS", "signatureTimestamp": 20760}},
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
    matches = [f for f in fmts if f.get("itag") == itag]
    return matches[0] if matches else None

def compare_stream_urls(vid1: str, vid2: str):
    s1 = get_format(vid1)
    s2 = get_format(vid2)

    print(f"=== 对比音频流 URL 特征 ===")
    print(f"\n[曲目 1] {vid1}:")
    if s1:
        u1 = urllib.parse.urlparse(s1["url"])
        print(f"  Content-Length: {s1.get('contentLength')} bytes, Bitrate: {s1.get('bitrate')}")
        print(f"  CDN Host: {u1.hostname}")
        print(f"  Query Keys: {list(urllib.parse.parse_qs(u1.query).keys())}")
    else:
        print("  未获取到 itag 250 音频流")

    print(f"\n[曲目 2] {vid2}:")
    if s2:
        u2 = urllib.parse.urlparse(s2["url"])
        print(f"  Content-Length: {s2.get('contentLength')} bytes, Bitrate: {s2.get('bitrate')}")
        print(f"  CDN Host: {u2.hostname}")
        print(f"  Query Keys: {list(urllib.parse.parse_qs(u2.query).keys())}")
    else:
        print("  未获取到 itag 250 音频流")

if __name__ == "__main__":
    v1 = sys.argv[1] if len(sys.argv) > 1 else "1LBbOldnZcA"
    v2 = sys.argv[2] if len(sys.argv) > 2 else "hwpeUW1yEOI"
    compare_stream_urls(v1, v2)
