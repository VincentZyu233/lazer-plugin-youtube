import os
import sys
import json
from test_search import test_search
from test_stream import test_stream
from test_song import test_song
from test_lyrics import (
    test_lyrics_timed,
    test_lyrics_mv_auto_resolution,
    test_lyrics_fallback,
    test_lyrics_unselectable
)
from test_stream_nodes import test_stream_nodes
from test_home_feed import test_home_feed
from test_playlist import test_playlist
from test_charts import test_charts

def get_plugin_version() -> str:
    manifest_path = os.path.join(os.path.dirname(__file__), "..", "manifest.json")
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            return json.load(f).get("version", "unknown")
    except Exception:
        return "unknown"

def main():
    version = get_plugin_version()
    print("==================================================")
    print(f" Running Lazer YouTube Plugin Test Suite (v{version})")
    print("==================================================")

    passed = 0
    failed = 0

    tests = [
        ("Search Test (iyowa)", lambda: test_search("iyowa")),
        ("Song Details (7MkUDkzsge0)", lambda: test_song("7MkUDkzsge0")),
        ("Stream & Range Probe (7MkUDkzsge0)", lambda: test_stream("7MkUDkzsge0")),
        ("Stream Bandwidth & Nodes Probe (1LBbOldnZcA)", lambda: test_stream_nodes("1LBbOldnZcA")),
        ("Native Timed Lyrics (hpSrLjc5SMs)", lambda: test_lyrics_timed("hpSrLjc5SMs")),
        ("MV Auto-Resolution to Official Timed Lyrics (aBZqxfnvaVA)", lambda: test_lyrics_mv_auto_resolution("aBZqxfnvaVA")),
        ("Fallback Lyrics Synthesis (1LBbOldnZcA)", lambda: test_lyrics_fallback("1LBbOldnZcA")),
        ("Lyrics Unselectable Check (hwpeUW1yEOI)", lambda: test_lyrics_unselectable("hwpeUW1yEOI")),
        ("Home Feed Discovery & Daily Tracks", test_home_feed),
        ("Playlist Detail & Tracks (VLOLAK...)", lambda: test_playlist()),
        ("Charts Toplist Discovery", test_charts),
    ]

    for name, fn in tests:
        try:
            print(f"\n[RUNNING] {name} ...")
            fn()
            print(f"[PASS] {name}")
            passed += 1
        except Exception as e:
            print(f"[FAIL] {name}: {e}")
            failed += 1

    print("\n==================================================")
    print(f" Summary: {passed} passed, {failed} failed")
    print("==================================================")
    if failed > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
