import json
import urllib.request
from common import (
    ensure_visitor_data,
    post_innertube,
    get_opener,
    HOST_YOUTUBE,
    CLIENT_VISIONOS
)

def test_stream(video_id: str = "7MkUDkzsge0"):
    print(f"\n==========================================")
    print(f" [TEST STREAM] videoId: {video_id}")
    print(f"==========================================")

    # 1. 确保已有 visitorData
    visitor_data = ensure_visitor_data()
    print(f"Using VisitorData: {visitor_data}")

    # 2. 发起 player 请求
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

    playability = data.get("playabilityStatus", {})
    status = playability.get("status")
    print(f"Playability Status: {status}")
    assert status == "OK", f"Playability not OK: {playability}"

    streaming = data.get("streamingData", {})
    formats = streaming.get("adaptiveFormats", [])
    print(f"Adaptive formats count: {len(formats)}")

    # 过滤可用的音频流
    direct_audios = []
    for f in formats:
        mime = f.get("mimeType", "")
        if "audio/" in mime and f.get("url"):
            direct_audios.append(f)

    print(f"Direct unencrypted audio formats found: {len(direct_audios)}")
    assert len(direct_audios) > 0, "No unencrypted direct audio stream found!"

    # 挑选最高码率
    best = max(direct_audios, key=lambda x: x.get("bitrate", 0))
    bitrate = best.get("bitrate", 0)
    itag = best.get("itag")
    mime = best.get("mimeType", "")
    stream_url = best.get("url")

    print(f"Best audio chosen: itag={itag}, bitrate={bitrate}, mime={mime}")
    print(f"Stream URL: {stream_url[:90]}...")

    # 3. 模拟播放器发起 HTTP Range 探测
    print("\nProbing audio stream with Range: bytes=0-1023 ...")
    opener = get_opener()
    probe_req = urllib.request.Request(
        stream_url,
        headers={
            "User-Agent": CLIENT_VISIONOS["userAgent"],
            "Origin": "https://www.youtube.com",
            "Range": "bytes=0-1023"
        }
    )

    with opener.open(probe_req, timeout=10) as resp:
        print(f"Audio probe response status: {resp.status}")
        assert resp.status in (200, 206), f"Unexpected HTTP status {resp.status}"
        chunk = resp.read()
        print(f"Downloaded chunk size: {len(chunk)} bytes")
        print(f"Magic bytes (hex): {chunk[:16].hex()}")

        # 校验 webm (1a 45 df a3) 或 mp4/m4a (ftyp)
        if "webm" in mime:
            assert chunk.startswith(b"\x1a\x45\xdf\xa3"), f"Invalid WebM EBML header: {chunk[:4].hex()}"
            print("Verified EBML (WebM Opus) magic header!")
        elif "mp4" in mime:
            assert b"ftyp" in chunk[:16], f"Invalid MP4/M4A header: {chunk[:16].hex()}"
            print("Verified MP4/M4A header!")

    # 4. 校验符合 Lazer 宿主 MusicStream 契约字段
    music_stream_contract = {
        "url": stream_url,
        "bitRate": bitrate,
        "suffix": "webm" if "webm" in mime else "m4a",
        "contentType": mime,
        "transcoded": False,
        "headers": {
            "User-Agent": CLIENT_VISIONOS["userAgent"],
            "Origin": "https://www.youtube.com"
        }
    }
    print("\nLazer MusicStream Contract verification:")
    for k, v in music_stream_contract.items():
        if k != "url":
            print(f"  - {k}: {v}")
    print(">>> STREAM TEST PASSED <<<")

if __name__ == "__main__":
    test_stream("7MkUDkzsge0") # 惑星直列
