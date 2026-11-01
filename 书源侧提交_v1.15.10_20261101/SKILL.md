---
name: legado-booksource-debug
description: 为开源阅读(Legado/阅读)3.0 App 编写、校验、调试书源 JSON。触发：写/修书源；搜索/详情/目录/正文/发现(探索)规则解析失败取空；配 header/charset/正文净化；判断站点静态还是动态；站点被 CF/JS 挑战/验证墙/限流/字体反爬拦；webViewDelayTime 不生效(只认 webWait)。核心能力：先取证真实响应(带/不带 cookie)再改规则；XPath/CSS/JSOUP默认@链式/Regex/JSONPath/JS 五路径；字段校验+铁律检测；webView 站 Playwright 实测；无电脑用诊断探针书源。不含：非 Legado 平台、App 使用教学、通用爬虫反爬工程。
version: 1.15.10
agent_created: true
---

# 开源阅读(Legado)3.0 书源工坊

## Overview

生成健壮可维护的 Legado 书源 JSON，跑通「先取证 → 分析 → 生成 → 验证 → 调试」闭环。

**边界**：只做 Legado 书源（JSON 规则）的编写与调试；不做 App 使用教学、不做非 Legado 平台。

## 🔴 版本锁定：以用户提供的 3.25 反编译为唯一真相源，禁止下载官方源码

- **目标 App 版本 = legado 3.25（用户提供的反编译）**。所有字段名、执行时序、API 语义、cookie 行为的判断，**一律以用户反编译为准**，不得另下官方/其他版本源码来"对照"。
- **绝不下载官方源码**：用户已明确——"你给的 3.25 我破译了，干嘛还下官方"。官方 Kotlin 仓库已删除（含曾误塞进技能包的 `leg/` 整套官方仓库），不要再 `git clone` / 下载 legado 仓库。找不到答案时从用户给的反编译里挖，而不是去下官方。
- **版本切换由你主动告知**：你换版本会主动说；在此之前**本技能一律按 3.25 处理，不引入任何"官方版/兼容写法/双写"**。不假设、不引用其他任何 Legado 构建。

## 🔴 URL 行内选项：字段名写错会被静默忽略

书源里的 `,{...}` 行内选项字段名以 **3.25 反编译版**为准（详见 `references/field-availability.md`）：

- **legado 3.25 反编译版** `UrlOption` 全字段（实证）：`method` `charset` `headers` `body` `origin` `retry` `type`
  `webView` **`webWait`** `webJs` `js` `serverID`（**无** `webViewDelayTime` / `bodyJs` / `dnsIp`）。
- `webViewDelayTime` 在 3.25 里**不是合法字段**：Gson 会静默丢弃它，写了不报错也不生效，还容易让人误以为等待已设置。3.25 的等待字段**只有 `webWait`**。

**等待字段只认 `webWait`（3.25）**：Gson 不拒绝未知字段，写错名字**不报错也不生效**，等待时间退回默认节奏——
3.25 的 `webWait` 默认约 1000ms（见 `realcheck.py` 的 `RETRY_INTERVALS`）。
表现为「明明给了 8000 还是取空」。`webJs` 一旦存在，等待只剩约 100ms 基础延迟，此时必须显式给 `webWait`。

> `validate_booksource.py` 与 `webview_probe.py` 拦截这类静默失效；`realcheck.py` 还会逐一核对每个行内选项的字段名是否被 3.25 认识，不匹配即返回非零退出码。

## 🔴 最高优先级：先取证，再改规则

遇到任何"解析失败"，先回答**真实请求到底拿到了什么**——**带 cookie / 不带 cookie 各抓一次正文页对比**，再动手改规则：

- 不带 cookie 就被挖空 → **cookie / CF 问题**（`enabledCookieJar:true` + 先过一次 CF 落库），**不是** JS 渲染
- 直连就有明文、只是规则没命中 → **修规则**，别上 WebView
- 只有浏览器渲染后 DOM 里才有正文 → **真 JS 渲染**，才上 `chapterUrl` 内联 `webView:true` + `webWait>=8000`

> 完整决策树、本地验证的边界、反编译实证铁律见 [references/pitfalls.md](references/pitfalls.md)。

## 🔴 站点侧 JS 签名 / 动态参数（sign、_ts、nonce）：别抽常量，别急着逆算法

搜索/列表请求里带 `sign`、`_ts`、`nonce` 且值来自**页内联 JS 现算**时，按三级路线评估，
最忌一上来就逆向算法把密钥写死——**轮换的是整套算法内核，不只是常量**（rrssk 实证：一天内从累加式换成
FNV-1a+xorshift，常量还留着，算式全变）。用户要的是"写完能长期用"，不是"今天能用、明天找我改"。

1. **L0 先证伪**：签名乱填直接发一次。很多站的前端闸（`isTrusted`、DOM 指纹累加）**服务端不校验**，
   本次 `_ad52ca`/`_b13bf3` 两道闸实测纯绕过照样 200。**别因为看见 `isTrusted` 就断言"Legado 不可能"。**
2. **L1 首选 eval 官方 JS**：把站点自己的 signJs 拉回来在 Rhino 里 `eval`，调它自己的签名函数。算法由它提供，
   换内核也不怕。定位函数按"有 `f` 属性且是函数"去捡，别写死下标。⚠️ eval 第三方脚本能调 `java.*`，介意就退 L2。
3. **L2 让浏览器自己算**：`ajax` 选项 `webView`+`webJs`+`webWait` / `java.startBrowserAwait(url, title)`（**只有两个参数**），
   加载目标页让它自己签名提交，`webJs` 只捞结果 HTML（`return null` 表未就绪）。
   **未真机验证**，但遇到"每天换内核"的站优先试这条，它是唯一能从军备竞赛里退出的路。
4. **L3 本地复刻算法**是最后手段，且默认活不过下次改版。

**已自动化的那一条**：签名与请求各取一次 `Date.now()/1000`（跨秒即不一致）在 `validate_booksource.py` 里是 **WARN**（确有场景需要两个时间戳，故不用 ERROR），回归用例 `warn-dual-second-timestamp` 固化。

**本地验证别用 Node 顶替 Rhino**：`js_layer_check.py` 是 V8。签名类 JS 要下 `rhino-1.7.14.jar`
（`java -cp ... org.mozilla.javascript.tools.shell.Main`），并把真响应存 fixture 做 **mock 回放**——
真站会被 IP 限流、`__snc` 一次性，反复打真站得出的结论是错的。细节见
[references/site-patterns.md](references/site-patterns.md)「站点侧 JS 签名 / 动态参数」。

## 🔴 webView 站点必须实测，不要丢给真机

`webView:true` 的站（JS 挑战、客户端解密、Cookie 限流）纯 curl **永远抓不到真实页面**。以前只能一律 SKIP 交真机——于是「按 Cookie 限流」「字段名写错静默失效」这类问题本地一律测不出来，全靠用户真机才发现。

跑 `python3 scripts/realcheck.py <书源.json> [--times 3] [--cold --content-url URL] [--poison]` —— **交付前最后一闸**：
直接从**待交付的书源文件**里读 `searchUrl` 的行内选项（不手写副本，杜绝"测的和交的不是同一份"），
按 `BackstageWebView` 的真实时序实跑：等 **3.25 认识的等待字段 `webWait`** → 按 3.25 的节奏重复
`evaluateJavascript`，**结果判定照抄反编译 c.java 的原始值语义**：JS 返回 `null` → 重试；
**JS 返回 `''` → 原始值 `'""'` 会被判「成功」但 body 为空**（真机「获取成功/html空/0条」的确切成因）→
realcheck 把它标为失败，逼 webJs 用 `return null` 表达"未就绪"（铁律 13）。
默认 UA 用 Legado 真实默认（Windows 桌面 Chrome，`help/config/a.java`），不是 Android WebView UA。
跑完还会自动从搜索结果正则提取真实书籍链接，串起 **发现 → 详情 → 正文** 整条链路并核对正文容器 id。

