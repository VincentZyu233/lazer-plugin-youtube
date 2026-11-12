# 🎵 Lazer YouTube Music Plugin (YouTube 音乐插件)

专为 [Lazer](https://github.com/chuxuehaocai/Lazer) 现代跨平台音乐播放器打造的 **YouTube & YouTube Music 官方/第三方 Lua Gateway 扩展插件**。

---

## ✨ 特性亮点

- **双轨全域检索**：
  - **YouTube Music**：优先呈现录音室单曲、艺人官方专辑与榜单。
  - **全量 YouTube 视频支持**：支持直接检索任意 YouTube 视频的音频轨，或在搜索栏直接粘贴视频分享链接（`youtu.be/...` 或 `watch?v=...`）秒开！
- **移动端 InnerTube 直链流提取**：
  - 参考 `yt-dlp` 逆向精髓，通过伪装移动端（iOS / Android）客户端协议，直接提取原生 128kbps AAC / 160kbps Opus 音频直链，免去复杂的网页端 JS 解密开销。
- **轻量独立**：纯 Lua 实现，无额外 Python / 原生动态库依赖。

---

## 📦 安装使用指南

### 📥 方法一：通过 ZIP 导入

1. 前往本仓库的 [Releases](../../releases) 页面，下载最新的 `lazer.youtube.zip`。
2. 打开 **Lazer** 播放器，进入 **设置 -> 插件管理**。
3. 点击 **导入 ZIP 插件**，选择下载好的 `lazer.youtube.zip`。
4. 启用插件后，在播放器音源切换列表即可选择 **YouTube Music**！

### 🛒 方法二：通过插件市场源自动更新

上架官方插件市场后，可在 Lazer 内置市场一键安装与无感热更新。

---

## 🛠️ 本地构建与打包

项目内置了 Node.js 一键校验与打包脚本：

```bash
# 校验清单并打包为 dist/lazer.youtube.zip，同时输出 SHA-256 和 plugins.json 片段
node tools/build.js
```

---

## 💖 鸣谢与致敬

- [chuxuehaocai/Lazer](https://github.com/chuxuehaocai/Lazer) - 优雅而纯粹的手工打造跨平台音乐播放器。
- [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp) - 业界领先的音视频提取框架与逆向工程参考。

---

## 📄 许可证

本项目遵循 MIT 协议开源。仅供技术学习与交流使用，音视频版权归 YouTube、Google LLC 及相关版权方所有。
