import sys
from test_search import test_search
from test_stream import test_stream
from test_song import test_song
from test_lyrics import test_lyrics_timed, test_lyrics_fallback, test_lyrics_unselectable
from test_stream_nodes import test_stream_nodes

def main():
    print("==================================================")
    print(" Running Lazer YouTube Plugin Test Suite (v0.1.0)")
    print("==================================================")

    passed = 0
    failed = 0

    tests = [
        ("Search Test (iyowa)", lambda: test_search("iyowa")),
        ("Song Details (7MkUDkzsge0)", lambda: test_song("7MkUDkzsge0")),
        ("Stream & Range Probe (7MkUDkzsge0)", lambda: test_stream("7MkUDkzsge0")),
        ("Stream Bandwidth & Nodes Probe (1LBbOldnZcA)", lambda: test_stream_nodes("1LBbOldnZcA")),
        ("Timed Lyrics & Precise Cue (hpSrLjc5SMs)", lambda: test_lyrics_timed("hpSrLjc5SMs")),
        ("Fallback Lyrics Synthesis (1LBbOldnZcA)", lambda: test_lyrics_fallback("1LBbOldnZcA")),
        ("Lyrics Unselectable Check (hwpeUW1yEOI)", lambda: test_lyrics_unselectable("hwpeUW1yEOI")),
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