**靠 cookie 限流的站必加 `--poison`**：主框架文档请求前把限流 cookie 回种进 cookie jar（页内 XHR 不回种），
用于复现「真机 31 次重试全空、40s 超时」，配 `--gap 0` 复现窗口内极速二搜。
**判读要带偏差修正**（1.8.0 更新）：Playwright 无法模拟 `loadUrl` 的 headerMap 注入，也无法模拟真机 webView 的历史累积——
因此它对 `location.replace()` 方案**偏保守**（真机通常更好），对 `location.reload()` 方案**偏乐观**（真机更差）。
污染模式下若结果是 `about:blank`，那是真死局（铁律 15），不是书源写错。

**shumi99 真机事故复盘（书迷楼，1.8.0→1.11.0 逐步实锤，结论以下述为准）**：
- 限流 cookie 是服务端 `Set-Cookie` 下发并带 **30 秒 `Expires`**（不是"永不过期"）；最初建立在错误 URL（`/search.php?q=` 实为 404）上的对照实验已作废。
- **webView 每页加载完都会把 cookie 回写 CookieStore**：以 3.25 反编译 `help/http/e.java`（`extends WebViewClient`，`onPageFinished` 内 `CookieStore.setCookie(CookieManager.getCookie(url))`）为证——这是早先"不回写"误判被推翻后的定论，不要再反向引用。
- `cookieToMap` 不解析过期时间 ⇒ 限流 cookie 在 CookieStore 里**每次都抢先注入**，是反复失败的真正死结。
- 首访 403 壳页（`403`+`<script>location.href=同一URL`+`Set-Cookie`）：**shumi99 实测是「cookie 可复用」型——带 cookie 的普通 HTTP 二访即 200 真内容**，那行跳转只是让浏览器带 cookie 再请求一次，HTTP 层 cookie 复用即可完成（curl 带上首次 `Set-Cookie` 二访也能过）。故这类站**走「普通 HTTP + `enabledCookieJar:true` + `loginCheckJs` 检测壳页并 `java.connect(result.url())` 重取一次」即可过墙（v8 真机实证搜索正常），用 webView 反而卡壳页**；只有「带 cookie 二访仍 403、必须浏览器真跑 JS」的硬 JS 挑战型才只能走 webView（见铁律 15 v8 修正框 + site-patterns.md「首访 403 壳页」）。
- 限流页 `alert();history.go(-1)` 会把页面踢进 **`about:blank` 死局**（cookie/XHR/forward 全失效），表现即「31 次全 null + 40s 超时」或吃满预算后报 60s `TimeoutCancellationException`。这种死局 webView 双清闭环也救不了，正是 v8 改用「普通 HTTP + `loginCheckJs` 重取」过壳页的动因——直连重取天然避开 about:blank，不必赌浏览器跳转。
- **webView 站的破解 = 双清闭环（铁律 16）**：对走 webView 的入口（硬 JS 挑战 / 客户端解密 / 详情·目录页），用 URL 行内选项 **`js` 字段**（`analyzeUrl()` 发请求前执行、绑定含 `cookie`）事前清 CookieStore；webJs 命中锚点删 `document.cookie` 事后清 CookieManager。两层缺一不可，**存量污染自动自愈，用户无需手动清 Cookie**。**边界**：shumi99 的**搜索（普通 HTTP WebBook）链路**在 v8 不用这套——它靠 `loginCheckJs`（HTTP 链路每次请求后执行）检测 403 壳页并 `java.connect` 重取过墙（见下方版本甄别 + 铁律 16 v8 修正框），比 webView 双清更稳更快；双清闭环留给「必须 webView 的入口」用。
- 版本甄别：`loginCheckJs` 在 3.25 **走 webView 的站点（WebBook/WebView 模式内部导航）不触发**，所以"驯兽师"那套 `loginCheckJs` 拦截 403 的写法在 webView 站上会静默失效、不能照搬；但**普通 HTTP 书源链路（含搜索，非 webView）`loginCheckJs` 每次请求返回后都执行、过验证墙/壳页/限流页首选**（见 `field-availability.md` 矩阵与 `pitfalls.md` 铁律 3 / 铁律 16 的 v8 修正框）。v8 真机实证：shumi99 的**搜索（普通 HTTP WebBook）链路**正是靠 `loginCheckJs` 检测 403 壳页并 `java.connect` 重取一次过墙。抄他人书源前先确认：走 webView 的站点别依赖它，普通站点（含纯 HTTP 搜索）放心用。

**realcheck 按 3.25 的等待时序实跑**（详见 `references/field-availability.md`）：

| 版本指纹 | 等待字段真名 | webJs 重试节奏 |
|---|---|---|
| `325`（legado 3.25 反编译版） | `webWait` | **固定 1000ms** |

写错字段名（如写成 `webViewDelayTime`）会被 Gson **静默丢弃**（不报错、不生效、等待退回默认约 1000ms）——这是「本地验证全绿、
真机全空」的头号成因。`realcheck.py` 会**逐一核对每个行内选项的字段名是否被 3.25 认识**，
不匹配即以「严重」列出并返回非零退出码。
`--cold --content-url /数字/数字.html` 额外做**冷启动（无任何 cookie）直取正文页**，
暴露「必须先预热才有内容」的站点。

它能测出：

1. 页面到底能不能渲染出内容（真跑 JS，不猜）；
2. **连续搜索会不会被限流**、限流 cookie 有无被清掉；
3. **webJs 是否会把半截页面当成成功** —— 这是"第一次搜索正常、之后全空"类故障的头号成因，
   无条件 `return outerHTML` 会让第 1 次 evaluate 拿到的 `<head>`（实测 854B）直接通过判定（见铁律 11）；
4. **webJs 的"未就绪"是否用 `return null` 表达** —— `return ''` 会被 Legado 判成「获取成功」但 body 为空
   （evaluateJavascript 原始值语义，见铁律 13），真机表现恰是「获取成功/html空/0条」且无任何报错；
5. 详情/发现/正文是否被搜索的限流 cookie 连带影响。

配套 `python3 scripts/webview_probe.py <书源.json>` 做更细的渲染/限流探测（每次请求用全新 Page、弹窗 dismiss）。

**靠 Cookie 限流的站点**（连续两次请求第二次骤降成极短页 + `alert("搜索间隔")`）用 `webJs` 在**每次成功后顺手清掉限流 cookie**，为下一次留干净状态。这是**维持**干净，不是**事后补救**——请求发出时 cookie 已带上，webJs 补不回来；因此别承诺"完全免疫"。

## 环境检查（先路由）

跑 `check_environment.py --capability <能力> [--network]`（依赖与降级映射见 `skill-dependencies.json`）：
`ready` 直接干活；`partial` 说明受影响功能后继续；`needs_setup` 只装缺失项再重检；
`unavailable` 按 [setup-guide.md](references/setup-guide.md) 降级。字段校验只依赖标准库。

## 核心工作流（骨架；完整步骤与命令见 [references/workflow-detail.md](references/workflow-detail.md)）

0. **环境路由（默认按"只有手机"，不要每次追问）**：默认按**用户只有手机**准备方案（探针书源 / App 内调试界面 / 真机日志判读）；只在用户**主动**说"有电脑且同局域网"时才走调试桥。反复问一个固定答案只会添乱（同 App 版本那条的处理方式）。
   **但要分清两件事**：① **取证用的真实浏览器跑在 Agent 沙盒里**（`realcheck.py` / `webview_probe.py`，Playwright）——**不需要用户的电脑**，用户没电脑照样能取证、能复现限流时序；② 真正依赖用户电脑的**只有** `legado_debug_bridge.py`（要靠手机与电脑同 WiFi 才能连上 App 的 Web 调试服务）——**用户无电脑时不要推这条**，改走 `make_probe_source.py` 探针 + App 调试界面截图/日志。
