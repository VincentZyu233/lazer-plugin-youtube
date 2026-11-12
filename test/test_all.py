import sys
from test_search import test_search
from test_stream import test_stream
from test_song import test_song

def main():
    print("==================================================")
    print(" Running Lazer YouTube Plugin Test Suite")
    print("==================================================")

    passed = 0
    failed = 0

    tests = [
        ("Search Test (iyowa)", lambda: test_search("iyowa")),
        ("Song Details (7MkUDkzsge0)", lambda: test_song("7MkUDkzsge0")),
        ("Stream & Range Probe (7MkUDkzsge0)", lambda: test_stream("7MkUDkzsge0")),
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
