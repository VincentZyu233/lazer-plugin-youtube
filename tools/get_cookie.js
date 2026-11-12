#!/usr/bin/env node
/**
 * Lazer YouTube Music 登录与凭据自动抓取超级工具
 * 
 * 版本号跟随 manifest.json 自动同步。
 * 支持四种灵活的抓取与登录模式：
 *   [1] 浏览器常驻模式 (默认：拉起独立浏览器登录，抓取后保留窗口供边听边对照)
 *   [2] 快速提取模式   (拉起独立浏览器登录，抓取成功后立即自动关闭)
 *   [3] 终端扫码模式   (纯命令行：在终端绘制半字字符二维码，手机扫码授权)
 *   [4] 网页扫码即退   (拉起极简无边框小窗展示高清二维码，扫码成功后自动关闭)
 * 
 * 依赖：Node.js >= 18.0 (纯原生标准库，0 第三方 npm 依赖)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const http = require('http');
const https = require('https');
const readline = require('readline');
const { spawn, exec } = require('child_process');
const { renderANSI, renderSVG } = require('./mini_qr');

// 从 manifest.json 动态读取插件版本号
const MANIFEST = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'manifest.json'), 'utf8'));
const VERSION = MANIFEST.version;

// Google Device Flow 官方开源客户端凭据 (YouTube on TV 官方 Client)
const GOOGLE_CLIENT_ID = '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
const GOOGLE_CLIENT_SECRET = 'SboVhoG9s0rNafixCSGGKXAT';
const GOOGLE_SCOPE = 'https://www.googleapis.com/auth/youtube';

// 解析命令行参数
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    mode: null,          // 1: browser-keep, 2: browser-quit, 3: terminal-qr, 4: web-qr
    browserPath: null,
    port: 0,
    url: 'https://music.youtube.com',
    timeout: 300,        // 秒
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-b' || arg === '--browser') {
      options.mode = 1;
    } else if (arg === '-q' || arg === '--quit') {
      options.mode = 2;
    } else if (arg === '--qr' || arg === '-t' || arg === '--terminal-qr') {
      options.mode = 3;
    } else if (arg === '--qr-web' || arg === '-w' || arg === '--web-qr') {
      options.mode = 4;
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

// 打印帮助信息
function printHelp() {
  console.log(`
================================================================
       Lazer YouTube Music 登录与凭据自动获取工具 (v${VERSION})
================================================================

用法:
  node tools/get_cookie.js [选项]

模式选项:
  (无参数)             显示交互式菜单，输入数字回车即可运行
  -b, --browser        [模式 1] 浏览器常驻模式 (抓取后保留窗口供边听边对照)
  -q, --quit           [模式 2] 快速提取模式   (抓取成功后立即自动关闭浏览器)
  --qr                 [模式 3] 终端扫码模式   (纯命令行：在终端绘制二维码供手机扫码)
  --qr-web             [模式 4] 网页扫码即退   (拉起独立小窗展示高清二维码，扫码后自动关闭)

通用选项:
  -p, --browser-path   指定自定义 Chrome/Edge 浏览器绝对路径
  --timeout <秒>       等待登录超时的秒数 (默认: 300)
  -h, --help           显示此帮助信息
`);
}

// 寻找可用空闲端口
function findFreePort(preferredPort = 9222) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.listen(preferredPort, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
    server.on('error', () => {
      // 首选端口被占用，使用新实例分配随机端口
      const server2 = net.createServer();
      server2.listen(0, '127.0.0.1', () => {
        const port = server2.address().port;
        server2.close(() => resolve(port));
      });
    });
  });
}

// 智能查找系统中常见的浏览器路径
function getCandidateBrowserPaths() {
  const platform = process.platform;
  const candidates = [];

  if (platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA || '';
    const progFiles = process.env.ProgramFiles || 'C:\\Program Files';
    const progFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';

    candidates.push(
      path.join(progFiles, 'Google\\Chrome\\Application\\chrome.exe'),
      path.join(progFilesX86, 'Google\\Chrome\\Application\\chrome.exe'),
      path.join(localAppData, 'Google\\Chrome\\Application\\chrome.exe'),
      path.join(progFiles, 'Microsoft\\Edge\\Application\\msedge.exe'),
      path.join(progFilesX86, 'Microsoft\\Edge\\Application\\msedge.exe'),
      path.join(localAppData, 'Microsoft\\Edge\\Application\\msedge.exe'),
      path.join(progFiles, 'BraveSoftware\\Brave-Browser\\Application\\brave.exe'),
      path.join(localAppData, 'BraveSoftware\\Brave-Browser\\Application\\brave.exe')
    );
  } else if (platform === 'darwin') {
    candidates.push(
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser'
    );
  } else {
    candidates.push(
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/usr/bin/microsoft-edge',
      '/usr/bin/brave-browser'
    );
  }

  for (const p of candidates) {
    if (p && fs.existsSync(p)) return p;
  }
  return null;
}

// 写入系统剪贴板 (0 外部依赖)
function copyToClipboard(text) {
  return new Promise((resolve) => {
    const platform = process.platform;
    let proc;
    if (platform === 'win32') {
      proc = spawn('clip');
    } else if (platform === 'darwin') {
      proc = spawn('pbcopy');
    } else {
      proc = spawn('xclip', ['-selection', 'clipboard']);
      proc.on('error', () => {
        const alt = spawn('wl-copy');
        alt.stdin.end(text);
        alt.on('close', () => resolve(true));
      });
    }

    if (proc) {
      proc.on('error', () => resolve(false));
      proc.stdin.write(text);
      proc.stdin.end();
      proc.on('close', (code) => resolve(code === 0));
    } else {
      resolve(false);
    }
  });
}

// 发起支持 HTTP 代理的 POST 请求
function httpsPost(urlStr, dataStr) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const proxy = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.https_proxy || process.env.http_proxy || 'http://127.0.0.1:7890';
    
    let options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(dataStr)
      }
    };

    if (proxy && proxy.startsWith('http://')) {
      const proxyUrl = new URL(proxy);
      const connectReq = http.request({
        host: proxyUrl.hostname,
        port: proxyUrl.port,
        method: 'CONNECT',
        path: `${url.hostname}:443`
      });

      connectReq.on('connect', (res, socket) => {
        options.socket = socket;
        options.agent = false;
        const httpsReq = https.request(options, (response) => {
          let body = '';
          response.on('data', chunk => body += chunk);
          response.on('end', () => resolve({ status: response.statusCode, body }));
        });
        httpsReq.on('error', reject);
        httpsReq.write(dataStr);
        httpsReq.end();
      });

      connectReq.on('error', () => {
        directRequest();
      });
      connectReq.end();
    } else {
      directRequest();
    }

    function directRequest() {
      const dReq = https.request(options, (response) => {
        let body = '';
        response.on('data', chunk => body += chunk);
        response.on('end', () => resolve({ status: response.statusCode, body }));
      });
      dReq.on('error', reject);
      dReq.write(dataStr);
      dReq.end();
    }
  });
}

// 交互式菜单选择
function promptUserMode() {
  return new Promise((resolve) => {
    console.log(`
================================================================
       Lazer YouTube Music 登录凭据获取工具 (v${VERSION})              
================================================================

请选择登录抓取模式：

  [1] 浏览器常驻模式 (拉起浏览器登录，抓取后保留窗口供边听边对照)
  [2] 快速提取模式   (拉起浏览器登录，抓取成功后立即自动关闭)
  [3] 终端扫码模式   (纯命令行：在终端绘制字符二维码供手机扫码)
  [4] 网页扫码即退   (拉起极简小窗展示高清二维码，扫码成功后自动关闭)
`);

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    rl.question('请输入选项 [1-4] (默认 1): ', (answer) => {
      rl.close();
      const choice = answer.trim();
      if (choice === '2') resolve(2);
      else if (choice === '3') resolve(3);
      else if (choice === '4') resolve(4);
      else resolve(1);
    });
  });
}

// 模式 1 & 模式 2：CDP 浏览器控制
async function runBrowserMode(options, autoQuit = false) {
  const browserPath = options.browserPath || getCandidateBrowserPaths();
  if (!browserPath) {
    console.error('❌ 未检测到系统浏览器，请通过 -p <路径> 手动指定 Chrome/Edge 绝对路径。');
    process.exit(1);
  }

  const port = options.port || await findFreePort(9222);
  const tempProfileDir = path.join(os.tmpdir(), `lazer_yt_profile_${Date.now()}`);
  fs.mkdirSync(tempProfileDir, { recursive: true });

  console.log(`[1/4] 找到可用浏览器: ${browserPath}`);
  console.log(`[2/4] 分配调试端口: 127.0.0.1:${port}`);
  console.log(`[3/4] 正在拉起独立的浏览器窗口，请在弹出的网页中登录 Google 账号…`);

  const browserProcess = spawn(browserPath, [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${tempProfileDir}`,
    '--no-first-run',
    '--no-default-browser-check',
    options.url
  ], { detached: true, stdio: 'ignore' });

  console.log(`[4/4] 正在监听登录状态，请在浏览器中完成登录…\n`);
  console.log(`⏳ 等待登录授权中… (可在浏览器中输入账号密码或扫码)`);

  const startTime = Date.now();
  let cookieFound = false;

  while (Date.now() - startTime < options.timeout * 1000) {
    await new Promise(r => setTimeout(r, 1500));
    try {
      const targetsRes = await httpGet(`http://127.0.0.1:${port}/json`);
      const targets = JSON.parse(targetsRes);
      const ytTarget = targets.find(t => t.url && (t.url.includes('music.youtube.com') || t.url.includes('youtube.com')));
      
      if (!ytTarget || !ytTarget.webSocketDebuggerUrl) continue;

      const cookies = await getCookiesViaCdp(ytTarget.webSocketDebuggerUrl);
      if (!cookies || cookies.length === 0) continue;

      const cookieMap = {};
      cookies.forEach(c => { cookieMap[c.name] = c.value; });

      const hasAuth = (cookieMap['SAPISID'] || cookieMap['__Secure-3PAPISID']) && cookieMap['LOGIN_INFO'];
      if (hasAuth) {
        cookieFound = true;
        const cookieString = Object.entries(cookieMap).map(([k, v]) => `${k}=${v}`).join('; ');

        console.log(`\n================================================================================`);
        console.log(`🎉 恭喜！YouTube Music 登录凭据抓取成功！`);
        console.log(`================================================================================\n`);
        console.log(`【Cookie 字符串】：`);
        console.log(`--------------------------------------------------------------------------------`);
        console.log(cookieString);
        console.log(`--------------------------------------------------------------------------------\n`);

        await copyToClipboard(cookieString);
        console.log(`✅ 提示：上方 Cookie 字符串已自动复制到您的系统剪贴板！`);
        console.log(`👉 下一步：打开 Lazer 客户端 -> 点击「登录」-> 选择 YouTube Music -> 粘贴并点击登录即可！\n`);

        if (autoQuit) {
          console.log(`🚪 正在自动关闭浏览器窗口…`);
          try {
            if (process.platform === 'win32') {
              exec(`taskkill /F /T /PID ${browserProcess.pid}`, { windowsHide: true });
            } else {
              process.kill(-browserProcess.pid, 'SIGTERM');
            }
          } catch (_) {}
          try { fs.rmSync(tempProfileDir, { recursive: true, force: true }); } catch (_) {}
          process.exit(0);
        } else {
          console.log(`🎵 浏览器窗口已为您保留，您可以继续在浏览器中听歌并与 Lazer 进行对照！`);
          console.log(`💡 提示：若希望抓取后自动退出浏览器，可附加 -q 或 --quit 参数。\n`);
          process.exit(0);
        }
      }
    } catch (_) {}
  }

  if (!cookieFound) {
    console.error(`\n❌ 等待超时 (${options.timeout}秒)。未检测到登录完成，请重新运行工具。`);
    try {
      if (process.platform === 'win32') {
        exec(`taskkill /F /T /PID ${browserProcess.pid}`, { windowsHide: true });
      } else {
        process.kill(-browserProcess.pid, 'SIGTERM');
      }
    } catch (_) {}
    process.exit(1);
  }
}

// 模式 3 & 模式 4：Google Device Flow
async function runDeviceFlowMode(mode = 3) {
  console.log(`\n[1/3] 正在向 Google 授权服务请求设备配对码…`);
  const postData = `client_id=${encodeURIComponent(GOOGLE_CLIENT_ID)}&scope=${encodeURIComponent(GOOGLE_SCOPE)}`;

  let deviceCodeRes;
  try {
    const res = await httpsPost('https://oauth2.googleapis.com/device/code', postData);
    deviceCodeRes = JSON.parse(res.body);
  } catch (err) {
    console.error(`❌ 请求 Google 授权失败，请检查网络代理 (127.0.0.1:7890):`, err.message);
    process.exit(1);
  }

  const { device_code, user_code, verification_url, interval = 5, expires_in = 1800 } = deviceCodeRes;
  const qrUrl = `${verification_url}?user_code=${encodeURIComponent(user_code)}`;

  let browserProcess = null;
  let tempHtmlPath = null;

  if (mode === 3) {
    console.log(`[2/3] 请使用手机扫码或浏览器打开下方链接授权：\n`);
    console.log(renderANSI(qrUrl));
    console.log(`  👉 手机快速配对网址: \x1b[36m${qrUrl}\x1b[0m`);
    console.log(`  🔑 您的设备确认码:   \x1b[32m\x1b[1m${user_code}\x1b[0m\n`);
    console.log(`[3/3] ⏳ 正在等待手机端确认授权… (完成后将自动同步)`);
  } else if (mode === 4) {
    console.log(`[2/3] 正在拉起极简高清二维码小窗口…`);
    const svgContent = renderSVG(qrUrl, 4, 280);
    const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>YouTube Music 扫码登录</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #121212;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
      user-select: none;
    }
    .card {
      background: #1e1e1e;
      border: 1px solid #333;
      border-radius: 16px;
      padding: 24px;
      text-align: center;
      box-shadow: 0 8px 32px rgba(0,0,0,0.5);
      width: 100%;
      max-width: 360px;
    }
    .title { font-size: 18px; font-weight: 600; margin-bottom: 6px; color: #fff; }
    .subtitle { font-size: 13px; color: #888; margin-bottom: 18px; }
    .qr-box {
      background: #fff;
      padding: 12px;
      border-radius: 12px;
      display: inline-block;
      margin-bottom: 16px;
    }
    .code-box {
      background: #2a2a2a;
      border: 1px dashed #555;
      padding: 10px 16px;
      border-radius: 8px;
      margin-bottom: 16px;
    }
    .code-title { font-size: 11px; color: #aaa; margin-bottom: 4px; text-transform: uppercase; }
    .code { font-size: 20px; font-family: monospace; font-weight: bold; color: #4ade80; letter-spacing: 2px; }
    .footer { font-size: 12px; color: #666; line-height: 1.5; }
    .status { font-size: 12px; color: #38bdf8; margin-top: 12px; display: flex; align-items: center; justify-content: center; gap: 6px; }
    .spinner {
      width: 10px; height: 10px; border: 2px solid #38bdf8; border-top-color: transparent;
      border-radius: 50%; animation: spin 1s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="card">
    <div class="title">YouTube Music 扫码登录</div>
    <div class="subtitle">请用手机相机或浏览器扫描下方二维码</div>
    <div class="qr-box">${svgContent}</div>
    <div class="code-box">
      <div class="code-title">设备配对码</div>
      <div class="code">${user_code}</div>
    </div>
    <div class="footer">手机确认授权后，此小窗口将自动关闭</div>
    <div class="status"><div class="spinner"></div> 等待手机确认中…</div>
  </div>
</body>
</html>`;

    tempHtmlPath = path.join(os.tmpdir(), `lazer_qr_${Date.now()}.html`);
    fs.writeFileSync(tempHtmlPath, html, 'utf8');

    const browserPath = getCandidateBrowserPaths();
    if (browserPath) {
      browserProcess = spawn(browserPath, [
        `--app=file:///${tempHtmlPath.replace(/\\/g, '/')}`,
        '--window-size=420,580',
        '--window-position=450,200',
        '--no-first-run'
      ], { detached: true, stdio: 'ignore' });
    }

    console.log(`  👉 网页配对网址: \x1b[36m${qrUrl}\x1b[0m`);
    console.log(`  🔑 设备确认码:   \x1b[32m\x1b[1m${user_code}\x1b[0m`);
    console.log(`[3/3] ⏳ 等待手机端扫码并确认授权中… (扫码通过后小窗口将自动关闭)`);
  }

  const pollInterval = Math.max(interval, 4) * 1000;
  const pollStart = Date.now();
  let tokenResult = null;

  while (Date.now() - pollStart < expires_in * 1000) {
    await new Promise(r => setTimeout(r, pollInterval));
    const tokenPayload = `client_id=${encodeURIComponent(GOOGLE_CLIENT_ID)}&client_secret=${encodeURIComponent(GOOGLE_CLIENT_SECRET)}&device_code=${encodeURIComponent(device_code)}&grant_type=urn:ietf:params:oauth:grant-type:device_code`;

    try {
      const res = await httpsPost('https://oauth2.googleapis.com/token', tokenPayload);
      const data = JSON.parse(res.body);

      if (data.access_token) {
        tokenResult = data;
        break;
      } else if (data.error === 'authorization_pending') {
        // 等待中
      } else if (data.error === 'slow_down') {
        await new Promise(r => setTimeout(r, 2000));
      } else if (data.error === 'expired_token') {
        console.error(`\n❌ 授权已过期，请重新运行工具。`);
        cleanup();
        process.exit(1);
      } else {
        console.error(`\n❌ 授权失败: ${data.error_description || data.error}`);
        cleanup();
        process.exit(1);
      }
    } catch (_) {}
  }

  function cleanup() {
    if (browserProcess && browserProcess.pid) {
      try {
        if (process.platform === 'win32') {
          // Windows 上必须用 taskkill 杀掉整个 Chrome 进程树
          exec(`taskkill /F /T /PID ${browserProcess.pid}`, { windowsHide: true });
        } else {
          process.kill(-browserProcess.pid, 'SIGTERM');
        }
      } catch (_) {}
    }
    if (tempHtmlPath) {
      try { fs.unlinkSync(tempHtmlPath); } catch (_) {}
    }
  }

  if (tokenResult) {
    cleanup();
    console.log(`\n================================================================================`);
    console.log(`🎉 恭喜！Google 账号扫码授权成功！`);
    console.log(`================================================================================\n`);
    console.log(`【OAuth 2.0 授权凭据】：`);
    console.log(`--------------------------------------------------------------------------------`);
    console.log(JSON.stringify(tokenResult, null, 2));
    console.log(`--------------------------------------------------------------------------------\n`);

    const tokenStr = `Bearer ${tokenResult.access_token}`;
    await copyToClipboard(tokenStr);

    console.log(`✅ 提示：Access Token 已自动复制到系统剪贴板！`);
    if (mode === 4) {
      console.log(`🚪 二维码弹窗已为您自动关闭！`);
    }
    console.log(`\n👉 提示：若您的 Lazer 正在使用 Cookie 登录模式，推荐使用模式 [1] 或 [2] 抓取完整 Cookie；若使用客户端原生扫码，可在 Lazer 登录弹窗中直接使用扫码！\n`);
    process.exit(0);
  } else {
    cleanup();
    console.error(`\n❌ 等待超时，请重新运行。`);
    process.exit(1);
  }
}

function httpGet(urlStr) {
  return new Promise((resolve, reject) => {
    http.get(urlStr, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

function getCookiesViaCdp(wsUrl) {
  return new Promise((resolve) => {
    const u = new URL(wsUrl);
    const options = {
      port: u.port || 9222,
      host: u.hostname || '127.0.0.1',
      path: u.pathname,
      headers: {
        'Connection': 'Upgrade',
        'Upgrade': 'websocket',
        'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': Buffer.from('lazer-cdp-secret-key').toString('base64')
      }
    };

    const req = http.request(options);
    req.on('upgrade', (res, socket) => {
      socket.on('error', () => {}); // 静默处理 socket 断开
      const msg = JSON.stringify({ id: 1, method: 'Network.getAllCookies' });
      const frame = makeWsTextFrame(msg);
      socket.write(frame);

      let buffer = Buffer.alloc(0);
      socket.on('data', (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        const parsed = parseWsFrame(buffer);
        if (parsed) {
          socket.end();
          try {
            const data = JSON.parse(parsed.payload.toString('utf8'));
            if (data.result && data.result.cookies) {
              resolve(data.result.cookies);
            } else {
              resolve([]);
            }
          } catch (_) {
            resolve([]);
          }
        }
      });
    });
    req.on('error', () => resolve([]));
    req.end();
  });
}

function makeWsTextFrame(dataStr) {
  const payload = Buffer.from(dataStr, 'utf8');
  const len = payload.length;
  let header;
  const mask = Buffer.from([0x12, 0x34, 0x56, 0x78]);

  if (len < 126) {
    header = Buffer.from([0x81, 0x80 | len]);
  } else if (len < 65536) {
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

  const masked = Buffer.alloc(len);
  for (let i = 0; i < len; i++) {
    masked[i] = payload[i] ^ mask[i % 4];
  }
  return Buffer.concat([header, mask, masked]);
}

function parseWsFrame(buffer) {
  if (buffer.length < 2) return null;
  const lenByte = buffer[1] & 0x7F;
  let offset = 2;
  let len = lenByte;

  if (lenByte === 126) {
    if (buffer.length < 4) return null;
    len = buffer.readUInt16BE(2);
    offset = 4;
  } else if (lenByte === 127) {
    if (buffer.length < 10) return null;
    len = Number(buffer.readBigUInt64BE(2));
    offset = 10;
  }

  if (buffer.length < offset + len) return null;
  const payload = buffer.slice(offset, offset + len);
  return { payload };
}

async function main() {
  const options = parseArgs();
  if (options.help) {
    printHelp();
    return;
  }

  let mode = options.mode;
  if (!mode) {
    mode = await promptUserMode();
  }

  if (mode === 1) {
    await runBrowserMode(options, false);
  } else if (mode === 2) {
    await runBrowserMode(options, true);
  } else if (mode === 3) {
    await runDeviceFlowMode(3);
  } else if (mode === 4) {
    await runDeviceFlowMode(4);
  }
}

main().catch(err => {
  console.error('发生错误:', err);
  process.exit(1);
});
