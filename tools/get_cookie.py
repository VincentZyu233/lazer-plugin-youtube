# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "websockets>=12.0",
# ]
# ///
"""
Lazer YouTube Music Cookie 自动抓取工具 (Python 版)

用法:
  uv run tools/get_cookie.py
  或: python tools/get_cookie.py (需事先 pip install websockets)

选项:
  -p, --browser-path <path>   指定浏览器可执行文件路径 (Chrome/Edge/Brave/Chromium)
  --port <port>               指定 CDP 远程调试端口 (默认自动分配空闲端口)
  --url <url>                 指定打开的登录页面 (默认: https://music.youtube.com)
  --timeout <seconds>         登录等待超时时间 (默认: 300 秒)
"""

import sys
import os
import time
import json
import socket
import tempfile
import shutil
import argparse
import subprocess
import asyncio
from typing import Optional, List
import urllib.request

try:
    import websockets
except ImportError:
    websockets = None

def get_candidate_browser_paths() -> List[str]:
    platform = sys.platform
    candidates = []

    if platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        prog_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        prog_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")

        candidates.extend([
            # Microsoft Edge
            os.path.join(prog_files_x86, r"Microsoft\Edge\Application\msedge.exe"),
            os.path.join(prog_files, r"Microsoft\Edge\Application\msedge.exe"),
            os.path.join(local_app_data, r"Microsoft\Edge\Application\msedge.exe"),
            # Google Chrome
            os.path.join(prog_files, r"Google\Chrome\Application\chrome.exe"),
            os.path.join(prog_files_x86, r"Google\Chrome\Application\chrome.exe"),
            os.path.join(local_app_data, r"Google\Chrome\Application\chrome.exe"),
            # Brave
            os.path.join(prog_files, r"BraveSoftware\Brave-Browser\Application\brave.exe"),
            os.path.join(prog_files_x86, r"BraveSoftware\Brave-Browser\Application\brave.exe"),
            os.path.join(local_app_data, r"BraveSoftware\Brave-Browser\Application\brave.exe"),
            # Chromium
            os.path.join(prog_files, r"Chromium\Application\chrome.exe"),
            os.path.join(local_app_data, r"Chromium\Application\chrome.exe"),
        ])
    elif platform == "darwin":
        candidates.extend([
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi",
        ])
    elif platform.startswith("linux"):
        candidates.extend([
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/microsoft-edge",
            "/usr/bin/microsoft-edge-stable",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
            "/snap/bin/chromium",
            "/usr/bin/brave-browser",
            "/snap/bin/brave",
        ])

    return candidates

def resolve_browser(custom_path: Optional[str] = None) -> str:
    if custom_path:
        if os.path.exists(custom_path):
            return custom_path
        raise FileNotFoundError(f"指定的浏览器路径不存在: {custom_path}")

    candidates = get_candidate_browser_paths()
    for p in candidates:
        if p and os.path.exists(p):
            return p

    # 尝试从系统 PATH 查找
    for binary_name in ["chrome", "google-chrome", "msedge", "chromium", "brave"]:
        path = shutil.which(binary_name)
        if path:
            return path

    raise FileNotFoundError(
        "未在常用路径中找到已安装的 Chrome / Edge / Brave 浏览器。\n"
        "请使用 -p 或 --browser-path 参数手动指定浏览器可执行文件路径。\n"
        '示例: uv run tools/get_cookie.py -p "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"'
    )

def find_free_port(preferred: int = 9222) -> int:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", preferred))
            return preferred
    except OSError:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            return s.getsockname()[1]

