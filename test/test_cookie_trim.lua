-- test/test_cookie_trim.lua
-- 回归测试：Cookie 首尾空白裁剪与 SAPISID 提取
-- 核心约束：Lazer 宿主的 string.match 直接调用 Dart RegExp，Lua 的 %s/%d 字符类
-- 会退化成字面量，`^%s*(.-)%s*$` 恒返回 nil。任何裁剪/提取都必须走字节扫描。

package.path = "?.lua;ytm/?.lua;" .. package.path

local auth_cookie = require("ytm.auth.cookie")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s | Expected: %s, Actual: %s", tostring(msg), tostring(expected), tostring(actual)), 2)
  end
end

print(">>> [Test 1] trim 必须保留完整 Cookie 内容...")

local cookie = "YSC=y4K9LvJtlxE; VISITOR_INFO1_LIVE=MmkinVEbwfQ; SAPISID=2pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT; LOGIN_INFO=AFmmF2sw"

assert_eq(auth_cookie.trim(cookie), cookie, "trim 不应改动无空白 Cookie")
assert_eq(auth_cookie.trim("  " .. cookie .. "  "), cookie, "trim 应裁掉首尾空格")
assert_eq(auth_cookie.trim("\r\n\t" .. cookie .. "\r\n"), cookie, "trim 应裁掉首尾换行与制表符")
assert_eq(auth_cookie.trim("   \r\n\t "), "", "纯空白应裁剪为空串")
assert_eq(auth_cookie.trim(nil), "", "nil 应裁剪为空串")

print(">>> [Test 1] 全部通过！")

print(">>> [Test 2] 占位符语义：trim 后的 -1 仍为 -1...")
assert_eq(auth_cookie.trim("  -1  "), "-1", "占位符必须保留")
assert_eq(auth_cookie.trim(" LOCAL "), "LOCAL", "占位符大小写保留")

print(">>> [Test 2] 全部通过！")

print(">>> [Test 3] 无 host.cookie_field 时的 SAPISID 字节扫描兜底...")
-- 宿主正常路径会走 host.cookie_field；此处故意不提供 host，覆盖兜底实现
assert_eq(host, nil, "测试环境不应存在 host")
assert_eq(auth_cookie.get_sapisid(cookie), "2pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT", "SAPISID 提取")
assert_eq(
  auth_cookie.get_sapisid("a=1; __Secure-3PAPISID=3pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT; b=2"),
  "3pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT",
  "__Secure-3PAPISID 提取"
)
assert_eq(
  auth_cookie.get_sapisid("__Secure-1PAPISID=1pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT"),
  "1pVIBgMQc5fVZP4r/A7mqzxpuBjj1rcxzT",
  "__Secure-1PAPISID 作为开头字段"
)
assert_eq(auth_cookie.get_sapisid("XXSAPISID=nope; SAPISID=good"), "good", "不得命中后缀字段")
assert_eq(auth_cookie.get_sapisid("NOSAPISID=value"), nil, "无边界后缀不得命中")
assert_eq(auth_cookie.get_sapisid("SAPISID="), nil, "空值应返回 nil")
assert_eq(auth_cookie.get_sapisid(""), nil, "空串应返回 nil")
assert_eq(auth_cookie.get_sapisid(nil), nil, "nil 应返回 nil")

print(">>> [Test 3] 全部通过！")

print(">>> [Test 4] Authorization 头格式校验...")
local auth_header = auth_cookie.generate_authorization(cookie, "https://music.youtube.com")
assert_eq(
  string.sub(auth_header, 1, 12),
  "SAPISIDHASH ",
  "Authorization 前缀"
)
local underscore = string.find(auth_header, "_", 1, true)
assert_eq(underscore ~= nil, true, "Authorization 必须带时间戳与哈希分隔符")
assert_eq(string.len(auth_header) > 50, true, "Authorization 长度异常")

print(">>> [Test 4] 全部通过！")

print(">>> [Test 5] 源码守卫：account.lua 不得再使用 %s 模式裁剪...")
local guard_ok = pcall(function()
  local file = assert(io.open("ytm/services/account.lua", "r"))
  local source = file:read("*a")
  file:close()
  if string.find(source, ':match("%^%s*(.-)%s*$")', 1, true) then
    error("account.lua 仍包含 :match(\"^%s*(.-)%s*$\")，会在宿主编译器上吞掉整条 Cookie")
  end
end)
assert_eq(guard_ok, true, "源码守卫")

print(">>> [Test 5] 全部通过！")
print(">>> [OK] test_cookie_trim.lua 测试套件执行完毕，全用例验证成功！")