1. **分析站点**：静态 HTML / 动态 JSON，识别防护（软防护 / cookie 判别 / CF / 字体反爬）。
2. **生成 JSON**：`header`、`charset` 必备；`enabledCookieJar` 按站点定；**净化写进 `content` 的 `<js>` 或规则行内 `##正则##替换`**（`ruleContent.replaceRegex` 在 3.25 **有消费点**：`webBook.w.b` → `AnalyzeRule.getString`；但**必须以 `##` 开头**，裸正则会把正文取空并抛「内容为空」，见 `pitfalls.md` 铁律 5）；**过"明文 cookie"验证墙优先用 `loginCheckJs`**（本 App 实测生效：每次请求后执行、落 cookie 到 CookieJar、下次自动带上，见 `field-availability.md` 矩阵）。
3. **验证命中**：`test_parse.py`（本地样本）+ `verify_booksource.py`（真实抓取闭环）；**webView 站加跑 `webview_probe.py`**（含限流探测）。
4. **调试校验**（两道，缺一不可）：① `validate_booksource.py <书源.json>`（字段完整性 + 铁律 + 行内选项字段名 + JsoupXpath 不兼容语法自动检测）；② **只要书源里有 JS**（`loginCheckJs` / `webJs` / URL 选项 `js` / 规则 `<js>`）就**必须**再跑 `js_layer_check.py --source <书源.json>`（Node `vm` 真跑一遍，抓语法错/运行时异常/未就绪反模式、列表规则 `<js>` 返回数组的类型检查——末段纯 `<js>` 非数组即真机 ClassCastException，链式形态不适用，见 `pitfalls.md` 铁律 26）。前者只看字符串，后者才真执行——**只跑①就报"全绿"是虚假安全感**。要验证人工弹码路径时加 `--code <码>`：输出出现 `弹码=True(java.getVerificationCode)` 才说明弹码分支真被走到（没走到通常是验证码图/captcha-id 的 `indexOf` 定位写错，静态校验抓不到）。
5. **闭环迭代**：未实测通过不得标完成，交付须区分已确认 / 待验证。
6. **反爬逆向**（防护站）：`bypass_cf.py` / `reverse_crypto.py` / `reverse_font.py`。
7. **设备侧诊断**（无电脑时主力）：`make_probe_source.py` 生成探针书源，用户导入后搜任意词、截图回传。

## 输出契约

- 书源 JSON：**数组形态 `[{...}]`**（单对象会 `ImportError`）
- 交付说明：已确认项 / 待验证项 / 已知限制 / 回滚方式
- 结论须附证据（日志 / 命中数 / 响应片段），不臆断根因
- **验证覆盖率必须交代（v1.15.2）**：`validate_booksource.py` 的 `NOTE` 若不为 0，
  说明有字段**本地根本验不到**（`&&` / `||` 并联被吞、`td.0,2` 混合索引、`@js:` / `<js>` 终结）。
  交付说明必须逐条写明「哪些字段 / 用什么手段另验 / 结论如何」，**不得用「test_parse 全绿」一句话概括**。
  只有 `NOTE=0` 才允许写「全部字段本地已验证」。
  设立缘由：这条不是流程洁癖——1.15.1 之后我仍说过「已全部验证」，而当时 `.NOPE_XYZ&&.name` 这种
  半截坏规则在本地照样判命中。**工具说绿不等于验过，得先问它验到了哪。**

## Resources

### references/（按需查阅，不占初始上下文）
- `workflow-detail.md` 流程与命令｜`pitfalls.md` 坑与铁律｜`site-patterns.md` 站点形态解法｜`device-diagnosis.md` 设备侧诊断｜`device-log-cheatsheet.md` 真机调试日志符号与命令速查
- `booksource-schema.md` 字段规范（含 `concurrentRate`/`enabledCookieJar`/`loginCheckJs` 等顶层字段）｜`parse-paths.md` 解析路径与引擎（含 JSOUP 默认 `@` 链式规则与规则标志）｜`field-availability.md` 字段可用性矩阵与版本指纹/死字段｜`legend-js-api.md` Rhino JS API（按 3.25 内置 `jsHelp.md` 对齐）｜`setup-guide.md` 依赖安装与降级
- `apk-3.25-verified-facts.md` APK 实锤（`assets/web/help/md/` 16 篇原文：五个调试入口、规则标志与关键字段、JS API 关键签名、`SourceMBookHelp.md`「校验成功≠能用」、dex 字符串取证）｜`apk-method-inventory.md` **dex 提取的方法补集 + 全量真值表**（对称加解密参数顺序 / 免落地读压缩包 / `cache` 带类型读取 / 发现页 `ExploreKind` 无 group 分组限制 / androguard 复现命令）——只收另两份未覆盖项。**写 `java.xxx()` 前先在此 grep 方法名与描述符**：本表经 dex 反向核校后贴的，人工罗列的方法名已被抓出过不存在项
- `references/evidence/` **结论的物证，引用即归档**：`references/evidence/AnalyzeByJSoup.kt`
  （属性选择器 `~=` 委托 Jsoup 原生 `select()` 的反编译原文；
  `?=` 经同通道实证为幻影——Jsoup 把 `?` 解析进属性名，恒不命中，真机同结果）｜`references/evidence/jsoup-from-apk.jar`（APK 内 Jsoup 纯 JVM 跑不起来的物证：编译能过、加载能过、一解析就 `NoClassDefFoundError: cn/hutool/core/map/f`）。**每个证据都配了 `README.md`，写明它证明什么、怎么自己复核——别只看结论，跑一遍才是证据。****随包约定**：one-off 挖掘产物（jadx 全文、从 APK 抽出的 jar）必须落到这里、**并在文档里以技能内路径引用**；APK 内部类（如 `help/http/e.java`、`t6/i.java`）用户随时可再反编译复现，**不必随包**。裸文件名引用既区分不了这两者、也逃过 `self_audit.py` 第 4 类检查，一律不写。
- `maintenance.md` **维护本技能的自检清单**（改完本技能后必查：机械检查 `self_audit.py`、护栏自测 `--self-test`、语义耦合点表、铁律 22–25）

### scripts/（确定性逻辑，勿用散文重写）
- 常用：`validate_booksource.py` 字段+铁律+选项字段名｜`test_parse.py` 命中验证｜`verify_booksource.py` 真实闭环｜`check_environment.py` 环境路由
- **webView 站必跑**：`realcheck.py` 交付前终审（读交付文件、校验等待字段名 `webWait`、实跑 Legado 时序、串起搜索→发现→详情→正文、`--cold` 冷启动）｜`webview_probe.py` 细粒度渲染与限流探测（playwright 不可用时降级说明）
- 防护站才用：`fetch_page.py`｜`bypass_cf.py`｜`reverse_crypto.py`｜`reverse_font.py`
- 设备侧：`make_probe_source.py` 探针(无电脑)｜`legado_debug_bridge.py` 调试桥(有电脑同局域网)
- **JS 层与自检**：`js_layer_check.py` 书源含 JS 时**必跑**（Node vm 真跑 `webJs`/`js`/`loginCheckJs`；列表 `<js>` 返回数组类型闸门——末段纯 `<js>` 返非数组真机 ClassCastException，链式形态不适用；`--code <码>` 验人工弹码路径）｜`self_audit.py` 技能自身一致性自检（改完本技能必跑，清单见 `references/maintenance.md`）｜`l0_probe.py` 签名站动手逆向前先 L0 证伪（mock 优先，不主动打真站）
- 真 Jsoup 通道引擎：`jsoup_eval/`（`JsoupRuleEval.java`/`.class`/`jar`——`test_parse.py` 命中验证与 `jsoup_realdevice_equiv.py` 真机等价回归的引擎载体；真 Jsoup 通道说明随 `parse-paths.md` 查阅）

