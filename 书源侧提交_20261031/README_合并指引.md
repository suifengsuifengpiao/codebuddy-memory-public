# 合并指引（给引擎侧）

> **这是请你入库的操作单。** 按下面四步做完即可；做完请回执（见主说明第零节）。
>
> 目标库：`z157001/legado-booksource-knowledge`
> 本包路径映射到库内既有结构，可直接复制，无需改格式。

---

## 一、文件映射

| 本包文件 | 库内目标 |
|---|---|
| `cases/站点档案_百草露.md` | `cases/站点档案_百草露.md`（新增） |
| `cases/站点档案_手机小说.md` | `cases/站点档案_手机小说.md`（新增） |
| `cases/站点档案_八叉书库.md` | `cases/站点档案_八叉书库.md`（新增） |
| `references-extra/坑点补遗_N10-N13_20261031.md` | 追加到 `references-extra/pitfalls.md` 末尾（接 N9） |
| `releases/legado-booksource-debug_v1.15.0.skill` | `releases/`（新增，保留 v1.14.10 作回滚点） |
| `samples/百草露小说书源.json` 等 3 份 | `samples/`（新增） |

---

## 二、README.md 需追加的清单行

### 2.1 `cases/` 行尾追加

```
+ 站点档案（百草露/手机小说/八叉书库 3 站，2026-10-31）
```

### 2.2 `samples/` 行

把「7 份」改为「10 份」，追加：`百草露/手机小说/八叉书库`。

### 2.3 `releases/` 行追加

```
④ **`legado-booksource-debug_v1.15.0.skill`** — 技能包（2026-10-31）：
   3.25 `@html` 语义纠偏（删 script/style + 单条 outerHtml）、新增 `all` 指示符、
   `test_parse` 末段 html/all 走真 Jsoup 通道、evals 新增 script 载体 golden。
```

### 2.4 新增「2026-10-31 更新」小节

```markdown
## 2026-10-31 更新

- **技能升级 v1.15.0**：`@html` 语义纠偏（3.25 会先删 script/style 再取 outerHtml，
  与 innerHTML 不同），新增 `all` 指示符；工具链三处同步（JsoupRuleEval.java / test_parse.py /
  evals golden），铁律 27 入库。全套回归 59/59 + equiv 19/19。
- **新增 3 站档案**：百草露（正文脚本 Base64 + 章节分页跨章陷阱）、手机小说（搜索字节闸 +
  限频 cookie）、八叉书库（接口型正文 + Rhino 跨语言两坑）。
- **坑点补遗 N10–N13**：@html 删 script / 分页变量跨章 / 搜索字节闸 / Packages.java 污染。
```

---

## 三、`tools/` 需同步的 2 个文件（**必须**）

```bash
# 从 v1.15.0 技能包取出后覆盖
unzip -o legado-booksource-debug_v1.15.0.skill \
  'legado-booksource-debug/scripts/test_parse.py' \
  'legado-booksource-debug/scripts/jsoup_eval/JsoupRuleEval.java' \
  'legado-booksource-debug/scripts/jsoup_eval/JsoupRuleEval.class' -d /tmp/v115

cp /tmp/v115/legado-booksource-debug/scripts/test_parse.py            tools/
cp /tmp/v115/legado-booksource-debug/scripts/jsoup_eval/JsoupRuleEval.*  tools/jsoup_eval/
```

> `.class` 必须与 `.java` 同批覆盖 —— 本次 `html` 语义变了，只换 `.java` 不重编译 = 本地工具继续返回旧语义，会把这次的坑重新埋回去。

同步后自检：

```bash
cd tools && python3 test_parse.py --self-test          # 期望：html 指示符(单条) / all 指示符 均 PASS
cd .. && python3 evals/run_evals.py                    # 期望 59/59（Node 缺失时 58/58）
```

---

## 四、合并后建议抽验（3 条，约 2 分钟）

```bash
# 1) @html 与 @all 的差异还在（用百草露真实页）
java -cp tools/jsoup_eval/jsoup-1.17.2.jar:tools/jsoup_eval \
  JsoupRuleEval <百草露章节页.html> "id.txt@html"   # 期望：只剩提示语，约 127 字符
java -cp tools/jsoup_eval/jsoup-1.17.2.jar:tools/jsoup_eval \
  JsoupRuleEval <百草露章节页.html> "id.txt@all"    # 期望：含 23 条 script，6000+ 字符

# 2) 分页变量确实跨章（同站第 2 页）
grep -o "hhekgsv='[^']*'" <百草露第2页.html>       # 期望：指向下一章 id，不带 _N

# 3) 新样本能被校验器接受
python3 tools/validate_booksource.py samples/百草露小说书源.json --strict
```

---

## 五、不建议做的事

| 动作 | 原因 |
|---|---|
| 直接用 v1.15.0 覆盖 `tools/` 但**不重编译** `.class` | 源码与字节码不一致，本地会静默回退到错误语义 |
| 把 N11（分页跨章）写成「所有站都别用 nextContentUrl」 | 这是一条**判据**（只跟随 `_N` 形态），不是禁令；`nextContentUrl` 对普通分页站仍是对的 |
| 把 `samples/百草露` 当作「已验证真机」样本 | 分页版尚未真机复验，见主说明第五节 |
