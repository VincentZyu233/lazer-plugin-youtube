#!/usr/bin/env node
/**
 * Lazer YouTube Music Cookie 自动抓取工具
 * 
 * 功能：
 * 1. 自动寻找系统内置的 Chrome / Edge / Brave / Chromium 浏览器（支持 Win / Mac / Linux）；
 * 2. 也支持通过 -p / --browser-path 指定自定义浏览器路径；
 * 3. 启动隔离的临时浏览器窗口打开 music.youtube.com，用户手动完成 Google 账号登录；
 * 4. 通过 CDP 协议自动轮询检测登录态，获取完整 Cookie 并高亮打印到控制台，自动复制到剪贴板。
 * 
 * 依赖：Node.js >= 20.0 (纯原生标准库，0 第三方 npm 依赖)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const http = require('http');
const { spawn, exec } = require('child_process');

// 命令行参数解析
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    browserPath: null,
    port: 0,
    url: 'https://music.youtube.com',
    timeout: 300, // 5 分钟超时
    help: false
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-p' || arg === '--browser-path') {
      options.browserPath = args[++i];
    } else if (arg === '--port') {
      options.port = parseInt(args[++i], 10);
    } else if (arg === '--url') {
      options.url = args[++i];
    } else if (arg === '--timeout') {
      options.timeout = parseInt(args[++i], 10);
    } else if (arg === '-h' || arg === '--help') {
      options.help = true;
    }
  }
  return options;
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
      server.listen(0, '127.0.0.1', () => {
        const port = server.address().port;
        server.close(() => resolve(port));
      });
    });
  });
}

// 跨平台预设浏览器路径列表
function getCandidateBrowserPaths() {
  const platform = process.platform;
  const candidates = [];

  if (platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA || '';
    const progFiles = process.env.ProgramFiles || 'C:\\Program Files';
    const progFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';

    candidates.push(
      // Microsoft Edge
      path.join(progFilesX86, 'Microsoft\\Edge\\Application\\msedge.exe'),
      path.join(progFiles, 'Microsoft\\Edge\\Application\\msedge.exe'),
      path.join(localAppData, 'Microsoft\\Edge\\Application\\msedge.exe'),
      // Google Chrome
      path.join(progFiles, 'Google\\Chrome\\Application\\chrome.exe'),
      path.join(progFilesX86, 'Google\\Chrome\\Application\\chrome.exe'),
      path.join(localAppData, 'Google\\Chrome\\Application\\chrome.exe'),
      // Brave
      path.join(progFiles, 'BraveSoftware\\Brave-Browser\\Application\\brave.exe'),
      path.join(progFilesX86, 'BraveSoftware\\Brave-Browser\\Application\\brave.exe'),
      path.join(localAppData, 'BraveSoftware\\Brave-Browser\\Application\\brave.exe'),
      // Chromium
      path.join(progFiles, 'Chromium\\Application\\chrome.exe'),
      path.join(localAppData, 'Chromium\\Application\\chrome.exe')
    );
  } else if (platform === 'darwin') {
    candidates.push(
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
      '/Applications/Chromium.app/Contents/MacOS/Chromium',
      '/Applications/Vivaldi.app/Contents/MacOS/Vivaldi'
    );
  } else if (platform === 'linux') {
    candidates.push(
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/microsoft-edge',
      '/usr/bin/microsoft-edge-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/snap/bin/chromium',
      '/usr/bin/brave-browser',
      '/snap/bin/brave'
    );
  }

  return candidates;
}

// 自动探测可用浏览器
function resolveBrowser(customPath) {
  if (customPath) {
    if (fs.existsSync(customPath)) {
      return customPath;
    }
    throw new Error(`指定的浏览器路径不存在: ${customPath}`);
  }

  const candidates = getCandidateBrowserPaths();
  for (const p of candidates) {
    if (p && fs.existsSync(p)) {
      return p;
    }
  }

  throw new Error(
    '未在常用路径中找到已安装的 Chrome / Edge / Brave 浏览器。\n' +
    '请使用 -p 或 --browser-path 参数手动指定浏览器可执行文件路径。\n' +
    '示例: node tools/get_cookie.js -p "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"'
  );
}

// 尝试将内容复制到系统剪贴板
function copyToClipboard(text) {
  const platform = process.platform;
  try {
    if (platform === 'win32') {
      const proc = spawn('powershell', ['-NoProfile', '-Command', '$input | Set-Clipboard'], { stdio: ['pipe', 'ignore', 'ignore'] });
      proc.stdin.write(text);
      proc.stdin.end();
      return true;
    } else if (platform === 'darwin') {
      const proc = spawn('pbcopy', [], { stdio: ['pipe', 'ignore', 'ignore'] });
      proc.stdin.write(text);
      proc.stdin.end();
      return true;
    } else if (platform === 'linux') {
      exec('which xclip || which xsel', (err, stdout) => {
        if (!err && stdout.includes('xclip')) {
          const proc = spawn('xclip', ['-selection', 'clipboard'], { stdio: ['pipe', 'ignore', 'ignore'] });
          proc.stdin.write(text);
          proc.stdin.end();
        } else if (!err && stdout.includes('xsel')) {
          const proc = spawn('xsel', ['-b'], { stdio: ['pipe', 'ignore', 'ignore'] });
          proc.stdin.write(text);
          proc.stdin.end();
        }
      });
      return true;
    }
  } catch (_) {
    // 复制失败不影响终端打印
  }
  return false;
}

// HTTP JSON 请求封装
function fetchJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

// 主流程
async function main() {
  const options = parseArgs();
  if (options.help) {
    console.log(`
Lazer YouTube Music Cookie 抓取工具

用法:
  node tools/get_cookie.js [选项]

选项:
  -p, --browser-path <path>   指定浏览器可执行文件路径 (Chrome/Edge/Brave/Chromium)
  --port <port>               指定 CDP 远程调试端口 (默认自动分配空闲端口，如 9222)
  --url <url>                 指定打开的登录页面 (默认: https://music.youtube.com)
  --timeout <seconds>         登录等待超时时间 (默认: 300 秒)
  -h, --help                  显示帮助信息
`);
    process.exit(0);
  }

  console.log('================================================================');
  console.log('       Lazer YouTube Music 登录与 Cookie 自动抓取工具           ');
  console.log('================================================================\n');

  const browserPath = resolveBrowser(options.browserPath);
  console.log(`[1/4] 找到可用浏览器: ${browserPath}`);

  const port = options.port || await findFreePort(9222);
  console.log(`[2/4] 分配调试端口: 127.0.0.1:${port}`);

  const tempDir = path.join(os.tmpdir(), `lazer_yt_profile_${Date.now()}`);
  fs.mkdirSync(tempDir, { recursive: true });

  const browserArgs = [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${tempDir}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-blink-features=AutomationControlled', // 防止 Google 拦截自动化环境
    options.url
  ];

  console.log('[3/4] 正在拉起独立的浏览器窗口，请在弹出的网页中登录 Google 账号…');
  const browserProc = spawn(browserPath, browserArgs, {
    detached: true,
    stdio: 'ignore'
  });

  let cleanedUp = false;
  function cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    try {
      if (browserProc && !browserProc.killed) {
        browserProc.kill();
      }
    } catch (_) {}
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (_) {}
  }

  process.on('SIGINT', () => {
    console.log('\n\n检测到用户中断，正在退出并清理临时会话…');
    cleanup();
    process.exit(0);
  });

  process.on('exit', cleanup);

  // 1. 等待 CDP 端口就绪
  let wsUrl = null;
  const startWait = Date.now();
  while (Date.now() - startWait < 15000) {
    try {
      const targets = await fetchJson(`http://127.0.0.1:${port}/json`);
      if (Array.isArray(targets) && targets.length > 0) {
        const page = targets.find(t => t.type === 'page') || targets[0];
        if (page && page.webSocketDebuggerUrl) {
          wsUrl = page.webSocketDebuggerUrl;
          break;
        }
      }
    } catch (_) {}
    await new Promise(r => setTimeout(r, 600));
  }

  if (!wsUrl) {
    cleanup();
    console.error('❌ 连接浏览器调试端口超时，请重试或更换浏览器。');
    process.exit(1);
  }

  // 2. 建立 WebSocket CDP 监听
  console.log('[4/4] 正在监听登录状态，请在浏览器中完成登录…\n');

  if (typeof WebSocket === 'undefined') {
    cleanup();
    console.error('❌ 当前 Node.js 版本不支持原生 WebSocket，请使用 Node.js >= 20 或运行 python tools/get_cookie.py');
    process.exit(1);
  }

  const ws = new WebSocket(wsUrl);
  let reqId = 1;
  let pollTimer = null;
  let resolvedCookie = null;

  await new Promise((resolveWs, rejectWs) => {
    ws.onopen = () => {
      // 开启 Network 域
      ws.send(JSON.stringify({ id: reqId++, method: 'Network.enable' }));
      resolveWs();
    };
    ws.onerror = rejectWs;
  });

  const startTime = Date.now();
  const timeoutMs = options.timeout * 1000;

  // 定时发送 Network.getCookies
  const checkCookies = () => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({
        id: reqId++,
        method: 'Network.getCookies',
        params: {
          urls: [
            'https://music.youtube.com',
            'https://youtube.com',
            'https://accounts.google.com',
            'https://google.com'
          ]
        }
      }));
    }
  };

  const cookiePromise = new Promise((resolve) => {
    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.result && Array.isArray(msg.result.cookies)) {
          const cookies = msg.result.cookies;
          const cookieMap = new Map();
          for (const c of cookies) {
            cookieMap.set(c.name, c.value);
          }

          // 核心凭据检测
          const hasSapisid = cookieMap.has('SAPISID') || cookieMap.has('__Secure-3PAPISID') || cookieMap.has('__Secure-1PAPISID');
          const hasSid = cookieMap.has('SID') || cookieMap.has('__Secure-3PSID') || cookieMap.has('__Secure-1PSID');
          const hasHsid = cookieMap.has('HSID') || cookieMap.has('SSID');

          if (hasSapisid && hasSid && hasHsid) {
            // 组装格式化 Cookie 字符串
            const cookiePairs = [];
            for (const [k, v] of cookieMap.entries()) {
              cookiePairs.push(`${k}=${v}`);
            }
            resolvedCookie = cookiePairs.join('; ');
            resolve(resolvedCookie);
          }
        }
      } catch (_) {}
    };

    pollTimer = setInterval(() => {
      if (Date.now() - startTime > timeoutMs) {
        clearInterval(pollTimer);
        resolve(null);
        return;
      }
      process.stdout.write('⏳ 等待登录授权中… (可在浏览器中输入账号密码或扫码)\r');
      checkCookies();
    }, 1500);
  });

  const cookieResult = await cookiePromise;
  clearInterval(pollTimer);
  try { ws.close(); } catch (_) {}

  // 登录完成或超时处理
  cleanup();

  if (!cookieResult) {
    console.log('\n❌ 登录超时，未检测到完整的账号 Cookie。请重新运行重试。');
    process.exit(1);
  }

  const copied = copyToClipboard(cookieResult);

  console.log('\n');
  console.log('================================================================================');
  console.log('🎉 恭喜！YouTube Music 登录凭据抓取成功！');
  console.log('================================================================================\n');
  console.log('【Cookie 字符串】：');
  console.log('--------------------------------------------------------------------------------');
  console.log(cookieResult);
  console.log('--------------------------------------------------------------------------------\n');
  if (copied) {
    console.log('✅ 提示：上方 Cookie 字符串已自动复制到您的系统剪贴板！');
  } else {
    console.log('💡 提示：请完整选中并复制上方虚线框内的 Cookie 字符串。');
  }
  console.log('👉 下一步：打开 Lazer 客户端 -> 点击「登录」-> 选择 YouTube Music -> 粘贴并点击登录即可！\n');
  console.log('================================================================================\n');
  process.exit(0);
}

main().catch(err => {
  console.error('\n❌ 发生异常:', err.message || err);
  process.exit(1);
});
