# Lazer YouTube Music Plugin - Agent Instructions

## 项目定位与目标
本项目是针对 [Lazer](https://github.com/chuxuehaocai/Lazer) 音乐播放器（Flutter/Dart 原生客户端）开发的**YouTube Music 第三方 Lua 插件**（`lazer.youtube`）。
插件以规范的 ZIP 格式打包分发，运行在 Lazer 宿主内置的独立受限 Lua 沙箱环境（基于 Dart 实现的 `lua_dardo_plus` 解释器）中。

---

## 宿主底层沙箱避坑红线 (Critical Lazer Sandbox Guidelines)

Lazer 宿主基于 Dart 的 `LuaPluginRuntime` 与 `lua_dardo_plus` 运行插件代码，存在以下**致命底层约束与黑盒缺陷**，所有开发者与 Agent 必须无条件严格遵守：

### 1. 全局标准库剥离（禁止访问 `os.*` / `io.*`）
* **宿主行为**：Lazer 在启动 VM 时执行 `lua.setGlobal(key)` 将 `'io', 'os', 'package', 'debug', 'dofile', 'loadfile', 'load', 'loadstring', 'require', 'print'` **全部置为了 `nil`**。
* **致命陷阱**：调用 `os.time()`、`os.date()` 或 `io.*` 会立即触发 `attempt to index a nil value` 导致当前调用崩溃，并在歌单页面展示“歌单读取失败，请重试。”。
* **规避准则**：
  * 获取当前时间戳**必须且只能使用 `host.now()`**（返回毫秒整数，等价于 `DateTime.now().millisecondsSinceEpoch`）。
  * 插件内计算缓存超时（TTL）统一采用毫秒时间差：`host.now() - at < ttl_ms`。

### 2. Dart 解释器模式匹配缺陷（禁止使用 `%d`/`%s` 模式串）
* **解释器缺陷**：`lua_dardo_plus` 的 `string.match` 内部直接调用了 Dart 的 `RegExp(pattern).firstMatch(tail!)`，且**只返回 `group(0)`**。
* **致命陷阱**：
  * Lua 专属的字符类转义（如 `%d` 数字、`%s` 空格、`%w`、`%-`）在 Dart 正则表达式中被作为**普通字面量字符 `%` 和对应字母**处理，导致数字或空白匹配永远失败并返回 `nil`！
  * 多捕获组解构全部失效（只返回单个 `group(0)`，其余解构变量全为 `nil`）。
* **规避准则**：
  * **严禁在核心逻辑中依赖带有 Lua `%` 转义模式的 `string.match`**。
  * 数字与数值提取统一采用**纯字符字节流扫描**（`string.byte >= 48 and <= 57`）。
  * 字符串查找统一采用带 plain 标志的明文检索：`string.find(str, substr, 1, true)`。

### 3. Table 到 Dart 类型转换严格契约（List vs Map）
* **宿主转换规则**：
  * 仅当 Table 的键为**连续整数 `1..N`** 时，Dart 才会将其转换为 Dart `List`。
  * 空表 `{}` 会被解释器先转换为 Dart 空 `Map`（宿主 `_page` 会特判处理为空 List）。
  * **一旦 Table 包含非连续整数键或字符串键，Dart 立即将其转为 `Map`**。
* **致命陷阱**：在需要返回列表的方法（如 `favorites`, `playlistSongs`, `albumSongs`, `artistSongs`）中，若把分页 Token、count 或 meta 信息混入同一个 Table 返回，宿主在执行 `raw is! List` 检查时会立即抛出 `MusicGatewayException(reason: 'invalid payload')`，导致界面整页报错。
* **规避准则**：
  * 列表分页方法**必须严格返回纯数组 Table**，禁止夹带任何非数字键属性。

### 4. 网络请求限制与域名白名单（`host.http`）
* **宿主限制**：
  * 单次 HTTP 请求超时由宿主硬编码为 **30 秒**。
  * 请求体与响应体限制：单次 body 超过 2MB 会被宿主抛出 `FormatException('Request too large')`。
  * 必须在 `manifest.json` 的 `network` 白名单中显式声明目标域名（如 `*.youtube.com`, `*.googlevideo.com`）。
  * 宿主强制剥离 `host`, `content-length`, `connection` 标头，不可自定义覆盖。
* **规避准则**：网络请求必须包裹在 `pcall` 中，并实现轻量超时熔断，失败时返回安全空数据，绝不阻塞调用队列。

### 5. 存储 1MB 物理天花板（`host.storage_set`）
* **宿主限制**：单个插件的 `storage.json` 总大小超过 1MB 时，宿主直接抛出 `FormatException('Storage full')`。
* **规避准则**：`host.storage_set` 仅用于持久化用户的 Cookie、Visitor Data、Session 及简单标记，**严禁将大批量歌曲列表或大型 JSON 写入 storage**。大列表缓存只能保存在 Lua 模块级局部变量中。

### 6. 并发与 Isolate 崩溃重启机制
* **宿主限制**：插件运行在独立 Isolate 的单线程事件循环中，后台调用（`scrobble`, `playStats`, `lyrics`, `song`）超时预算仅有 10 秒。一旦超时，宿主将强制终止并**重启整个 Lua VM**。
* **规避准则**：严禁死循环或阻塞式网络请求，异常需秒级退出并返回降级兜底。

---

## YouTube 专有核心规范与业务策略 (YouTube Specifics)

1. **Innertube 双栈客户端路由**：
   - `WEB_REMIX`（YouTube Music Web 客户端）：用于 `browse`、`search`、`next`、主页推荐、歌单探索、喜欢列表（`VLLM`）。
   - `VISIONOS`（Apple Vision Pro 客户端）：用于 `player` 音频直链与沉浸式高码率媒体流解析（无需 JS 解密签名即可直出音频格式）。
2. **SAPISIDHASH 鉴权算法**：
   - 提取 Cookie 中的 `SAPISID` 或 `__Secure-3PAPISID`。
   - 时间戳采用秒级整数：`timestamp = math.floor(host.now() / 1000)`。
   - 哈希公式：`sha1(timestamp .. " " .. sapisid .. " https://music.youtube.com")`。
   - 生成标头：`Authorization: SAPISIDHASH <timestamp>_<sha1>`。
3. **双轨封面视觉融合与 Mix Art**：
   - 常规曲目采用 `https://i.ytimg.com/vi/<vid>/hqdefault.jpg`。
   - 针对 YouTube 服务端合成的电台/合辑封面（`/image/mixart?r=...`），保留原样高清 URL 下发，与方形唱片封面形成双轨视觉体验。
4. **Continuation Token 分页协议**：
   - YouTube 接口（如主页推荐、喜欢列表）基于长 continuation 令牌分页。
   - 增量续拉必须将新曲目追加到内存缓存末尾，返回纯数组 Table 切片。
5. **无正则播放量多语言解析**：
   - 提取中、日、英等多语系播放次数（`万`、`亿`、`K`、`M`、`B`、`views`、`回視聴`），统一采用**纯字符流字节扫描**，杜绝任何正则表达式，格式化为国际通用的 `[17M 播放]` / `[850K 播放]`。