### evals/ + samples/
`run_evals.py`+`validate_cases.json` 回归（改检测器后**必跑**；用例随铁律增长，项数不写死）；`sample_booksource.json` 数组形态样例

## 🔴 护栏的验收标准（改 `self_audit.py` / 加检查项前必读）

**`self_audit --self-test` 为什么有七组、为什么不能精简。** 这是 v1.15.3→1.15.9 连修五轮才凑齐的：
每一组对应一种**不同的失效模式**，砍掉任一组就等于承认那类失效模式不存在。

| 类 | 组 | 断言方向 | 它防的是什么 |
|---|---|---|---|
| **A 该叫** | 反例注入、畸形 meta | `exit!=0` 且 [ERROR] 命中 | **漏报**：坏了没人吭声 |
| **B 该闭嘴** | 正例干净树、日期在前的正确展示名 | `exit==0` 且无误报 | **误报**：好的被叫，久了没人信报错 |
| **C 该认怂** | 两段式 display_name、日期格式漏网 | `exit==0` 但**必须**出 [NOTE] | **冒充**：判不了却装作判过了 |
| **D 该照镜子** | 真实基线（本技能当前状态） | 对着真实文件跑 | **沙盒自洽、真实已坏**：虚拟树全绿但本技能早就不健康 |

A 与 B **方向相反**（前者要 `exit!=0`，后者要 `exit==0`），C 既不属于 A 也不属于 B
（既不许叫，也不许沉默）。这就是七组必须**各自独立成一棵沙盒树**的原因——
塞进同一棵树，断言会互相抵消：v1.15.5 的「两段式 NOTE」和 v1.15.6 的「日期在前」两次都是因为
被检测到"混进去会掩盖旧反例"才单独成组的。

两条更精简的表述，记住就够了：

> 只验「该红的红了」→ 发现不了「好的被叫」（v1.15.6 这条误报）；
> 只验「该绿的绿了」→ 发现不了「坏的没叫」（v1.15.3～v1.15.5 那三轮漏报）。

### 加新检查项的三步，缺一不可

1. **先红（证明检查器在尖叫）**：只加断言、不改修复代码，`--self-test` 必须**失败**。
   跳过这步，你不知道自己加的是"能叫的警报"还是"永远静默的空指针"。
2. **后绿（证明修复真的修了）**：改完代码必须全组通过。
3. **因果复现（证明两者之间有因果，不是碰巧）**：**把修复回退**（例如把 v1.15.6 的两级匹配改回
   单级 `v?`），断言一行不动，重跑必须**重新变红**，且只是新组红、老组仍绿。
   第 3 步由引擎侧 v1.15.6 回执 §二 提出并实操：它证明的不是"我们改对了"，
   而是**"改之前这条确实是红的"**——中间没有含糊地带。没有第 3 步，前两步也可能是碰巧。

### 造沙盒数据时的两个坑（都真实发生过）

- **交叉比对的字段必须一起改**：改 `version` 时 `_meta.json` 和 `SKILL.md` 要同步改。
  只改一半（如 `_meta.json` 改成 1.15.6 而 `SKILL.md` 仍是 1.15.7）→ 3b 报「SKILL.md version=1.15.7, _meta.json version=1.15.6 → 两处必须同步」，
  **这条 ERROR 关于 `version` 字段、与 `display_name` 无关**；只有 `display_name` 也写了旧版本号时 3c 才再补一条（实测 `E=2`：3b + 3c 各一）。
  据此去盯 `display_name` 找问题会走弯路——真正要先修的是两处 `version` 没同步。
  （注：3c 文案里的 `version=` 取的是 `SKILL.md` 的版本，不是 `_meta.json` 的；两者不同步时它在指一个 `_meta.json` 里不存在的值。改正文案是「与 SKILL.md version=… 不一致」，v1.15.8 未动代码，留待下次碰 `self_audit.py` 时一并改。）
- **取退出码不得跨管道**：`python3 x.py | grep X; echo $?` 拿到的是 `grep` 的码。
  正确写法：`python3 x.py > out.log 2>&1; ec=$?; cat out.log`。

## 版本记录



- **版本 1.14.4 → 1.14.5**（2026-10-25，进化引擎 A' 修复批）：修正 list-js 闸门与「列表 `<js>` + 纯选择器子规则」检查对**链式形态**的误杀——按 3.25 反编译（`AnalyzeRule.getElements`/`splitSourceRule`/`AnalyzeByJSoup.parse`）确立两形态契约：末段纯 `<js>` 时 JS 返回值直接作列表元素被强转 `List`（非数组即 CCE，mowan v1 实证），链式形态 `<js>...</js>选择器` 时 JS 返串经 `Jsoup.parse` 成 DOM 供尾段求值、数组契约不适用（58书屋在售源实证）。三处改动：`js_layer_check.py` 加 `_is_pure_js_terminal` carve-out + explore 字符串化 `ruleExplore` 二级解析；`validate_booksource.py` #12 同款 carve-out + `get_explore_regions` 覆盖结构(a)；evals 补链式 good 标本与 explore bad 标本、bad 标本升级为 v2 忠实形态（HTML 字符串数组）。在售书源全集冒烟与 v1.14.4 基线逐文件一致，零假阳零回归。

- **版本 1.14.5 → 1.14.6**（2026-10-25，进化引擎批次 B）：坑库沉淀 + 旧 schema 覆盖补齐。① `pitfalls.md` 新增铁律 26「真机才暴露的列表规则三坑」：末段纯 `<js>` 必须返回数组（CCE 实证，含两形态契约边界）、真机不解析字符串元素为 HTML（JsoupRuleEval 排除法证据链）、混合聚合站 type 过滤（novel/video/audio/image 实测分布），顺带确立「业务限额码 ≠ 频控」判读原则（40306 message 明示登录限额，解法 enabledCookieJar + App 内登录）；② `site-patterns.md` 新增「混合聚合站（SPA+CDN，四 type）」站点样本（四端点 API 取证表、source+book_id 标识体系、搜索层 type=novel 过滤）；③ `validate_booksource.py` #12 搜索区口径统一：`_list_js_regions()` 改调 `_get_search_region()`，覆盖旧 schema（规则内嵌字符串化 searchUrl 对象）——验证师 A' 复证实证的漏报通道，P2 修复；evals 新增对应 bad 标本（48 用例）；④ SKILL.md 核心工作流 js_layer_check 描述增补列表数组类型检查。

- **版本 1.14.6 → 1.14.7**（2026-10-25，进化引擎批次 C 决策项 R1+R2）：
  订正 `?=` 幻影操作符的传播性错误陈述。实证结论（jsoup-1.17.2 可复跑 + 反编译透传证据）：
  `~=` 是 Jsoup **正则匹配**（无词边界——`foobar` 也中 `~=foo`；`|` 为正则 OR；`.` 为任意字符）；
  **`?=` 不是操作符**——Jsoup 将 `?` 解析进属性名，`[attr?=val]` 恒不命中、不报错，真机透传同结果，写了等于静默取空。
  ① R1：订正全部将二者混为一谈的并称措辞（原陈述合称「Jsoup 原生操作符/扩展属性选择器」；覆盖 test_parse.py 注释与输出文案、parse-paths.md、evidence/README.md、setup-guide.md、workflow-detail.md、SKILL.md、equiv 注释，复审阶段补订审计漏列的站外载体 `JsoupRuleEval.java` ×2、`skill-dependencies.json` ×2），路由正则保留 `\?`（让此类规则走真通道拿到真机一致的恒空，非假装其有语义）；铁律 25 纪律增补：一致性扫描必须覆盖全部文件类型（.java/.json 等站外载体同样会残留，本轮即因此漏网 4 处）；
  ② R2：equiv 新增「幻影操作符 `?=` 恒不命中」值级 golden 用例，把真机行为钉成回归。全套回归 55/55 + self_audit --self-test 通过；铁律 25 同行并称扫描（全文件类型，含 .java/.json）零残留。

