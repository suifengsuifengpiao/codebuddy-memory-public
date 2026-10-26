# 回滚 SOP（ROLLBACK.md）

> 建立：2026-10-27 00:57 ｜ 来源：进化计划 v0.1 P0-3
> 前提：`/workspace` **不是 git 仓库**（实测 `git -C /workspace rev-parse` → fatal），
> 快照是工作区**唯一防线**。

---

## 一、强制前置动作

**任何删除 / 覆盖 / 批量修改之前，必须先建快照。** 无快照不动手。

```bash
TS=$(date +%Y%m%dT%H%M%SZ); D=/workspace/.evo-snapshots/$TS; mkdir -p $D
cd /workspace
tar czf $D/tier0-core.tar.gz --exclude=.git --exclude=releases memory-repo legado-knowledge-repo
tar czf $D/tier1-docs.tar.gz $(ls *.md) evo/
# ↑ 必须含 evo/ 整个目录：本 SOP 自己也在这里面。
#   若不含，工作区全毁时连"怎么回滚"都读不到（A8 保护方案必须自保护）。
tar czf $D/tier2-binaries.tar.gz $(ls *.json *.skill *.zip) user_sources demo
{ echo "# tier3 只登记不打包"; du -sh --exclude=memory-repo --exclude=legado-knowledge-repo /workspace; } > $D/tier3-heavy.list
cd $D && sha256sum tier*.tar.gz tier3-heavy.list > manifest.sha256
```

---

**规则层 / 本 SOP 的实体在 `/workspace/memory-repo/evo/`**（git 纳管，单一权威，A3）。
`/workspace/evo/` 下是**软链**，便于访问——**禁止在 `/workspace/evo/` 下另建实体副本**。
若 `evo/` 整体缺失：从更早快照的 `tier0-core.tar.gz` 中取（`memory-repo/evo/`）。

---

## 二、分层定义

| 层级 | 内容 | 恢复时效 | 打包 |
|---|---|---|---|
| `tier0-core` | 两个 git 仓库工作树（`memory-repo` / `legado-knowledge-repo` 源码，排除 `.git` 与 `releases`） | <2 min | 是 |
| `tier1-docs` | 全部 `*.md`（含 `evo/RULES.md`） | <2 min | 是 |
| `tier2-binaries` | `*.json` / `*.skill` / `*.zip` / `user_sources/` / `demo/` | <2 min | 是 |
| `tier3-heavy` | `apktool.jar` 23.2MB、`legado_app_3.25.apk` 18.8MB、`b2-work/`、`dex-tools-v2.4/`、`jadx_dist/` | 需重下载/重建 | **否**，只登记 |

> **为什么 tier3 不打包**：613M（实测 `du -sh --exclude=memory-repo --exclude=legado-knowledge-repo /workspace`）、均可重建（APK 可重新获取、dex-tools/enjarify 可重新下载、
> B2 jar 可由 APK 经 BUILD.md 重建）。打包不经济，只留清单以便知道要恢复什么。

---

## 三、回滚三步（**不得跳步**）

### 第 1 步：验包（必做）

```bash
cd /workspace/.evo-snapshots/<快照目录>
sha256sum -c manifest.sha256
```

**全部 OK 才继续**。任一 FAIL 说明包已损坏，换一份更早的快照，绝不解包损坏包。

### 第 2 步：解到临时目录（**禁止直接解到 /workspace**）

```bash
mkdir -p /tmp/rollback-$$
cd /tmp/rollback-$$
tar xzf /workspace/.evo-snapshots/<快照目录>/tier0-core.tar.gz
tar xzf /workspace/.evo-snapshots/<快照目录>/tier1-docs.tar.gz
tar xzf /workspace/.evo-snapshots/<快照目录>/tier2-binaries.tar.gz
```

> **为什么禁止 `tar -C /` 直接解**：直接覆盖会**不可逆地摧毁当前状态**，
> 而"当前状态"可能正是你需要比对的对象。解到临时目录保留了反悔权。

### 第 3 步：diff 确认后再覆盖

```bash
# 先看差异，确认要回滚哪些
diff -rq /tmp/rollback-$$/memory-repo /workspace/memory-repo | head -30

# 确认无误后，按 tier 逆序覆盖（tier2 → tier1 → tier0）
cp -a /tmp/rollback-$$/<具体文件> /workspace/<目标路径>
```

**每覆盖一个文件前，先 `diff` 一次。** 批量 `cp -a` 覆盖整个目录是禁止的。

---

## 四、RTO（恢复时效）

| 场景 | 目标 | 说明 |
|---|---|---|
| tier0–tier2 恢复 | **< 2 min** | 本地解包 |
| tier3 恢复 | 视网络 | 重下载 APK / 重建 dex-tools + enjarify；B2 jar 重建见 `legado-knowledge-repo/tools/b2/BUILD.md` |

---

## 五、快照保留策略

- **保留最近 2 份**，更早的删除（tier2 每份 41MB，2 份已 82MB）
- 删除前确认 manifest 最新一份校验通过

```bash
ls -dt /workspace/.evo-snapshots/*/ | tail -n +3 | xargs rm -rf   # 保留最近 2 份
```

---

## 五点五、旧快照体系处置

`20261027T001950Z/` 及更早的快照使用**旧命名**（`workspace-md` / `skills` / `src`），
与本 SOP 的 `tier*` 体系**不兼容**——保留最近 2 份时会被清除。

如需保留旧体系快照，请先手动改名为 `tierX-legacy.tar.gz` 并补进其 `manifest.sha256`。

---

## 六、与 git 的分工

| 资产 | 保护方式 |
|---|---|
| `memory-repo/` | **git**（双远端 Gitee + GitHub）+ 快照 tier0 |
| `legado-knowledge-repo/` | **git**（Gitee 权威；GitHub 异步降级）+ 快照 tier0 |
| `/workspace` 其余（61 文件） | **仅快照**（非 git 仓库） |
| `~/.codebuddy/skills/` | 快照（不在任何 git 库内，修改前必须手动 `cp` 备份） |

> **A3 单点写入提醒**：`memory-repo` 是记忆类资产的**唯一权威路径**。
> `/workspace` 下的同名副本仅为跨端入口便利，由 `update_memory.py` 同步，
> 校验见 P1-1 `check_assets.py` 第 2 项。
