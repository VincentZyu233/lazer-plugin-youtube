#!/usr/bin/env node
/**
 * Lazer YouTube Music Cookie 自动抓取工具
 * 
 * 版本号跟随 manifest.json 自动同步。
 * 功能：
 *   拉起独立的 Chrome / Edge 浏览器窗口引导登录，
 *   通过 Chrome DevTools Protocol (CDP) 自动监听并提取 YouTube Music 核心 Cookie，
 *   抓取完成后自动复制到剪贴板，可直接粘贴进 Lazer 插件设置中使用。
 * 
 * 依赖：Node.js >= 18.0 (纯原生标准库，0 第三方 npm 依赖)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const readline = require('readline');
const { spawn, exec } = require('child_process');

// 从 manifest.json 动态读取插件版本号
const MANIFEST = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'manifest.json'), 'utf8'));
const VERSION = MANIFEST.version;

// 解析命令行参数
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    quitAfterDone: false, // 是否在抓取成功后自动关闭浏览器
    skipStorage: false,   // 是否跳过向 Lazer 本地插件 storage 写入
    backup: false,        // 是否在脚本同级目录生成 cookie_backup.json 备份
    browserPath: null,
    port: 0,
    url: 'https://music.youtube.com',
    timeout: 300,         // 秒
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-q' || arg === '--quit') {
      options.quitAfterDone = true;
    } else if (arg === '-s' || arg === '--skip-storage') {
      options.skipStorage = true;
    } else if (arg === '-b' || arg === '--backup') {
      options.backup = true;
    } else if (arg === '-p' || arg === '--browser-path') {
      options.browserPath = args[++i];
    } else if (arg === '--port') {
      options.port = parseInt(args[++i], 10);
    } else if (arg === '--timeout') {
      options.timeout = parseInt(args[++i], 10);
    } else if (arg === '-h' || arg === '--help') {
      options.help = true;
    }
  }

  return options;
}

function showHelp() {
  console.log(`
======================================================================
  Lazer YouTube Music Cookie 自动抓取工具 (v${VERSION})
======================================================================

使用方法:
  node tools/get_cookie.js [参数]

参数选项:
  -b, --backup        在脚本同级目录生成 cookie_backup.json 凭据备份文件 (用于离线调研与恢复)
  -s, --skip-storage  跳过自动写入 Lazer 插件本地存储 (默认自动写入免贴登录)
  -q, --quit          抓取 Cookie 成功后自动关闭浏览器窗口 (默认保持打开)
  -p, --browser-path  指定浏览器可执行文件路径 (默认自动探测 Chrome / Edge)
  --port <port>       指定调试端口 (默认自动分配空闲端口)
  --timeout <sec>     等待登录超时时间 (秒，默认 300)
  -h, --help          查看本帮助信息

示例:
  node tools/get_cookie.js            # 抓取并自动注入 Lazer 插件存储，免复制粘贴
  node tools/get_cookie.js -s         # 仅抓取并复制到剪贴板，不写入 Lazer 存储
  node tools/get_cookie.js -q         # 抓取完成后自动关闭浏览器
`);
}

// 跨平台自动探测浏览器路径 (Windows / macOS / Linux)
function detectBrowser() {
  const platform = os.platform();

  if (platform === 'win32') {
    const prefixes = [
      process.env.LOCALAPPDATA,
      process.env['PROGRAMFILES'],
      process.env['PROGRAMFILES(X86)']
    ].filter(Boolean);

    const candidates = [];
    for (const prefix of prefixes) {
      candidates.push(
        path.join(prefix, 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(prefix, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(prefix, 'BraveSoftware', 'Brave-Browser', 'Application', 'brave.exe')
      );
    }
    for (const c of candidates) {
      try {
        if (fs.existsSync(c)) return c;
      } catch (_) {}
    }
  } else if (platform === 'darwin') {
    const home = os.homedir();
    const candidates = [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
      '/Applications/Chromium.app/Contents/MacOS/Chromium',
      path.join(home, 'Applications/Google Chrome.app/Contents/MacOS/Google Chrome'),
      path.join(home, 'Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'),
      path.join(home, 'Applications/Brave Browser.app/Contents/MacOS/Brave Browser')
    ];
    for (const c of candidates) {
      try {
        if (fs.existsSync(c)) return c;
      } catch (_) {}
    }
  } else {
    // Linux: 检查 PATH 环境变量中的候选浏览器命令
    const commands = [
      'google-chrome-stable',
      'google-chrome',
      'chromium',
      'chromium-browser',
      'microsoft-edge-stable',
      'microsoft-edge',
      'brave-browser'
    ];
    const pathDirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
    for (const cmd of commands) {
      for (const dir of pathDirs) {
        const full = path.join(dir, cmd);
        try {
          fs.accessSync(full, fs.constants.X_OK);
          return full;
        } catch (_) {}
      }
    }
    // 常见绝对路径 / snap / flatpak
    const absoluteCandidates = [
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/snap/bin/chromium',
      '/snap/bin/google-chrome'
    ];
    for (const c of absoluteCandidates) {
      try {
        if (fs.existsSync(c)) return c;
      } catch (_) {}
    }
  }

  return null;
}

// 获取随机可用端口
function getFreePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => {
      const port = s.address().port;
      s.close(() => resolve(port));
    });
    s.on('error', reject);
  });
}

// 跨平台复制字符串到系统剪贴板 (与 0.1.15 对齐：Windows 纯原生 clip.exe 标准字节流写入，0 截断 0 污染)
function copyToClipboard(text) {
  return new Promise((resolve) => {
    const platform = os.platform();
    if (platform === 'win32') {
      const proc = spawn('clip');
      proc.on('error', () => resolve(false));
      proc.stdin.write(text);
      proc.stdin.end();
      proc.on('close', (code) => resolve(code === 0));
      return;
    }

    if (platform === 'darwin') {
      const proc = spawn('pbcopy');
      proc.on('error', () => resolve(false));
      proc.stdin.write(text);
      proc.stdin.end();
      proc.on('close', (code) => resolve(code === 0));
      return;
    }

    // Linux: 优先尝试 Wayland wl-copy，再尝试 X11 xclip，最后尝试 xsel
    const tryTool = (cmd, args, next) => {
      const proc = spawn(cmd, args);
      let failed = false;
      proc.on('error', () => {
        failed = true;
        next();
      });
      proc.on('close', (code) => {
        if (!failed && code === 0) {
          resolve(true);
        } else {
          next();
        }
      });
      try {
        proc.stdin.write(text);
        proc.stdin.end();
      } catch (_) {
        next();
      }
    };

    tryTool('wl-copy', [], () => {
      tryTool('xclip', ['-selection', 'clipboard'], () => {
        tryTool('xsel', ['--clipboard', '--input'], () => {
          resolve(false);
        });
      });
    });
  });
}

// 跨平台探测 Lazer 插件数据存储路径 (Windows / macOS / Linux)
function resolveLazerStoragePath() {
  const platform = os.platform();
  const home = os.homedir();
  const pluginId = 'lazer.youtube';
  const candidates = [];

  if (platform === 'win32') {
    const appData = process.env.APPDATA || path.join(home, 'AppData', 'Roaming');
    candidates.push(
      path.join(appData, 'dev.naominet', 'lazer_nextgen', 'lua_plugin_data', pluginId, 'storage.json')
    );
  } else if (platform === 'darwin') {
    candidates.push(
      path.join(home, 'Library', 'Application Support', 'dev.naominet.lazer', 'lua_plugin_data', pluginId, 'storage.json'),
      path.join(home, 'Library', 'Application Support', 'dev.naominet', 'lazer_nextgen', 'lua_plugin_data', pluginId, 'storage.json'),
      path.join(home, 'Library', 'Containers', 'dev.naominet.lazer', 'Data', 'Library', 'Application Support', 'dev.naominet.lazer', 'lua_plugin_data', pluginId, 'storage.json')
    );
  } else {
    // Linux (遵循 XDG Base Directory 规范)
    const xdgData = process.env.XDG_DATA_HOME || path.join(home, '.local', 'share');
    candidates.push(
      path.join(xdgData, 'dev.naominet.lazer', 'lua_plugin_data', pluginId, 'storage.json'),
      path.join(xdgData, 'lazer_nextgen', 'lua_plugin_data', pluginId, 'storage.json'),
      path.join(xdgData, 'dev.naominet', 'lazer_nextgen', 'lua_plugin_data', pluginId, 'storage.json')
    );
  }

  // 1. 优先探测已存在 storage.json 或其上级数据目录的活跃路径
  for (const file of candidates) {
    if (fs.existsSync(file)) return path.resolve(file);
    const parentDir = path.dirname(path.dirname(file)); // lua_plugin_data
    if (fs.existsSync(parentDir)) return path.resolve(file);
  }

  // 2. 默认返回该平台的第一顺位标准路径
  return path.resolve(candidates[0]);
}

// 自动向 Lazer 本地插件存储注入凭据，成功时返回文件的绝对物理路径，失败返回 null
// 自动向 Lazer 本地插件存储注入凭据，成功时返回文件的绝对物理路径，失败返回 null
function autoInjectToLazerStorage(cookieStr, profile) {
  try {
    const storageFile = resolveLazerStoragePath();
    if (!storageFile) return null;

    const storageDir = path.dirname(storageFile);
    if (!fs.existsSync(storageDir)) {
      fs.mkdirSync(storageDir, { recursive: true });
    }

    let data = {};
    if (fs.existsSync(storageFile)) {
      try { data = JSON.parse(fs.readFileSync(storageFile, 'utf8')); } catch (_) {}
    }

    data.user_cookie = cookieStr;
    data.backup_cookie = cookieStr; // 同时记录备用凭据，防止退出登录后无法以 -1 快速找回
    if (profile && profile.name) {
      data.user_name = profile.name;
      data.user_id = profile.id || profile.handle || profile.name;
      if (profile.avatarUrl) {
        data.user_avatar = profile.avatarUrl;
      }
    } else {
      if (!data.user_id || data.user_id === '') {
        data.user_id = 'yt_authenticated';
      }
      if (!data.user_name || data.user_name === '') {
        data.user_name = 'YouTube 用户';
      }
    }

    fs.writeFileSync(storageFile, JSON.stringify(data, null, 2), 'utf8');
    return storageFile;
  } catch (_) {
    return null;
  }
}

// 在脚本同级目录生成一份凭据备份文件 (cookie_backup.json) 供调研与离线备份
function saveBackupCredentials(cookieStr, profile) {
  try {
    const backupFile = path.join(__dirname, 'cookie_backup.json');
    let data = {};
    const storageFile = resolveLazerStoragePath();
    if (storageFile && fs.existsSync(storageFile)) {
      try { data = JSON.parse(fs.readFileSync(storageFile, 'utf8')); } catch (_) {}
    }

    data.user_cookie = cookieStr;
    data.backup_cookie = cookieStr;
    data.backup_time = new Date().toISOString();
    if (profile && profile.name) {
      data.user_name = profile.name;
      data.user_id = profile.id || profile.handle || profile.name;
      if (profile.avatarUrl) {
        data.user_avatar = profile.avatarUrl;
      }
    } else {
      if (!data.user_id || data.user_id === '') {
        data.user_id = 'yt_authenticated';
      }
      if (!data.user_name || data.user_name === '') {
        data.user_name = 'YouTube 用户';
      }
    }

    fs.writeFileSync(backupFile, JSON.stringify(data, null, 2), 'utf8');
    return backupFile;
  } catch (err) {
    console.error(`[!] 写入备份文件失败: ${err.message}`);
    return null;
  }
}

// 简易 WebSocket 客户端 (纯原生实现，无需 ws 依赖)
class SimpleWebSocket {
  constructor(wsUrl) {
    this.url = new URL(wsUrl);
    this.socket = null;
    this.buffer = Buffer.alloc(0);
    this.onmessage = null;
    this.onopen = null;
    this.onclose = null;
    this.onerror = null;
  }

  connect() {
    return new Promise((resolve, reject) => {
      const key = Buffer.from(Math.random().toString()).toString('base64');
      const req = http.request({
        hostname: this.url.hostname,
        port: this.url.port,
        path: this.url.pathname + this.url.search,
        headers: {
          'Connection': 'Upgrade',
          'Upgrade': 'websocket',
          'Sec-WebSocket-Version': '13',
          'Sec-WebSocket-Key': key
        }
      });

      req.on('upgrade', (res, socket) => {
        this.socket = socket;
        this._setupSocket();
        if (this.onopen) this.onopen();
        resolve();
      });

      req.on('error', (err) => {
        if (this.onerror) this.onerror(err);
        reject(err);
      });

      req.end();
    });
  }

  _setupSocket() {
    this.socket.on('data', (chunk) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      this._parseFrames();
    });
    this.socket.on('close', () => {
      if (this.onclose) this.onclose();
    });
    this.socket.on('error', (err) => {
      if (this.onerror) this.onerror(err);
    });
  }

  _parseFrames() {
    while (this.buffer.length >= 2) {
      const b1 = this.buffer[0];
      const b2 = this.buffer[1];
      const opcode = b1 & 0x0f;
      let len = b2 & 0x7f;
      let offset = 2;

      if (len === 126) {
        if (this.buffer.length < 4) return;
        len = this.buffer.readUInt16BE(2);
        offset = 4;
      } else if (len === 127) {
        if (this.buffer.length < 10) return;
        len = Number(this.buffer.readBigUInt64BE(2));
        offset = 10;
      }

      if (this.buffer.length < offset + len) return;

      const payload = this.buffer.slice(offset, offset + len);
      this.buffer = this.buffer.slice(offset + len);

      if (opcode === 1) { // text
        if (this.onmessage) this.onmessage(payload.toString('utf8'));
      } else if (opcode === 8) { // close
        this.close();
      }
    }
  }

  send(data) {
    if (!this.socket || this.socket.destroyed) return;
    const payload = Buffer.from(data, 'utf8');
    const len = payload.length;
    let header;

    if (len <= 125) {
      header = Buffer.from([0x81, 0x80 | len]);
    } else if (len <= 65535) {
      header = Buffer.alloc(4);
      header[0] = 0x81;
      header[1] = 0x80 | 126;
      header.writeUInt16BE(len, 2);
    } else {
      header = Buffer.alloc(10);
      header[0] = 0x81;
      header[1] = 0x80 | 127;
      header.writeBigUInt64BE(BigInt(len), 2);
    }

    const mask = Buffer.from([0x12, 0x34, 0x56, 0x78]);
    const masked = Buffer.alloc(len);
    for (let i = 0; i < len; i++) {
      masked[i] = payload[i] ^ mask[i % 4];
    }

    this.socket.write(Buffer.concat([header, mask, masked]));
  }

  close() {
    if (this.socket && !this.socket.destroyed) {
      this.socket.end();
    }
  }
}

// CDP 交互客户端
class CDPClient {
  constructor(wsUrl) {
    this.ws = new SimpleWebSocket(wsUrl);
    this.nextId = 1;
    this.callbacks = new Map();
  }

  async connect() {
    await this.ws.connect();
    this.ws.onmessage = (msg) => {
      try {
        const data = JSON.parse(msg);
        if (data.id && this.callbacks.has(data.id)) {
          const { resolve, reject } = this.callbacks.get(data.id);
          this.callbacks.delete(data.id);
          if (data.error) reject(new Error(data.error.message));
          else resolve(data.result);
        }
      } catch (_) {}
    };
  }

  send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      this.callbacks.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.ws.close();
  }
}

// 检查 Cookie 字符串是否包含核心鉴权项
function evaluateCookie(cookieStr) {
  const hasLoginInfo = cookieStr.includes('LOGIN_INFO=');
  const hasSapisid = cookieStr.includes('SAPISID=');
  const hasSid = cookieStr.includes('SID=');
  const hasHsid = cookieStr.includes('HSID=');
  const isComplete = hasLoginInfo && hasSapisid && hasSid && hasHsid;
  return { hasLoginInfo, hasSapisid, hasSid, hasHsid, isComplete };
}

// 验证 Cookie 是否已被 Google 激活并直接提取账号昵称与头像
function fetchAccountProfile(cookieStr) {
  return new Promise((resolve) => {
    try {
      const m = cookieStr.match(/[;\s]?SAPISID=([^;\s\r\n]+)/) || cookieStr.match(/[;\s]?__Secure-3PAPISID=([^;\s\r\n]+)/);
      if (!m) return resolve(null);
      const sapisid = m[1];
      const ts = Math.floor(Date.now() / 1000);
      const hash = crypto.createHash('sha1').update(`${ts} ${sapisid} https://music.youtube.com`).digest('hex');
      const auth = `SAPISIDHASH ${ts}_${hash}`;

      const req = https.request('https://music.youtube.com/youtubei/v1/account/account_menu', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
          'Origin': 'https://music.youtube.com',
          'X-Origin': 'https://music.youtube.com',
          'X-Goog-Api-Format-Version': '2',
          'Cookie': cookieStr,
          'Authorization': auth
        }
      }, (res) => {
        let buf = '';
        res.on('data', c => buf += c);
        res.on('end', () => {
          if (res.statusCode !== 200) return resolve(null);
          try {
            const j = JSON.parse(buf);
            const act = j.actions?.[0]?.openPopupAction?.popup?.multiPageMenuRenderer?.header?.activeAccountHeaderRenderer;
            if (act) {
              const name = act.accountName?.runs?.[0]?.text;
              const handle = act.channelHandle?.runs?.[0]?.text;
              const thumbs = act.accountPhoto?.thumbnails;
              const avatar = thumbs?.[thumbs.length - 1]?.url;
              return resolve({
                name: name || 'YouTube 用户',
                id: handle || name || 'yt_authenticated',
                avatarUrl: avatar ? (avatar.startsWith('//') ? `https:${avatar}` : avatar) : ''
              });
            }
          } catch (_) {}
          resolve(null);
        });
      });
      req.on('error', () => resolve(null));
      req.write(JSON.stringify({ context: { client: { clientName: 'WEB_REMIX', clientVersion: '1.20261110.04.00' } } }));
      req.end();
    } catch (_) {
      resolve(null);
    }
  });
}

async function main() {
  const options = parseArgs();
  if (options.help) {
    showHelp();
    return;
  }

  console.log(`======================================================================`);
  console.log(`  Lazer YouTube Music Cookie 抓取工具 (v${VERSION})`);
  console.log(`======================================================================\n`);

  const browserPath = options.browserPath || detectBrowser();
  if (!browserPath) {
    console.error(`[!] 错误：未能在系统中检测到 Chrome 或 Edge 浏览器。`);
    console.error(`    请使用 -p 或 --browser-path 参数手动指定浏览器可执行文件路径。\n`);
    process.exit(1);
  }

  console.log(`[*] 使用浏览器: ${browserPath}`);
  const port = options.port || await getFreePort();
  const userDataDir = path.join(os.tmpdir(), `lazer_ytm_auth_${Date.now()}`);

  console.log(`[*] 启动浏览器独立授权会话 (调试端口: ${port})...`);
  const browserProc = spawn(browserPath, [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    '--no-first-run',
    '--no-default-browser-check',
    options.url
  ], {
    detached: false,
    stdio: 'ignore'
  });

  browserProc.on('error', (err) => {
    console.error(`[!] 启动浏览器进程失败:`, err.message);
    process.exit(1);
  });

  console.log(`[*] 等待浏览器就绪...`);
  console.log(`\n>>> 请在弹出的浏览器窗口中完成 Google / YouTube 账号登录 <<<`);
  console.log(`    (工具正在后台持续监听 Cookie 凭据，登录成功将自动捕获并校验)\n`);

  let capturedCookie = null;
  let capturedProfile = null;
  const pollStart = Date.now();
  const pollTimeout = options.timeout * 1000;

  while (Date.now() - pollStart < pollTimeout) {
    try {
      const targets = await new Promise((resolve, reject) => {
        http.get(`http://127.0.0.1:${port}/json`, (r) => {
          let buf = '';
          r.on('data', chunk => buf += chunk);
          r.on('end', () => {
            try { resolve(JSON.parse(buf)); } catch (_) { resolve([]); }
          });
        }).on('error', reject);
      });

      const ytTarget = Array.isArray(targets) && targets.find(t => t.url && (t.url.includes('music.youtube.com') || t.url.includes('youtube.com')));

      if (ytTarget && ytTarget.webSocketDebuggerUrl) {
        let cookies = null;
        let domProfile = null;
        try {
          const cdp = new CDPClient(ytTarget.webSocketDebuggerUrl);
          await cdp.connect();
          const res = await cdp.send('Network.getAllCookies');
          if (res && res.cookies) cookies = res.cookies;

          // 尝试从浏览器已经渲染的页面中直接提取头像和用户名（零网络开销，不依赖 Node 外网代理）
          try {
            const evalRes = await cdp.send('Runtime.evaluate', {
              expression: `(() => {
                const img = document.querySelector('ytmusic-settings-button img, yt-img-shadow#avatar img, button#avatar-btn img');
                return {
                  name: img ? (img.getAttribute('alt') || '') : '',
                  avatarUrl: img ? (img.src || '') : ''
                };
              })()`,
              returnByValue: true
            });
            if (evalRes && evalRes.result && evalRes.result.value) {
              domProfile = evalRes.result.value;
            }
          } catch (_) {}

          cdp.close();
        } catch (_) {}

        if (cookies && cookies.length > 0) {
          const cookieMap = new Map();
          for (const c of cookies) {
            cookieMap.set(c.name, c.value);
          }

          const hasAuth = (cookieMap.get('SAPISID') || cookieMap.get('__Secure-3PAPISID')) && cookieMap.get('LOGIN_INFO');
          if (hasAuth) {
            const cookieStr = Array.from(cookieMap.entries())
              .map(([k, v]) => `${k}=${v}`)
              .join('; ');

            // 核心凭据齐备，立即判定捕获成功，不再阻塞主循环
            capturedCookie = cookieStr;

            // 优先使用页面 DOM 提取的头像/昵称
            if (domProfile && (domProfile.name || domProfile.avatarUrl)) {
              capturedProfile = {
                name: domProfile.name || 'YouTube 用户',
                id: domProfile.name || 'yt_authenticated',
                avatarUrl: domProfile.avatarUrl || ''
              };
            }

            // 容错尝试 InnerTube account_menu（设置 2s 超时，网络不通时不阻塞退出）
            try {
              const apiProfile = await Promise.race([
                fetchAccountProfile(cookieStr),
                new Promise(r => setTimeout(() => r(null), 2000))
              ]);
              if (apiProfile && apiProfile.name) {
                capturedProfile = apiProfile;
              }
            } catch (_) {}

            break;
          }
        }
      }
    } catch (_) {}

    await new Promise(r => setTimeout(r, 1500));
  }

  if (!capturedCookie) {
    console.error(`\n[!] 等待登录超时 (${options.timeout}s)，未捕获到完整登录凭据。`);
    try { browserProc.kill(); } catch (_) {}
    process.exit(1);
  }

  console.log(`\n======================================================================`);
  console.log(`[+] 恭喜！成功捕获并验证 YouTube Music 核心鉴权 Cookie！`);
  if (capturedProfile && capturedProfile.name) {
    console.log(`[+] 识别到账号: ${capturedProfile.name} (${capturedProfile.id || ''})`);
  }
  console.log(`======================================================================\n`);

  console.log(capturedCookie);
  console.log(`\n----------------------------------------------------------------------`);

  const copied = await copyToClipboard(capturedCookie);
  if (copied) {
    console.log(`[+] 已通过原生 clip 完整复制到系统剪贴板！可以直接在 Lazer 弹窗中按 Ctrl+V 粘贴登录。\n`);
  } else {
    console.log(`[*] 请手动复制上方整段 Cookie 字符串并在 Lazer 插件中粘贴登录。\n`);
  }

  if (!options.skipStorage) {
    const injectedPath = autoInjectToLazerStorage(capturedCookie, capturedProfile);
    if (injectedPath) {
      console.log(`[✓] 成功将最新凭据自动注入 Lazer 本地插件存储！`);
      console.log(`    本地绝对路径: ${injectedPath}`);
      console.log(`    使用推荐:`);
      console.log(`      1. 推荐直接在 Lazer 登录弹窗中按 Ctrl+V 粘贴即可完成登录！`);
      console.log(`      2. 若 Lazer 尚未启动，直接启动 Lazer 即可秒进已登录态！\n`);
    } else {
      console.log(`[*] 未能定位或写入 Lazer 本地存储路径，请手动粘贴 Cookie 登录。\n`);
    }
  } else {
    console.log(`[*] 已指定 -s / --skip-storage 参数，跳过自动写入本地存储。\n`);
  }

  if (options.backup) {
    const backupPath = saveBackupCredentials(capturedCookie, capturedProfile);
    if (backupPath) {
      console.log(`[✓] 成功在脚本同级目录生成凭据备份！`);
      console.log(`    备份绝对路径: ${backupPath}\n`);
    }
  }

  if (options.quitAfterDone) {
    console.log(`[*] 已设置自动退出，正在关闭浏览器窗口...`);
    try { browserProc.kill(); } catch (_) {}
    try { fs.rmSync(userDataDir, { recursive: true, force: true }); } catch (_) {}
  } else {
    console.log(`[*] 浏览器窗口已保留，可继续播放试听。按 Ctrl+C 可退出本脚本。`);
  }
}

if (require.main === module) {
  main().catch(err => {
    console.error('[!] 运行时发生异常:', err);
    process.exit(1);
  });
}

module.exports = {
  detectBrowser,
  resolveLazerStoragePath,
  autoInjectToLazerStorage,
  saveBackupCredentials,
  evaluateCookie
};
