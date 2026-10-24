# qinqinxs.cc 书源项目档案（会话续接必读）

> **结论截至 2026-10-23 | 置信度：高（四层盾均实锤）**
> 失效条件：站长换盾/下调防御 → 本档案结论作废，重新探测。
> **检索别名**（grep 不到时搜这些）：亲亲小说、质询页、安全扫描、keynamezzc、盾、反爬、WebView过盾、webJs、X-Requested-With、TLS指纹、验证码、captcha、小说CMS模板

> 新会话开场：先读本文件 + /workspace/亲亲小说_v11.json，再动手。禁止重复索要用户已提供的资料。

## 一、项目结论（2026-10-23 终版）
- **该站四层盾全部实锤：①IP段封禁(海外/云IP被HTTP/2 PROTOCOL_ERROR直断) ②TLS/HTTP2指纹(OkHttp被秒返质询页) ③真实手势交互(质询页unlock只由touchstart/scroll触发,IIFE不自动调用,无isTrusted检查) ④挂起惩罚(WebView带cookie导航被挂起40秒无响应)**
- Legado 书源路线全部到墙：WebView(改不了X-Requested-With/导航被挂起) + OkHttp(改不了TLS指纹,v11全套浏览器头+cookie仍秒返质询页0.395s)
- **最终判断：qinqinxs.cc 在 Legado 无解。留档 v11，待站长换盾。用户想看书→换同模板弱盾站(规则改域名即可复用)**

## 二、用户已提供过的资料（禁止再要！）
1. 首页/搜索页/详情页/正文页完整HTML源码（含正文div.novel-start-text与验证码框）
2. 质询页完整JS（unlock逻辑,见下）
3. 狐猴开发者工具里的完整cookie：keynamezzc=bdc2d347f991bb43d11a81ceb228d39（固定值,非计算）
4. 真实章节URL：https://qinqinxs.cc/html/102/56734.html（书102 章56734）
5. 多轮Legado调试日志与HTML预览截图（v5-v11）

## 三、质询页JS全貌（已解析,勿再推断）
```js
(function(){
  var v=false;
  function unlock(){
    if(v)return;
    if(navigator.webdriver || navigator.maxTouchPoints < 2){
      if(!/win|mac/i.test(navigator.platform.toLowerCase())){/*放行老年机*/}
      else{document.getElementById('t').innerHTML="环境异常：禁止模拟器";return;}
    }
    v=true;
    document.cookie='keynamezzc=bdc2d347f991bb43d11a81ceb228d39;path=/;max-age=86400;SameSite=Lax';
    setTimeout(function(){location.replace(location.href);},100);
  }
  window.addEventListener('touchstart',unlock);
  window.addEventListener('scroll',unlock);
})();
```
要点：unlock无isTrusted检查(我曾在推断中错判,实锤没有)；只绑事件,无自动调用。

## 四、Legado 机制实锤（来自APK反编译,通用知识）
- webJs返回值=StrResponse.body(unescapeJson+去引号);返回null/"null"时每秒重试最多30次,之后抛js执行超时;整个WebView抓取60秒协程超时
- WebView加载器io.legado.app.help.http.l:JS开/DOM storage开/屏蔽网络图片;e.java每次onPageFinished都removeCallbacks+postDelayed(webWait)
- cookie流转:WebView页面完成→CookieStore.setCookie;之后OkHttp请求前AnalyzeUrl.setCookie()合并jar与header(header优先级更高)
- 本APK中详情/目录/正文的useWebView参数hardcode false,URL options的webView对它们无效;规则内可用@js:java.webView(url,null,js)兜底
- 站点URL结构:/index.php?a=search&keyword= | /book/ID.html(目录内嵌#chapter-list) | /html/书ID/章ID.html(正文div.novel-start-text,有/captcha.php图片验证码) | /list/1-8.html分类 | /rank/allvisit.html排行

## 五、版本史(失败原因)
v5 webJs返回true→body="true"全空; v6 同步XHR重写→XHR秒返质询页; v8 dispatchEvent触发unlock→导航被挂起40s超时; v9 sessionStorage节流→该WebView抛异常中断; v10 window._lc闸门+location.replace→导航仍被挂起; v11 弃WebView纯普通请求+全套浏览器头→0.395s秒返质询页。均已验证到墙。

## 六、协作纪律(用户明确要求)
- 每轮动手前先盘库存:已有什么源码/实测/已证伪假设,再决定要什么
- 用户只读中文;重视效率,动手前先盘库存(已有什么源码/实测/已证伪假设),避免重复性验证
