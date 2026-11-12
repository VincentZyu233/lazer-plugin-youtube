# Lazer YouTube Music Cookie 抓取工具

本目录提供了全自动的 Cookie 抓取脚本，帮助您在无需手动打开浏览器 F12 开发者工具的情况下，一键完成 Google 账号登录并提取 Cookie。

---

## 🌟 特性

- **全平台支持**：内置 Windows、macOS、Linux 下 10+ 常见 Chrome / Edge / Brave / Chromium 默认安装路径；
- **智能探测与自定义**：支持自动探测已安装浏览器，也支持通过 `-p` / `--browser-path` 手动传入浏览器路径；
- **真实浏览器交互**：拉起系统真实的浏览器窗口，自动去除自动化特征标记（`--disable-blink-features=AutomationControlled`），避免触发 Google「此浏览器或应用可能不安全」的风控拦截；
- **全自动捕获与复制**：用户在浏览器中完成登录后，脚本通过 CDP 协议毫秒级检测核心凭据（`SAPISID`、`SID`、`HSID` 等），格式化后高亮打印并自动复制到剪贴板。

---

## 🚀 使用方法

您可以选择 **Node.js** 或 **Python** 任一版本运行：

### 选项 1：使用 Node.js (推荐，0 依赖)
要求：Node.js >= 20.0
```bash
# 进入插件根目录
node tools/get_cookie.js
```

### 选项 2：使用 Python (配合 uv)
要求：Python >= 3.9，推荐使用 `uv`
```bash
# 使用 uv 一键运行（自动解析 PEP 723 依赖）：
uv run tools/get_cookie.py

# 或使用标准 python（需手动安装 websockets 库）：
pip install websockets
python tools/get_cookie.py
```

---

## ⚙️ 常用命令行参数

两个脚本支持完全相同的参数：

| 参数 | 缩写 | 说明 | 默认值 |
| :--- | :--- | :--- | :--- |
| `--browser-path` | `-p` | 手动指定浏览器可执行文件路径 | 自动从内置 10+ 路径探测 |
| `--port` | | 指定 CDP 远程调试端口 | 自动寻找空闲端口 (如 9222) |
| `--url` | | 登录起始网页 | `https://music.youtube.com` |
| `--timeout` | | 登录等待超时时间 (单位：秒) | `300` (5 分钟) |
| `--help` | `-h` | 查看帮助提示 | |

### 指定自定义浏览器示例：
```bash
# Windows 指定特殊路径的 Chrome
node tools/get_cookie.js -p "D:\Software\Chrome\Application\chrome.exe"

# macOS 指定 Brave 浏览器
node tools/get_cookie.js -p "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"

# Linux 指定 Chromium
uv run tools/get_cookie.py -p "/usr/bin/chromium"
```

---

## 📋 下一步
登录成功后，脚本控制台会输出完整的 Cookie 字符串并自动复制进剪贴板。
打开 **Lazer 客户端** -> 点击左侧「登录」-> 平台选择「YouTube Music」-> 将内容粘贴到输入框后点击登录即可！
