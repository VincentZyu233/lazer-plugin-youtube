/**
 * Lazer Plugin Build & Packaging Tool
 * 自动校验 manifest 规范、打包为 ZIP 并生成 SHA-256 哈希值
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');

const ROOT_DIR = path.resolve(__dirname, '..');
const DIST_DIR = path.join(ROOT_DIR, 'dist');
const MANIFEST_PATH = path.join(ROOT_DIR, 'manifest.json');

function log(msg) {
  console.log(`[Build] ${msg}`);
}

function fail(msg) {
  console.error(`[Build Error] ${msg}`);
  process.exit(1);
}

// 1. 校验 manifest.json
if (!fs.existsSync(MANIFEST_PATH)) {
  fail('manifest.json 不存在！');
}

let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf-8'));
} catch (e) {
  fail('manifest.json 不是合法的 JSON 文件：' + e.message);
}

if (!manifest.id || !manifest.name || !manifest.version || !manifest.entry) {
  fail('manifest.json 缺少必要字段 (id, name, version, entry)');
}

const idRegex = /^[a-z][a-z0-9_.-]{2,79}$/;
if (!idRegex.test(manifest.id)) {
  fail(`manifest.id '${manifest.id}' 不符合规范，需匹配正则 ${idRegex}`);
}

const entryPath = path.join(ROOT_DIR, manifest.entry);
if (!fs.existsSync(entryPath)) {
  fail(`入口文件未找到: ${manifest.entry}`);
}

// 2. 收集需要打包的文件列表（保持相对路径）
const filesToPack = [];

function collectFiles(dir, base = '') {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const relPath = path.posix.join(base, entry.name);

    if (entry.isDirectory()) {
      if (entry.name !== 'tools' && entry.name !== 'dist' && entry.name !== '.git' && entry.name !== '.github' && entry.name !== '.venv' && entry.name !== 'test') {
        collectFiles(fullPath, relPath);
      }
    } else {
      if (entry.name === 'manifest.json' || entry.name === 'main.lua' || entry.name === 'README.md' || base.startsWith('yt')) {
        filesToPack.push({ fullPath, relPath });
      }
    }
  }
}

collectFiles(ROOT_DIR);
log(`共收集到 ${filesToPack.length} 个待打包文件:`);
filesToPack.forEach(f => console.log(`  - ${f.relPath}`));

// 3. 原生 Node.js 极简 Zip 打包器（无需 npm 外部依赖）
function createZip(files) {
  const localHeaders = [];
  const centralHeaders = [];
  let offset = 0;

  for (const file of files) {
    const data = fs.readFileSync(file.fullPath);
    const nameBuf = Buffer.from(file.relPath, 'utf8');
    const crc = crc32(data);
    const compressed = zlib.deflateRawSync(data);

    // Local file header (30 bytes + nameLen)
    const localHeader = Buffer.alloc(30 + nameBuf.length);
    localHeader.writeUInt32LE(0x04034b50, 0); // signature
    localHeader.writeUInt16LE(20, 4);         // version needed (2.0)
    localHeader.writeUInt16LE(0, 6);          // flags
    localHeader.writeUInt16LE(8, 8);          // compression method (deflate)
    localHeader.writeUInt16LE(0, 10);         // time
    localHeader.writeUInt16LE(0, 12);         // date
    localHeader.writeUInt32LE(crc, 14);       // crc32
    localHeader.writeUInt32LE(compressed.length, 18); // compressed size
    localHeader.writeUInt32LE(data.length, 22);       // uncompressed size
    localHeader.writeUInt16LE(nameBuf.length, 26);    // filename length
    localHeader.writeUInt16LE(0, 28);                 // extra length
    nameBuf.copy(localHeader, 30);

    localHeaders.push(localHeader, compressed);

    // Central directory header (46 bytes + nameLen)
    const centralHeader = Buffer.alloc(46 + nameBuf.length);
    centralHeader.writeUInt32LE(0x02014b50, 0);
    centralHeader.writeUInt16LE(20, 4);
    centralHeader.writeUInt16LE(20, 6);
    centralHeader.writeUInt16LE(0, 8);
    centralHeader.writeUInt16LE(8, 10);
    centralHeader.writeUInt16LE(0, 12);
    centralHeader.writeUInt16LE(0, 14);
    centralHeader.writeUInt32LE(crc, 16);
    centralHeader.writeUInt32LE(compressed.length, 20);
    centralHeader.writeUInt32LE(data.length, 24);
    centralHeader.writeUInt16LE(nameBuf.length, 28);
    centralHeader.writeUInt16LE(0, 30);
    centralHeader.writeUInt16LE(0, 32);
    centralHeader.writeUInt16LE(0, 34);
    centralHeader.writeUInt16LE(0, 36);
    centralHeader.writeUInt32LE(0, 38);
    centralHeader.writeUInt32LE(offset, 42);
    nameBuf.copy(centralHeader, 46);

    centralHeaders.push(centralHeader);
    offset += localHeader.length + compressed.length;
  }

  const centralDirSize = centralHeaders.reduce((acc, b) => acc + b.length, 0);
  const centralDirOffset = offset;

  // End of central directory record (22 bytes)
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(files.length, 8);
  eocd.writeUInt16LE(files.length, 10);
  eocd.writeUInt32LE(centralDirSize, 12);
  eocd.writeUInt32LE(centralDirOffset, 16);
  eocd.writeUInt16LE(0, 20);

  return Buffer.concat([...localHeaders, ...centralHeaders, eocd]);
}

// CRC32 计算器
function crc32(buf) {
  let crc = 0 ^ (-1);
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ crcTable[(crc ^ buf[i]) & 0xFF];
  }
  return (crc ^ (-1)) >>> 0;
}

const crcTable = [];
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) {
    c = ((c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1));
  }
  crcTable[n] = c;
}

if (!fs.existsSync(DIST_DIR)) {
  fs.mkdirSync(DIST_DIR, { recursive: true });
}

const zipBuffer = createZip(filesToPack);
const outZipPath = path.join(DIST_DIR, `${manifest.id}.zip`);
fs.writeFileSync(outZipPath, zipBuffer);

const sha256 = crypto.createHash('sha256').update(zipBuffer).digest('hex');
log(`打包成功！产物: ${outZipPath} (${zipBuffer.length} bytes)`);
log(`SHA-256 校验码: ${sha256}`);

// 打印供市场源使用的 plugins.json 片段
console.log('\n----------------------------------------');
console.log('【插件市场索引 (plugins.json) 片段配置】:');
console.log(JSON.stringify({
  id: manifest.id,
  name: manifest.name,
  version: manifest.version,
  summary: manifest.description,
  author: manifest.author,
  sha256: sha256,
  platforms: ["windows", "macos", "linux", "android", "ios", "web"],
  minAppVersion: "2.0.0"
}, null, 2));
console.log('----------------------------------------\n');