- **版本 1.14.7 → 1.14.8**（2026-10-25，专家团审查放行条件修复批）：
  ① P2-1：dex 坐实 `<js>` 求值作用域（classes3.dex + androguard 反汇编，证据链入 `apk-method-inventory.md`「`<js>` 求值作用域」节）——`AnalyzeRule.evalJS` 每次新建 `ScriptBindings` 独立求值，`var`/`function`/IIFE 顶层声明只活在本次调用，**bookList `<js>` 里定义的 helper 对子规则必然不可见**（真机 `ReferenceError: _p is not defined` 取名空）；跨片段共享 helper 的**唯一合法通道是书源 `jsLib` 字段**（`BaseSource$DefaultImpls.getShareScope` 经 `setPrototype` 注入每个 `<js>`）。据此修正：`pitfalls.md` 铁律 26 坑②解法重写（通道 A：helper 放 `jsLib` 共享，官方机制推荐 / 通道 B：子规则内联自含 / 旧文档「bookList 定义 `_p` + 子规则 `<js>_p(result).xxx`」处方作废声明）、`site-patterns.md` 兼容层同款修正、`validate_booksource.py` #12 WARN 文案处方修正；`js_layer_check.py` harness 对齐真机（jsLib prelude 注入 + 子规则 `result_raw` 字符串语义，此前从未建模）；evals 标本 14/15/16 三连钉住（IIFE 引用必 FAIL / jsLib 共享 PASS / 子规则自含 PASS）；`maintenance.md` 语义耦合点表登记「改 harness `<js>` 求值语义前必看 dex 节」。
  ② P2-2：触发枚举补「发现(探索)」（SKILL.md description 与 `workflow-detail.md` 两处对齐）。
  ③ P2-3：`workflow-detail.md` 第四步补 `js_layer_check.py` 必跑说明（书源含 JS 即跑、list-js 返回数组类型闸门与两形态契约、Node 缺失 exit 2 + validate #12 静态 WARN 兜底链）。
  全套回归 55/55 + self_audit 五项及自检 + js_layer self-test 18/18。

- **版本 1.14.8 → 1.14.9**（2026-10-25，专家团审查 P3 全修批）：
  ① P3-10 空输入口径对齐：`validate_booksource.py` 的 `load_source` 对 **0 字节/纯空白文件**报错 exit 2（原先被 JSONL 兜底当成空书源组、exit 0 输出「书源字段完整，符合规范。」——空文件被判合规有误导性，违背本技能「失败不可静默 pass」原则，且与 `js_layer_check.py` 同输入 exit 2 口径相悖）；合法但空的 JSON 数组 `[]` 保持放行（QA 记录在案的合法书源组行为，防误伤）、坏 JSON 既有 exit 2 行为不变（防回归）。`run_evals.py` 增**文件级用例通道**（`file_content` 逐字节写临时文件喂校验器，主断言 `expect_exit_code`）；`validate_cases.json` 补 4 用例（0 字节 / 纯空白 / 坏 JSON / 空数组，正反双向钉住）。
  ② good 标本连坐：`good-list-js-with-js-subrules` 改写为 P2-1 坐实后的合法写法（子规则内联自含 `JSON.parse(result)`，含 try/catch 容错），消除「文档已判废『bookList IIFE 定义 helper』旧写法而 good 标本仍在用」的矛盾；js_layer `--source` 实测该书源 12/12 PASS。
  ③ P3-5：`maintenance.md` 已知缺口表登记 `##`/`@js:` 尾段 carve-out 过宽（漏报方向、真实书源罕见、收紧需 dex 描述符级证据，与「#12 升 ERROR 需 dex 证据」同批处理）；代码未收紧。
  ④ P3-7/P3-9：SKILL.md Resources 的 js_layer_check 描述同步 list-js 数组闸门（末段纯 `<js>` 返非数组真机 CCE、链式形态不适用）；补 `jsoup_eval/` 真 Jsoup 通道引擎载体一行。
  ⑤ P3-8：`maintenance.md` 语义耦合点表登记 `_is_pure_js_terminal` 双副本（`validate_booksource.py` 与 `js_layer_check.py` 逐字同义、独立分发，改前必双扫、改后必同步，当前无漂移）。
  ⑥ 追溯补登（P3-6）：1.14.5 的 about:blank 误报判据收窄为 webJs 语义、1.14.6 的 JsoupRuleEval.class 重编译（修复基线 class 落后源码的隐患）此前的版本记录未点名，此补登。
  ⑦ 口径注明（P3-4）：全套回归 **59/59** = `run_evals.py` 顶层条目口径（52 个 validate 用例 + sample 基线 + 6 个聚合项；聚合项内共 92 个原始用例/断言，全套合计 144；Node 缺失时 js_layer 聚合项 SKIP，为 58/58）。

- **版本 1.14.9 → 1.14.10**（2026-10-26，专家团审查 P1 全修批 + 书源 lint 工具同步）：
  ① skill 自身 21 处 dex 结论纠错：`ruleContent.replaceRegex` 在 3.25 是**有消费点的活字段**（经 `webBook.w.b()` → `AnalyzeRule.getString(ruleStr, 正文)`，mask=4），必须以 `##` 开头（`##正则##替换`）；裸正则被当 JSOUP 规则 → 正文清空 → `ContentEmptyException("内容为空")`。覆盖 SKILL.md 铁律 5/10、诊断表④、`booksource-schema.md` §八、`field-availability.md`、`parse-paths.md`、`workflow-detail.md`、`apk-3.25-verified-facts.md`、`pitfalls.md` 铁律 5/10；`validate_booksource.py` 同步：顶层 `replaceRegex`→WARN、`ruleContent.replaceRegex` 非 `##`→ERROR、`##` 前缀→编译校验段[1]；`subContent`/`callBackJs` 移出 `ruleContent` 合法键集。
  ② 书源 lint 工具（knowledge-repo/tools/lint）batch 修复：P1-1 `java.*` 全量比对 dex 真值清单（书源 136 / 官方文档 51 / RSS-only 2 / 未仿真 17），按 rss_only→ERROR、unemu→WARN、未记载→INFO、清单外→WARN 分级；修复 `_JAVA_CALL_RE` 双重转义 bug（曾致整功能形同虚设）；P1-2 删 `DEAD_FIELDS` 中 replaceRegex 死字段误报、新增 `check_replaceregex_form`（REPLACEREGEX-TOP/FORM/REGEX）；self-test 坏源 8/8、好源 0 ERROR、资产 6/6；7 真实书源 ERROR=0 零新增误报。
  ③ 全套回归 **59/59** + self_audit 五项及自检 + js_layer self-test 18/18 零回归（对比 v1.14.9 基线逐文件一致）。

