#!/usr/bin/env bash
# 快照脚本 —— 落地 ROLLBACK.md「一、强制前置动作」
# 任何删除 / 覆盖 / 批量修改之前，必须先建快照。无快照不动手。
# 设计：tier0-core/tier1-docs/tier2-binaries 打包含 manifest；tier3-heavy 只登记不打包。
set -euo pipefail
shopt -s nullglob

TS=$(date +%Y%m%dT%H%M%SZ)
D=/workspace/.evo-snapshots/$TS
mkdir -p "$D"

cd /workspace
echo "[snapshot] 打包 tier0-core (两 git 仓库工作树，排除 .git/releases)..."
tar czf "$D/tier0-core.tar.gz" --exclude=.git --exclude=releases memory-repo legado-knowledge-repo

echo "[snapshot] 打包 tier1-docs (全部 *.md + evo/)..."
tar czf "$D/tier1-docs.tar.gz" $(ls *.md) evo/

echo "[snapshot] 打包 tier2-binaries (*.json/*.skill/*.zip + user_sources/demo)..."
tar czf "$D/tier2-binaries.tar.gz" $(ls *.json *.skill *.zip) user_sources demo

echo "[snapshot] 登记 tier3-heavy (只登记不打包)..."
{ echo "# tier3 只登记不打包"; du -sh --exclude=memory-repo --exclude=legado-knowledge-repo /workspace; } > "$D/tier3-heavy.list"

cd "$D"
sha256sum tier*.tar.gz tier3-heavy.list > manifest.sha256

echo "[snapshot] 完成: $D"
echo "[snapshot] 校验命令: cd $D && sha256sum -c manifest.sha256"
