#!/usr/bin/env bash
# 回滚脚本 —— 落地 ROLLBACK.md「三、回滚三步」+ 书源侧复验报告判据
# 判据（采纳书源侧复验报告_P0全项 §三）：无 manifest 或 manifest 校验不通过的快照 = 不可恢复，拒绝解包。
# 三步不得跳步：① 验包 ② 解到临时目录(禁止直接解 /workspace) ③ diff 确认后按 tier 逆序覆盖。
set -euo pipefail

SNAP="${1:-}"
if [ -z "$SNAP" ]; then
  echo "用法: restore.sh <快照目录名>" >&2
  echo "      例: restore.sh 20261027T001950Z" >&2
  exit 1
fi

D="/workspace/.evo-snapshots/$SNAP"
[ -d "$D" ] || { echo "[restore] 快照不存在: $D" >&2; exit 2; }
[ -f "$D/manifest.sha256" ] || { echo "[restore] 无 manifest.sha256 -> 标为不可恢复，拒绝解包" >&2; exit 3; }

cd "$D"
echo "[restore] 第1步: 验包"
if ! sha256sum -c manifest.sha256; then
  echo "[restore] manifest 校验失败 -> 包已损坏，换更早快照，绝不解包" >&2
  exit 4
fi

TD="/tmp/rollback-$$"
mkdir -p "$TD"
echo "[restore] 第2步: 解到临时目录 $TD (禁止直接覆盖 /workspace)"
tar xzf "$D/tier0-core.tar.gz" -C "$TD"
tar xzf "$D/tier1-docs.tar.gz" -C "$TD"
tar xzf "$D/tier2-binaries.tar.gz" -C "$TD"

echo "[restore] 第3步: 先 diff 确认，再按 tier 逆序覆盖（禁止批量 cp -a 覆盖整个目录）"
diff -rq "$TD/memory-repo" /workspace/memory-repo | head -30 || true
echo "[restore] 确认后按需覆盖，例: cp -a $TD/memory-repo/evo/<文件> /workspace/memory-repo/evo/<文件>"