- **版本 1.14.10 → 1.15.0**（2026-10-31，3.25 真机 `@html` 语义纠偏：正文藏在 `<script>` 里的站点）：
  百草露小说 m.baicaolu.com 真机「正文空」实证（日志 `诊断[html长度=127,base64块=0]`）——站点正文全部放在
  `<script>document.writeln(混淆对象.方法('base64'))</script>`，而 **3.25 的 `@html` 会先 `select("script").remove()`
  再取 outerHtml**（`AnalyzeByJSoup.getResultLast` 反编译原文），等于先把正文删干净，只剩提示语（复现长度 127 字符、与真机日志一字不差）。
  ① 新增铁律 27（`pitfalls.md`）：`@html` ≠ innerHTML、正文载体必须用 `@all`；识别信号、混淆函数名每次请求都变、
  正则须吃到函数名（`/writeln\([^'"]*['"]([A-Za-z0-9+\/=]+)['"]/g`）、一条命令自证（html 127B vs all 6171B）。
  ② `scripts/jsoup_eval/JsoupRuleEval.java` 按真机语义重写取值指示符：`html` = 删 script/style 后**单条** outerHtml；
  新增 `all`（不删，**单条** outerHtml）。此前本地 `html` 返回 innerHTML 且不删 script —— 这正是「本地 6088 字符全绿、
  真机 127 字符全空」的成因。已重编译 `.class`。
  ③ `test_parse.py`：`_jsoup_extract` 同步语义，并把末段 `html`/`all` 路由到真 Jsoup 通道（`_need_jsoup`）；
  自检 `html 指示符` 期望由 50（逐元素）改为 1（单条），新增 `all 指示符` 用例。
  ④ `evals/jsoup_realdevice_equiv.py`：新增 `SCRIPT_CONTENT` 夹具与 4 条 golden（html 单条 / all / html删script空壳 / all保留script），
  旧「正文html」golden 按逐元素 innerHTML 写的期望值同步纠正。
  ⑤ 文档同步：`parse-paths.md` 取值指示符表改写 `html` 条目并新增 `all`；`maintenance.md` 语义耦合点表登记
  「改 JsoupRuleEval 取值指示符须三处同步（.java 重编译 / _jsoup_extract / golden）」。
  全套回归 **59/59** + `jsoup_realdevice_equiv` 19/19 + `test_parse --self-test` 全通过。

- **版本 1.15.0 → 1.15.1**（2026-10-31，来读读小说书源调试中发现）：`test_parse.py` 补齐 Legado 点号/冒号索引与 `tag.` 语法糖。
  背景：原实现只有 `_IDX_RE = \[(\d+)\]`（方括号索引），Legado 书源普遍写的 `span.0` / `span.1:2:4` 不被识别，
  整串交给 bs4 后被当成 CSS 类名，报 `Malformed class selector`——把合法规则误判成写错。
  三处改动（均在 `test_parse.py` 的 bs4 分支）：
  ① 新增 `_strip_dot_index()` / `_apply_dot_index()`：解析段尾 `.N` `:N` 多索引与 `-N` 反向索引，
     并保证 `.book_box`、`div.content`、`a[href]` 这类类选择器不被误伤；
  ② `_jsoup_single()` 的 CSS 兜底处剥离 `tag.` 前缀——`'.book_box tag.span'` 含空格时原逻辑走不到 `tag` 专用分支，
     bs4 把 `tag` 当未知标签名**静默返回 0**（不报错，最难查）；
  ③ 内联取段循环与 `_jsoup_select_elements()` 同步接入上述两点。
  验证：来读读小说详情页 5 条带索引规则由「4 条未命中」变为「5/5 命中」；读书斋/八叉书库/手机小说三本书源回归均 `核心字段全部命中 OK`。
  已知边界：`td.0,2` 这类「点号+逗号混合多索引」未支持（Legado 用 `,` 分隔，本技能暂未覆盖）。
  注：初版曾另建独立模块 `legado_sel.py` 绕过该问题，因与 `test_parse.py` 功能重复且无脚本引用，已于同日删除；逻辑统一收敛到 `test_parse.py`。

- **版本 1.15.1 → 1.15.2**（2026-10-31，同日第二轮）：`validate_booksource.py` 新增 `check_verify_coverage()`——
  把「本地验不到、却会显示通过」的规则显式点出来，不让人拿假通过当验证。
  背景：1.15.1 修完索引后我仍判断失误一次（以为 test_parse 通过＝全验过了）。实测暴露更严重的一类：
  **`&&` / `||` 并联在本地是被"吞掉"而非被拒绝**——
  `'.NOPE_XYZ@text&&.name@text'` 返回 `['剑来']`，前半段根本不存在却判命中。书源写坏一段，本地不会报。
  检测三类（分级按"会不会误伤"定，非按严重度）：
  ① `&&` / `||` 并联 → **NOTE**（合法语法，书源本身未必有错；要拦的是"拿本地结果当已验证"这个动作。
     手机小说已真机通过却含 4 处并联，若判 WARN 会让 `--strict` 无故失败——沿用 v1.14.1 教训「护栏应提示而非命令」）；
  ② 点号+逗号混合索引 `td.0,2` → NOTE，明示「是工具边界，不是书源写错，勿改书源」；
  ③ JS 终结规则（`@js:` / `<js>`）→ NOTE，明示本地不执行 JS，须另用 node 跑才算验证。
  `##` 之后与 `<js>` 之后的内容不参与判断，避免把替换串/JS 里的 `||` 误报。
  验证：来读读小说 `ERROR=0 WARN=0 NOTE=0`（即该书源每条都本地可验）；读书斋/八叉书库/手机小说/百草露/读知阁
  五本回归 `ERROR=0`，NOTE 数量与实际 JS/并联处数一致，无新增 WARN。
  **配套（同版本）**：`SKILL.md`「输出契约」新增一条——`validate` 的 `NOTE` 非 0 时必须在交付说明里逐条交代
  未验字段与另验手段，禁止用「test_parse 全绿」概括。这条替代了原 P2「ReWOO 任务图」方案（裁定全文见书源侧内部台账 2026-10-31「P2 处置裁定」节，该台账不随包）：
  任务图靠自述，NOTE 清单靠工具判断，后者无法被自己糊弄。

- **版本 1.15.2 → 1.15.3**（2026-10-31，第三轮）：`self_audit.py` 新增 `display_name` 版本漂移检查。
  背景（引擎侧 v1.15.2 合并回执往返中发现的**共有缺陷**）：`_meta.json` 的 `version` 已到 1.15.2，
  `display_name` 却仍写「书源工坊 v1.15.0」——**我方与引擎侧两侧都没发现**，
  因为旧检查只比对 `version` 字段，不比对展示名里内含的版本号。
  它不导致功能故障，但技能市场/列表页会把版本号显示错，是"静默不一致"。
  检查实现：从 `display_name` 里正则取 `v?\d+\.\d+\.\d+`，与 SKILL.md 的 `version` 比对；
  展示名不含版本号则跳过（避免误伤）。
  **先红后绿已实测**：加完检查第一时间跑出
  `[ERROR] display_name='书源工坊 v1.15.0' 内含版本 1.15.0, 与 version=1.15.2 不一致`，
  修 `display_name` 为 1.15.3 后才转绿——证明该检查不是空转。
  配套：本轮提交包**必须带 `_meta.json`**（v1.15.2 包漏带，导致接收方自检第一件事就是报版本漂移）。

