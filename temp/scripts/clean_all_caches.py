import glob
import json
import os
import hashlib

def scan_and_clean():
    roaming_lyrics = r"C:\Users\VincentZyu\AppData\Roaming\dev.naominet\lazer_nextgen\cached_lyrics"
    local_data = r"C:\Users\VincentZyu\AppData\Local\dev.naominet\lazer_nextgen\lazer_cache_v1\data"

    print("=== 扫描 Roaming cached_lyrics ===")
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

    print("\n=== 扫描 Local lazer_cache_v1\\data ===")
    local_files = glob.glob(os.path.join(local_data, "*.json"))
    cleaned_local = 0
    for f in local_files:
        try:
            with open(f, "r", encoding="utf-8") as fp:
                d = json.load(fp)
            data_payload = d.get("data")
            if isinstance(data_payload, dict):
                # 检查是否为歌词且 pureMusic: true 且无歌词
                if data_payload.get("pureMusic") is True and not data_payload.get("lrc"):
                    os.remove(f)
                    cleaned_local += 1
        except Exception as e:
            print(f"Error {f}: {e}")
    print(f"Local 清理了 {cleaned_local} 个 pureMusic 7天有效期假空缓存文件（共 {len(local_files)} 个）")

if __name__ == "__main__":
    scan_and_clean()
