# 🧪 YouTube Music 插件自动化测试套件

本目录包含用于验证 **YouTube / YouTube Music InnerTube API** 协议抓取、数据提纯及核心特性的 Python 自动化测试脚本与工程调试工具。

---

## 🌲 目录结构与脚本清单 (Tree)

```text
test/
├── common.py                 # InnerTube 请求封装、客户端配置 (WEB_REMIX/ANDROID_MUSIC/VISIONOS) 与代理管理
├── test_all.py               # 全量一键集成测试执行器 (自动顺序运行全套测试用例)
├── test_artist_and_mixart.py # 艺人详情页全量歌曲 (88+ 首 top songs) 探查及 Mixart 动态跑马灯拼图测试
├── test_charts.py            # YouTube Music 官方全球与地区榜单 (热门歌曲/MV/新歌榜) 解析测试
├── test_chart_match.py       # 榜单数据与歌曲元数据精准匹配度测试
├── test_home_feed.py         # 主页探索流 (今日限定/私人漫游/编辑精选/专属合辑) 抓取测试
├── test_lyrics.py            # ANDROID_MUSIC 毫秒级逐行滚动歌词 (LRC)、LyricFind 回退与纯音乐识别测试
├── test_playlist.py          # 歌单详情、我喜欢的音乐 (Favorites) 与 continuation 分页加载测试
├── test_search.py            # 全域综合搜索与分类 Filter (歌曲/专辑/歌手/歌单) 检索测试
├── test_song.py              # 单曲基础详情与播放元数据提纯测试
├── test_stream.py            # InnerTube 音频流 (128kbps AAC/Opus) 免 JS 逆向直链提取测试
├── test_stream_nodes.py      # 多客户端直链节点连通性与限速 (Anti-Throttling) 表现测试
└── tools/                    # 开发者辅助探查与清理工具
    ├── clean_lazer_cache.py  # 本地 Lazer 播放器缓存与持久化状态清理工具
    ├── compare_stream_urls.py # 不同客户端下发音频直链格式与比特率对比工具
    └── inspect_lyrics.py     # 歌曲原始 cueRange 时间戳与歌词文本深度探查工具
```

---

## 🚀 运行方法

测试脚本基于 Python 3（可使用项目根目录 `.venv` 或系统 Python / `uv`）：

```bash
# 1. 运行单个模块测试 (例如搜索验证)
uv run python test/test_search.py

# 2. 运行歌词毫秒级同步解析测试
uv run python test/test_lyrics.py

# 3. 运行全量集成测试
uv run python test/test_all.py
```

> [!NOTE]
> 默认会自动使用本机 HTTP/HTTPS 代理 `http://127.0.0.1:7890`，可通过环境变量 `HTTP_PROXY` / `HTTPS_PROXY` 自定义。