- **版本 1.15.3 → 1.15.4**（2026-11-01）：`self_audit.py` 止住「数据源在但内容坏 → 自检全绿放行」。
  缺陷由**引擎侧 v1.15.3 合并回执 §三 报出**，我方独立复现确认（见下方三例）。
  现象：`_meta.json` 存在但 JSON 非法时，3b 的 `except Exception: pass` 吞掉解析异常 → `mv` 未赋值、
  3b/3c 两段检查同时消失，**而末尾照样打印「五项检查全部通过」**。
  与之对照：同一情形下把文件整个删掉反而正确报 ERROR —— 第 221 行那条「数据源消失不能静默」
  的规矩只堵了「文件不在」这一半，漏了「文件在、内容坏」。
  性质比 `display_name` 不一致严重：**不是数据错，是护栏停摆且自称正常。**

  ① 修复：两处 `except Exception` 改为 `errors.append(...)`，报「存在但无法解析 → 检查已失去数据源」，
     与既有「文件缺失」文案同族；3b 置 `meta_unreadable` 标志、3c 见标志跳过，避免同一故障报两次。
  ② 防回归：`--self-test` 新增第三组反例「畸形 meta」（`_sandbox_files(dirty, broken_meta=True)`）。
     **必须独立于 dirty 组**：若把 `_meta.json` 改坏并进 dirty，3b 的"值不一致"分支就不执行了，
     会反过来掩盖已有的「版本漂移」反例——补一道防线先把旧防线打瞎，不划算。
  ③ 归属：此缺陷**不是 3c 引入**（v1.15.2 的 3b 就是同一个 `pass`），但 3c 照抄该模式把覆盖面从 1 处变 2 处。

  **先红后绿实测**（两条都做，缺一不可）：
  - 主检查：喂三个毒标本 → 截断 JSON 报错、空文件报错、合法 JSON 缺 version 字段**不误报**；正常树全绿。
  - 新反例：把两处处理改回 `pass` → `--self-test` 输出 `畸形 meta 0/1 → 失败`（且那段同时还印着
    `[OK] 五项检查全部通过`，假绿被当场抓获）；改回来 → `1/1 通过`。
    *注：只把 3b 改回 pass 时反例仍通过——因为 3c 会兜住报错。反例断言的是「数据源损坏必须有人报错」
    这个契约，不区分由哪一处报；这与 v1.15.3 那条「展示名不含版本号则跳过」是同一类取舍：
    **反例盯住契约，不盯实现细节**。*
  回归：`self_audit` 五项通过、`--self-test` 正例 1/1 + 反例 6/6 + 畸形meta 1/1 + 真实基线 4/4、
  `evals 59/59`、5 本已交付书源 `ERROR=0`。

- **版本 1.15.4 → 1.15.5**（2026-11-01）：`self_audit.py` 修「样本形状不合预期 → 静默跳过 → 全绿」。
  缺陷由**引擎侧 v1.15.4 回执 §五 第 6 条**报出（他喂了六种 `display_name` 形态，这条双方原先都没提）。
  现象：3c 的正则写死 `v?(\d+\.\d+\.\d+)`，`书源工坊 v1.15` 匹配不上 → 落进"没写版本号 → 跳过" → 全绿。
  但 `v1.15` 既不是"没写版本"（它明确写了版本），也不是"非标准写法"（大版本对齐很常见），
  它只是**段数不够**。归进"跳过"= 检查器以为自己判过了，实际没判。
  与本文件连修三轮的是同一族：**不是数据错，是检查器对样本形状做了未经声明的假设。**

  ① 正则放宽为 `v?(\d+(?:\.\d+)+)`（两段及以上）；仅当**完全不含版本数字**时才跳过。
  ② 分段判级：恰好三段 → 照旧比对，不一致报 ERROR；段数≠3 → 报 **NOTE**（非阻断）。
     NOTE 的理由沿用 v1.14.1 教训「护栏应提示而非命令」：段数不足可能是有意的写法，判 ERROR 会变狼来了；
     而静默会让它跟"没问题"混在一起。NOTE 是中间唯一不两头得罪的档位。
  ③ **新增 `notices` 通道**（此前 self_audit 只有 `errors` 一档）。`main()` 先在 `[OK]` 之前打印 `[NOTE]`，
     **exit code 不变**。要点：`[OK] 五项检查全部通过` 与 `[NOTE] 判不了` 必须能同时出现且不互相冒充。
  ④ 防回归：`--self-test` 新增第四组「两段式 display_name」，沙盒 `_sandbox_files(..., odd_display=True)`
     注入 `{"version": "1.0.0", "display_name": "书源工坊 v1.0"}`。**独立成组**，不并进 dirty/broken：
     它断言的是 `exit=0 且输出 [NOTE]`，与前两组断言（`exit!=0`）方向相反，混在一起会互相掩盖。

  **先红后绿实测**（顺序做了，不是补记）：
  - 先只加断言、不改代码 → `两段式 display_name: FAIL(静默跳过)`，summary `两段式NOTE 0/1 → 失败`；
    且那段失败输出里同时印着子进程的 `[OK] 五项检查全部通过` —— 静默跳过被当场抓获。
  - 再改代码 → `OK exit=0 且输出 [NOTE]`，summary `1/1`。
  - 六形态回归（`version` 固定 1.15.4）：`v1.15.4` 放行 / `v1.15.0` ERROR / 无版本号 放行 /
    `v1.15.0 (build 2026)` ERROR / `1.15(beta)` **NOTE**（原静默）/ `v1.15` **NOTE**（原静默）。
  已知边界：`v1.15.4.1` 这类四段式也落 NOTE（不猜主次）；含日期式展示名 `2026.11.01` 会被当三段比对，
  属既有行为，本轮未改。

- **版本 1.15.5 → 1.15.6**（2026-11-01）：`self_audit.py` 3c 修**误报**——「日期排在版本前面时，
  对着写对了的展示名报版本不一致」。
  缺陷由**引擎侧 v1.15.5 回执 §四**报出；它比我前几轮修的更伤信任，因为前三轮修的都是**漏报**（该叫没叫），
  这条是**误报**（不该叫却叫）。漏报的后果是问题溜过去，误报的后果是以后看到 ERROR 先怀疑检查器。

  现象：`version=1.15.5`、`display_name="2026.11.01 v1.15.5"` → `[ERROR] 内含版本 2026.11.01`。
  根因不是 `re.search` 本身，而是 `v?` 让前缀**可选**，等价于「版本号 = 展示名里第一个数字串」。

  ① 匹配改**两级**：先 `[vV]\s*(\d+(?:\.\d+)+)`（带前缀的语义上就是版本），找不到才退回裸数字串
     `(\d+(?:\.\d+)+)`（与 v1.15.5 完全一致）。**不新增分支**：纯日期 `2026.11.01` 仍走裸匹配、仍按三段比对。
  ② 顺带把大写 `V` 也纳入前缀匹配（旧版靠裸匹配兜住，能过但语义含糊）。
  ③ 防回归：`--self-test` 新增第五组「日期在前的正确展示名」，沙盒 `_sandbox_files(..., date_first=True)`
     注入 `{"version": "1.0.0", "display_name": "书源工坊 2026.11.01 v1.0.0"}`。断言 `exit=0 且无「版本漂移」`
     —— 与前四组「有缺陷必须叫」方向**相反**，必须独立成组，混进 dirty 会互相抵消。

  **先红后绿实测**（顺序做了，不是补记）：
  - 先只加断言、不改代码 → `日期在前的正确展示名: FAIL(误报)`，summary `日期在前 0/1 → 失败`；
    同屏还印着 `正例 1/1、反例 6/6、畸形meta 1/1、两段式NOTE 1/1` 全绿 —— 老护栏全绿、新缺陷漏网，正是要抓的形态。
  - 再改代码 → `OK exit=0 且无「版本漂移」`，summary `1/1 通过`。
  - 十一形态回归（`version` 固定 1.15.5）：
    `v1.15.5` 0/0 ｜ `2026.11.01 v1.15.5` **0/0（原 ERROR，本版修）** ｜ `v1.15.5 (2026.11.01)` 0/0 ｜
    `V1.15.5` 0/0 ｜ `2026.11.01 v1.15` **NOTE**（两级对两段同样生效）｜ `v1.15` NOTE ｜
    `v1.15.0` ERROR(1.15.0) ｜ `V1.15.0` ERROR(1.15.0) ｜ `2026.11.01` ERROR(2026.11.01 既有边界) ｜
    `2026.11.01 v1.15.0` **ERROR(1.15.0)**（误报修了，漏报没废）｜ `书源工坊` 跳过。
  已知边界未变：纯日期展示名仍按三段比对报 ERROR（无 `v` 前缀时无法与版本区分，故意不猜）；
  `v1.15.4.1` 四段式仍落 NOTE。

