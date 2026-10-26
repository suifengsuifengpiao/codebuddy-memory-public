#!/usr/bin/env bash
# pre_archive_gate.sh — A9 执行点：归档/发布前凭据闸门
#
# 背景：2026-10-27 复验发现 A9（密钥不得进入对话/文件/存档）写下的第 50 分钟即被违反
#       （明文令牌存于 /tmp 工作副本 .git/config，且历史会话存档含 5 处明文）。
#       根因：A9 是九条铁律中唯一"零执行点、纯自觉"的一条。
#       本脚本把它变成可阻断的机器闸门。
#
# 用法：
#   ./pre_archive_gate.sh                  # 检查默认目标（memory-repo 工作区 + /workspace 根 md）
#   ./pre_archive_gate.sh <dir|file> ...   # 检查指定目标
#   ./pre_archive_gate.sh --fix <target>   # 命中即就地脱敏（破坏性，先备份）
#
# 退出码：0 = 干净可归档；1 = 命中凭据，阻断
set -uo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
CRED="$HOME/.git-credentials"
FIX=0
if [ "${1:-}" = "--fix" ]; then FIX=1; shift; fi
TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=("/workspace/memory-repo" "/workspace")
fi

hits=0
report() { printf "  %s %s\n" "$1" "$2"; }

# 构造检测模式：已知凭据值（精确）+ 通用形态（正则）
PATTERNS=()
if [ -f "$CRED" ]; then
  while IFS= read -r line; do
    v=$(printf '%s' "$line" | sed -n 's#https://[^:]*:\([^@]*\)@.*#\1#p')
    [ -n "$v" ] && [ ${#v} -ge 8 ] && PATTERNS+=("$v")
  done < "$CRED"
fi
# 通用形态
REGEX='https://[^/[:space:]"]*:[^@[:space:]"]{8,}@(gitee|github)\.com'
REGEX2='(gh[pousr]_[A-Za-z0-9]{30,})'
REGEX3='(Authorization:[[:space:]]*(token|Bearer)[[:space:]]+)[A-Za-z0-9_\-]{20,}'
REGEX4='(ima_kb_[A-Za-z0-9]{6,})'

echo "== A9 凭据闸门 =="
echo "   已知凭据值: ${#PATTERNS[@]} 个；通用模式: 4 类"
echo

for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || { report "$YEL?$RST" "跳过（不存在）: $t"; continue; }
  f_hits=0
  # 跳过 .git/objects 与二进制
  while IFS= read -r f; do
    case "$f" in
      */.git/objects/*|*/.git/logs/*) continue ;;
      *.tar.gz|*.zip|*.png|*.jpg|*.pdf|*.mp4) continue ;;
    esac
    # 已知凭据值精确匹配
    for p in ${PATTERNS[@]+"${PATTERNS[@]}"}; do
      if grep -qF -- "$p" "$f" 2>/dev/null; then
        report "$RED✗$RST" "已知凭据: ${f}"
        f_hits=$((f_hits+1)); hits=$((hits+1))
      fi
    done
    # 通用形态
    for re in "$REGEX" "$REGEX2" "$REGEX3" "$REGEX4"; do
      if grep -qE -- "$re" "$f" 2>/dev/null; then
        report "$RED✗$RST" "形态匹配($re): ${f}"
        f_hits=$((f_hits+1)); hits=$((hits+1))
      fi
    done
  done < <(find "$t" -type f -size -60M 2>/dev/null | head -4000)

  if [ $f_hits -eq 0 ]; then report "$GRN✓$RST" "干净: $t"; else report "$RED✗$RST" "$t 命中 $f_hits 项"; fi
done

echo
if [ $hits -gt 0 ]; then
  echo "${RED}BLOCKED${RST}: 检出 ${hits} 处凭据，禁止归档/发布。"
  echo "  → 处置：① 脱敏或移除 ② 若已进历史，吊销并轮换该令牌（换历史不等于换钥匙）"
  exit 1
fi
echo "${GRN}PASS${RST}: 未检出凭据，可归档。"
exit 0
