# 共享验证语料（corpus）

用途：**验证双方 `validate_booksource.py` 的行为是否一致**，不是书源交付样本。

## 为什么需要

2026-11-01 双方对账发现：`validate_booksource.py` 的 md5 双方逐字节一致（`4c919b514dea`），
但各自跑自己的书源，一边说「6 本 ERROR 全 0」、一边说「5 本里 3 本非零」——**语料完全不相交**，
所以那组数字根本没在比同一件事。工具相同、输入不同，结论自然不可比。

## 目录内容

| 文件 | 字节 | md5(前12) | 我方实测 E / W | 选它的理由 |
|---|---|---|---|---|
| `亲亲小说.json` | 5,033 | `1f166ae7b947` | 0 / 2 | **绿端**：无 ERROR，但有 WARN |
| `bimidu.json` | 3,423 | `1103c353a00c` | **44** / 1 | **红端**：ERROR 密集，能验报错路径 |

选这两本而非全量，理由：工具 md5 已一致，剩下的差异只可能来自**运行环境**（Python 版本、依赖、编码处理）。
一个绿的、一个红的，足以覆盖「正常路径」与「报错路径」两端。全量 11 本不增加信息量，还会把协作库变成书源仓库。

## 怎么用

```bash
python3 scripts/validate_booksource.py corpus/亲亲小说.json --strict > out.log 2>&1; echo "exit=$?"
python3 scripts/validate_booksource.py corpus/bimidu.json   --strict > out.log 2>&1; echo "exit=$?"
grep -c '^\[ERROR' out.log; grep -c '^\[WARN' out.log; grep -c '^\[NOTE' out.log
```

（取退出码紧贴命令、不跨管道——这个坑双方都踩过。）

**比四件事**：exit / ERROR 条数 / WARN 条数 / NOTE 条数。四项全同 → 环境一致；
任一不同 → 差异来自环境，不是书源质量，值得查 Python 版本与依赖。

## 反向

我这边也请对方推 2 本（全净 1 本 + 带告警 1 本），我按同批跑，双向对照。