- **版本 1.15.6 → 1.15.7**（2026-11-01）：**只改文档**，新增 `## 🔴 护栏的验收标准` 一节。
  不涉任何检查器逻辑、不涉解析链路。起源是引擎侧 v1.15.6 回执 §八 指出：

  > `--self-test` 有七组，方向分两类（该红 / 该绿），但**没有一处文字说"为什么必须两类都有"**。

  缺这一节的实际代价已经付过三次：v1.15.5 和 v1.15.6 加第五、第六组、v1.15.9 加第七组（日期格式漏网）时，都是靠"临时想起来断言方向相反
  不能混"才决定独立成组的，**没有文档可查**。第四次遇到同样的事之前把它写下来。

  ① 七组按**失效模式**分四类：A 该叫（防漏报）／B 该闭嘴（防误报）／C 该认怂（防冒充：判不了必须说判不了）／
     D 该照镜子（防"沙盒自洽、真实已坏"）。A 与 B 断言方向相反，C 不属于任一，故必须各自独立成树。
  ② 加新检查项的三步：先红 → 后绿 → **因果复现**。第 3 步由引擎侧 v1.15.6 回执 §二 提出并实操——
     把修复**回退**成单级 `v?`、断言一行不动，必须重新变红（老组仍绿）。它证明的不是"我们改对了"，
     而是**"改之前那条确实是红的"**。我已用他发布的 `v1.15.6` 包（1,038,287B / `77f53f8b6fae`）复跑，
     输出与他的回执**一字不差**（含 `日期在前 0/1 → 失败` 与同屏的老四组全绿）。
  ③ 补两个已踩过的机械坑：**造测试数据只改一半会测出"环境的红"**（改 `version` 必须同步 `_meta.json`
     与 `SKILL.md`，否则每形态多出一条 ERROR，`exit!=0` 全是假的）；
     **取退出码不得跨管道**（`python3 x.py | grep X; echo $?` 取到的是 `grep` 的）。

  回归：`self_audit` 五项通过、`--self-test` 七组全过、`evals` 用例数不变全通过、同上 6 本书源 `ERROR=0`。
  版本必须随文档改动递增，是因为 `self_audit` 会校验 `SKILL.md` 与 `_meta.json` 的 `version` 一致。

- **版本 1.15.7 → 1.15.8**（2026-11-01）：**只改文档**，修正 `## 🔴 护栏的验收标准` 中一处**归因错误**。
  起源是引擎侧 v1.15.7 回执 §三：我原写「只改一半，`display_name` 检查会多出一条 ERROR」——
  实跑复现（`_meta.json` 改 1.15.6、SKILL.md 保持 1.15.7）确认多出的那条是 **3b「两处版本不同步」**（关于 `version` 字段，与 `display_name` 无关），
  只有 `display_name` 也写了旧版本号时 3c 才再补一条（`E=2` = 3b + 3c 各一）。顺带在文档注明 **3c 报错文案里的 `version=` 取的是 `SKILL.md` 的版本、不是 `_meta.json` 的**（不同步时指一个 `_meta.json` 里不存在的值）；
  改正文案「与 SKILL.md version=… 不一致」属代码改动，v1.15.8 未动 `self_audit.py`，留待下次碰代码时一并改（引擎侧 §七.3）。

  回归：同上，三件套 md5 中 `self_audit.py` 与 v1.15.7 逐字节相同（`0d147f4681ea`）。

- **版本 1.15.8 → 1.15.9**（2026-11-01）：**改代码**，修复 3c 的「日期格式漏网」。
  起源是引擎侧 v1.15.8 回执 §二 实测：展示名只写纯日期时，点分 `2026.11.01` 报 ERROR（被当版本号比对，误报），
  而横/斜线 `2026-11-01`、`2026/11/01` 因裸正则 `(\d+(?:\.\d+)+)` 只认点分 → 主匹配落空 → 掉进「真没写版本号→跳过」→ **静默通过**。
  三种日期格式三种结果，且横线格式是中文场景常用写法，属「判不了却装作判过了」。
  修法（两步，引擎侧给的完整方案）：
  ① 点分纯日期（`首段 4 位年份 1900~2100`）→ NOTE「只含日期、未写版本号」而非 ERROR（修误报）；
  ② 主匹配落空、但含疑似日期 `\d{4}[-/]\d{1,2}[-/]\d{1,2}` → NOTE「疑似日期但分隔符非点分」（修静默漏网）。
  `--self-test` 因此加**第七组「日期格式漏网」**（独立成树，断言方向同第四组 C 类该认怂），见 `## 🔴 护栏的验收标准`。
  先红后绿：先只加断言不改码 → 第七组 `FAIL(静默跳过)`；改码后七组全过。
  边界核对（S5）：兜底正则对 `2026-11-01`/`2026/11/01`/`2026-1-1` 命中、对 `11-11`（无4位年）/`2026年11月01日`（中文）/`v1.15.8`（版本号）跳过、对点分 `2026.11.01` 不重复命中（由主分支处理）。
  年份区间边界（引擎侧 v1.15.9 回执 §3.1）：点分分支仅当首段 4 位年落在 `1900~2100` 才判为日期走 NOTE；区间外（如 `1899.01.01`/`2101.01.01`）退回「按版本号比对」→ ERROR（指该日期串、非真实版本）。这是此前文档未写的隐含边界，属文档表述而非代码缺陷，按 P-9 暂不改代码。
  关键一格：`2026.11.01 v1.15.0`（日期+错版本）→ 仍 `E=1 内含版本 1.15.0`，**放过日期没连带放过真错**。
  采纳引擎侧回执 §一 的锚点格式建议：今后引用 Gitee 文件写 `字节数 / blob <sha>`（如 `7,591B / blob ca15480041a4`），git blob sha 直连仓库对象，比 md5 更硬。

  回归：`self_audit` 五项通过、`--self-test` 七组全过、`evals` 59/59、6 书源 `ERROR=0`、11 形态 + 3 新格全符合预期。

- **版本 1.15.9 → 1.15.10**（2026-11-01）：**只改断言，不改行为**。来源是引擎侧 v1.15.9 回执 §二 实测：v1.15.9 修了日期漏网的两半（点分 NOTE + 横斜线兜底 NOTE），但 `--self-test` 第七组只加了标本 A（横线 `2026-11-01`），**点分标本 B（`2026.11.01`）缺专属断言**——把点分那半单独回退，第七组仍全绿、自检一声不吭，行为已退回 v1.15.8。
  修法（引擎侧给的，不动第八组、不新增行为）：第七组同一组里补标本 B `书源工坊 2026.11.01`，与标本 A 同属 C 类（该认怂/NOTE）、断言方向一致，放一组不互相抵消。
  先红后绿：先只加标本 B 断言、把点分行为临时改 `if False` → 第七组 `FAIL(静默跳过)`、`日期漏网 1/2`；恢复点分 NOTE 后七组 `OK 2/2`、`exit=0`。
  行为零变化（v1.15.9 已对），只是把「防回归的网」补满最后一格——引擎侧原话「不是催你出包，当前发布版行为是对的，只是防回归的网缺一格」。

  回归：`self_audit` 五项通过、`--self-test` 七组全过（第七组 2/2）、`evals` 59/59、6 书源 `ERROR=0`。
