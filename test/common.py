import os
import json
import urllib.request
import urllib.error

DEFAULT_PROXY = os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY") or "http://127.0.0.1:7890"

HOST_MUSIC = "https://music.youtube.com"
HOST_YOUTUBE = "https://www.youtube.com"

CLIENT_WEB_REMIX = {
    "clientName": "WEB_REMIX",
    "clientVersion": "1.20260707.12.00",
    "hl": "zh-CN",
    "gl": "US",
    "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
}

CLIENT_VISIONOS = {
    "clientName": "VISIONOS",
    "clientVersion": "1.02",
    "deviceMake": "Apple",
    "deviceModel": "RealityDevice17,1",
    "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
    "osName": "visionOS",
    "osVersion": "26.5.23O471",
    "hl": "en",
    "timeZone": "UTC",
    "utcOffsetMinutes": 0
}

_opener = None
_cached_visitor_data = None

def get_opener():
    global _opener
    if _opener is None:
        proxy_handler = urllib.request.ProxyHandler({
            "http": DEFAULT_PROXY,
            "https": DEFAULT_PROXY,
        })
        _opener = urllib.request.build_opener(proxy_handler)
    return _opener

def post_innertube(url: str, payload: dict, client_profile: dict, extra_headers: dict = None) -> dict:
    global _cached_visitor_data
    opener = get_opener()

    ctx_client = dict(client_profile)
    if _cached_visitor_data:
        ctx_client["visitorData"] = _cached_visitor_data

    payload["context"] = {
        "client": ctx_client
    }

    headers = {
        "Content-Type": "application/json",
        "User-Agent": client_profile.get("userAgent", CLIENT_WEB_REMIX["userAgent"]),
        "X-Goog-Api-Format-Version": "2",
        "Origin": HOST_MUSIC if "music.youtube" in url else HOST_YOUTUBE,
    }
    if _cached_visitor_data:
        headers["X-Goog-Visitor-Id"] = _cached_visitor_data

    if extra_headers:
        headers.update(extra_headers)

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers
    )

    try:
        with opener.open(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            visitor = data.get("responseContext", {}).get("visitorData")
            if visitor:
                _cached_visitor_data = visitor
            return data
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"HTTP {e.code}: {body}")

def ensure_visitor_data():
    global _cached_visitor_data
    if not _cached_visitor_data:
        url = f"{HOST_MUSIC}/youtubei/v1/search"
        payload = {"query": "music"}
        post_innertube(url, payload, CLIENT_WEB_REMIX)
    return _cached_visitor_data