def copy_to_clipboard(text: str) -> bool:
    platform = sys.platform
    try:
        if platform == "win32":
            subprocess.run(
                ["powershell", "-NoProfile", "-Command", "$input | Set-Clipboard"],
                input=text.encode("utf-8"),
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        elif platform == "darwin":
            subprocess.run(
                ["pbcopy"],
                input=text.encode("utf-8"),
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        elif platform.startswith("linux"):
            if shutil.which("xclip"):
                subprocess.run(
                    ["xclip", "-selection", "clipboard"],
                    input=text.encode("utf-8"),
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return True
            elif shutil.which("xsel"):
                subprocess.run(
                    ["xsel", "-b"],
                    input=text.encode("utf-8"),
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return True
    except Exception:
        pass
    return False

async def monitor_cdp(ws_url: str, timeout: int) -> Optional[str]:
    if websockets is None:
        raise RuntimeError("缺少 websockets 依赖，请通过 'uv run tools/get_cookie.py' 运行。")

    req_id = 1
    start_time = time.time()

    async with websockets.connect(ws_url) as ws:
        # 启用 Network 域
        await ws.send(json.dumps({"id": req_id, "method": "Network.enable"}))
        req_id += 1

        while time.time() - start_time < timeout:
            sys.stdout.write("⏳ 等待登录授权中… (可在弹出的浏览器中输入账号密码或扫码)\r")
            sys.stdout.flush()

            # 请求 Cookies
            await ws.send(json.dumps({
                "id": req_id,
                "method": "Network.getCookies",
                "params": {
                    "urls": [
                        "https://music.youtube.com",
                        "https://youtube.com",
                        "https://accounts.google.com",
                        "https://google.com"
                    ]
                }
            }))
            check_req_id = req_id
            req_id += 1

            # 等待回包
            try:
                res_raw = await asyncio.wait_for(ws.recv(), timeout=2.0)
                msg = json.loads(res_raw)
                if msg.get("id") == check_req_id and "result" in msg:
                    cookies = msg["result"].get("cookies", [])
                    cookie_map = {c["name"]: c["value"] for c in cookies}

                    has_login_info = "LOGIN_INFO" in cookie_map
                    has_sapisid = any(k in cookie_map for k in ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"])
                    has_sid = any(k in cookie_map for k in ["SID", "__Secure-3PSID", "__Secure-1PSID"])

                    if has_login_info and (has_sapisid or has_sid):
                        pairs = [f"{k}={v}" for k, v in cookie_map.items()]
                        return "; ".join(pairs)
            except asyncio.TimeoutError:
                pass

            await asyncio.sleep(1.5)

    return None

def main():
    parser = argparse.ArgumentParser(description="Lazer YouTube Music Cookie 自动抓取工具")
    parser.add_argument("-p", "--browser-path", help="指定浏览器可执行文件路径 (Chrome/Edge/Brave/Chromium)")
    parser.add_argument("--port", type=int, default=0, help="指定 CDP 调试端口 (默认自动分配空闲端口)")
    parser.add_argument("--url", default="https://music.youtube.com", help="指定打开的登录页面")
    parser.add_argument("--timeout", type=int, default=300, help="登录等待超时时间 (默认 300 秒)")
    args = parser.parse_args()

    print("================================================================")
    print("       Lazer YouTube Music 登录与 Cookie 自动抓取工具           ")
    print("================================================================\n")

    try:
        browser_path = resolve_browser(args.browser_path)
    except Exception as e:
        print(f"❌ {e}")
        sys.exit(1)

    print(f"[1/4] 找到可用浏览器: {browser_path}")

    port = args.port or find_free_port(9222)
    print(f"[2/4] 分配调试端口: 127.0.0.1:{port}")

    temp_dir = tempfile.mkdtemp(prefix="lazer_yt_profile_")

    cmd = [
        browser_path,
        f"--remote-debugging-port={port}",
        f"--user-data-dir={temp_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-blink-features=AutomationControlled",
        args.url
    ]

    print("[3/4] 正在拉起独立的浏览器窗口，请在弹出的网页中登录 Google 账号…")
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def cleanup():
        try:
            proc.terminate()
        except Exception:
            pass
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass

    # 等待 CDP 端口就绪
    ws_url = None
    start_wait = time.time()
    while time.time() - start_wait < 15:
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/json")
            with urllib.request.urlopen(req, timeout=1) as response:
                targets = json.loads(response.read().decode())
                if isinstance(targets, list) and len(targets) > 0:
                    page = next((t for t in targets if t.get("type") == "page"), targets[0])
                    if page.get("webSocketDebuggerUrl"):
                        ws_url = page["webSocketDebuggerUrl"]
                        break
        except Exception:
            pass
        time.sleep(0.6)

    if not ws_url:
        cleanup()
        print("❌ 连接浏览器调试端口超时，请重试或更换浏览器。")
        sys.exit(1)

    print("[4/4] 正在监听登录状态，请在浏览器中完成登录…\n")

    cookie_result = None
    try:
        cookie_result = asyncio.run(monitor_cdp(ws_url, args.timeout))
    except KeyboardInterrupt:
        print("\n\n检测到用户中断，正在退出并清理临时会话…")
    except Exception as e:
        print(f"\n❌ 发生异常: {e}")
    finally:
        cleanup()

    if not cookie_result:
        print("\n❌ 登录超时或取消，未检测到完整的账号 Cookie。")
        sys.exit(1)

    copied = copy_to_clipboard(cookie_result)

    print("\n")
    print("================================================================================")
    print("🎉 恭喜！YouTube Music 登录凭据抓取成功！")
    print("================================================================================\n")
    print("【Cookie 字符串】：")
    print("--------------------------------------------------------------------------------")
    print(cookie_result)
    print("--------------------------------------------------------------------------------\n")
    if copied:
        print("✅ 提示：上方 Cookie 字符串已自动复制到您的系统剪贴板！")
    else:
        print("💡 提示：请完整选中并复制上方虚线框内的 Cookie 字符串。")
    print("👉 下一步：打开 Lazer 客户端 -> 点击「登录」-> 选择 YouTube Music -> 粘贴并点击登录即可！\n")
    print("================================================================================\n")

if __name__ == "__main__":
    main()
