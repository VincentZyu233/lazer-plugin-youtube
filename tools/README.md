# Lazer YouTube Music 凭据获取工具 (v0.2.3)

本目录提供了全自动的 YouTube Music 登录凭据获取工具以及插件的一键校验构建脚本，全面原生支持 **Windows**、**macOS** 与 **Linux** 三大操作系统。

---

## 🌲 目录结构与工具清单 (Tree)

```text
tools/
├── build.js         # 插件生产环境打包构建脚本 (校验 manifest.json、计算 SHA-256、压缩 dist/lazer.youtube.zip)
├── get_cookie.js    # YouTube / YouTube Music 交互式浏览器 Cookie 跨平台自动抓取与持久化注入工具
└── README.md        # 工具链详细使用说明与参数文档
```

---

## 🌟 使用方法

要求：Node.js >= 18.0（纯原生标准库，**0 第三方 npm 依赖**）

### 1. 抓取 Cookie 并自动注入 Lazer 本地存储（默认推荐）
```bash
node tools/get_cookie.js
```
脚本会自动探测系统中的 Chrome / Edge / Brave / Chromium 浏览器并拉起独立窗口引导登录。登录成功后：
- **跨平台自动注入**：自动识别 Windows (`%APPDATA%`)、macOS (`~/Library/Application Support/dev.naominet.lazer`) 和 Linux (`~/.local/share/dev.naominet.lazer`) 的数据存储位置，直接写入 `storage.json` 并输出文件的**本地物理绝对路径**。
- **极简登录体验**：在 Lazer 的 Cookie 输入框中直接输入 `-1` 或 `LOCAL` 点击【登录】（绕过 Flutter 前端空值拦截），或直接重启 Lazer 客户端，即可瞬间完成登录。
- **自动复制剪贴板**：跨平台适配 PowerShell/clip (Win)、`pbcopy` (Mac)、`wl-copy`/`xclip`/`xsel` (Linux)，完整复制到系统剪贴板备用。
- **窗口保持开启**：默认保留浏览器窗口可继续播放试听。

### 2. 仅抓取并复制到剪贴板，跳过写入 Lazer 本地存储
```bash
node tools/get_cookie.js -s
# 或
node tools/get_cookie.js --skip-storage
```

### 3. 抓取 Cookie 成功后自动关闭浏览器
```bash
node tools/get_cookie.js -q
# 或
node tools/get_cookie.js --quit
```

### 4. 生成脚本同级目录本地凭据备份 (用于离线调研与数据分析)
```bash
node tools/get_cookie.js -b
# 或
node tools/get_cookie.js --backup
```
在 `tools/` 脚本同级目录下生成 `cookie_backup.json`，方便离线研究或多环境备份（已配置 `.gitignore` 防止意外提交凭据）。
