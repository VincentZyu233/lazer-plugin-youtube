import glob
import json
import os

def clean_lazer_cache():
    """
    深度扫描并清理 Lazer 的两级假空歌词缓存：
    1. Roaming: cached_lyrics/*.json
    2. Local: lazer_cache_v1/data/*.json (7天有效期的底层缓存)
    """
    roaming_lyrics = os.path.expandvars(r"%APPDATA%\dev.naominet\lazer_nextgen\cached_lyrics")
    local_data = os.path.expandvars(r"%LOCALAPPDATA%\dev.naominet\lazer_nextgen\lazer_cache_v1\data")

    print(f"=== 扫描 Roaming: {roaming_lyrics} ===")
    roaming_files = glob.glob(os.path.join(roaming_lyrics, "*.json"))
    cleaned_roaming = 0
    for f in roaming_files:
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
            if d.get("pureMusic") is True and not d.get("lrc"):
                os.remove(f)
                cleaned_roaming += 1
        except Exception as e:
            print(f"Error {f}: {e}")
    print(f"Roaming 清理了 {cleaned_roaming} 个 pureMusic 假空缓存文件（共 {len(roaming_files)} 个）")

    print(f"\n=== 扫描 Local: {local_data} ===")
    local_files = glob.glob(os.path.join(local_data, "*.json"))
    cleaned_local = 0
    for f in local_files:
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
            data_payload = d.get("data")
            if isinstance(data_payload, dict):
                if data_payload.get("pureMusic") is True and not data_payload.get("lrc"):
                    os.remove(f)
                    cleaned_local += 1
        except Exception as e:
            print(f"Error {f}: {e}")
    print(f"Local 清理了 {cleaned_local} 个 pureMusic 7天有效期假空缓存文件（共 {len(local_files)} 个）")

if __name__ == "__main__":
    clean_lazer_cache()
