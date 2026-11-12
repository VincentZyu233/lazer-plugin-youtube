# Lazer YouTube Music Cookie 抓取工具

本目录提供了全自动的 Cookie 抓取脚本，帮助您在无需手动打开浏览器 F12 开发者工具的情况下，一键完成 Google 账号登录并提取 Cookie。

---

## 🌟 特性

- **全平台支持**：内置 Windows、macOS、Linux 下 10+ 常见 Chrome / Edge / Brave / Chromium 默认安装路径；
- **智能探测与自定义**：支持自动探测已安装浏览器（优先匹配系统主流日常浏览器），也支持通过 `-p` / `--browser-path` 手动传入浏览器路径；
- **真实浏览器交互**：拉起系统真实的浏览器窗口，自动去除自动化特征标记（`--disable-blink-features=AutomationControlled`），避免触发 Google「此浏览器或应用可能不安全」的风控拦截；
- **贴心常驻与自动退出**：默认在抓取完成后保持浏览器窗口开启，方便您在网页端听歌与在 Lazer 客户端中对照；也可通过 `-q` / `--quit` 参数让其提取后自动关闭；
- **毫秒级捕获与复制**：用户在浏览器中完成登录并跳回 YouTube Music 主页后，脚本通过 CDP 协议自动检测并仅提取发往 `music.youtube.com` 的完整凭据（避免多域名覆盖冲突），高亮打印并自动复制到系统剪贴板。

---

## 🚀 使用方法

要求：Node.js >= 20.0（利用原生 WebSocket，0 第三方依赖）

```bash
# 进入插件根目录
cd tools
node get_cookie.js

# 或在仓库根目录直接运行
node tools/get_cookie.js
```

---

## ⚙️ 常用命令行参数

| 参数 | 缩写 | 说明 | 默认值 |
| :--- | :--- | :--- | :--- |
| `--browser-path` | `-p` | 手动指定浏览器可执行文件路径 | 自动从内置 10+ 路径探测 |
| `--quit` | `-q` | 登录完成并提取 Cookie 后自动关闭浏览器 | 默认不关闭 (保持开启供听歌与对照) |
| `--port` | | 指定 CDP 远程调试端口 | 自动寻找空闲端口 (如 9222) |
| `--url` | | 登录起始网页 | `https://music.youtube.com` |
| `--timeout` | | 登录等待超时时间 (单位：秒) | `300` (5 分钟) |
| `--help` | `-h` | 查看帮助提示 | |

### 示例：

```bash
# 登录完成后自动关闭浏览器
node tools/get_cookie.js -q

# 指定自定义浏览器路径并保持窗口开启
node tools/get_cookie.js -p "C:\Program Files\Google\Chrome\Application\chrome.exe"
```

---

## 📋 下一步
登录成功后，脚本控制台会输出完整的 Cookie 字符串并自动复制进系统剪贴板。
打开 **Lazer 客户端** -> 点击左侧「登录」-> 平台选择「YouTube Music」-> 将内容粘贴到输入框后点击登录即可！
