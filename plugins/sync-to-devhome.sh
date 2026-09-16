#!/system/bin/sh
# 把仓库里的自研插件同步到开发环境的 dshroot。
#
# 为什么需要：build.sh 组装 payload 时，插件来自 $DSH_DEV_HOME/dshroot（不是本仓库的
# plugins/ 目录）—— 仓库里的 plugins/ 只是归档。改了插件（例如 v1.13.8 的
# dsh-tool-vscreen 端口改成读 APP_VS_PORT）却不同步，打包出来的还是 devhome 里的旧版。
#
# 用法：sh plugins/sync-to-devhome.sh ["$DSH_DEV_HOME"]
#      不传参数则用环境变量 DSH_DEV_HOME。
set -e

H="${1:-$DSH_DEV_HOME}"
[ -n "$H" ] || { echo "用法：sh plugins/sync-to-devhome.sh <DSH_DEV_HOME>（或先 export DSH_DEV_HOME=）" >&2; exit 1; }

SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$H/dshroot/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai"
[ -d "$DST" ] || { echo "找不到插件目录：$DST" >&2; exit 1; }

echo "== 源：$SRC"
echo "== 目标：$DST"
for d in "$SRC"/*/; do
  name=$(basename "$d")
  [ -f "$d/lib/index.js" ] || continue
  tgt="$DST/$name"
  if [ -d "$tgt" ]; then
    if diff -q "$d/lib/index.js" "$tgt/lib/index.js" >/dev/null 2>&1; then
      echo "  = $name 已一致，跳过"
      continue
    fi
    cp "$tgt/lib/index.js" "$tgt/lib/index.js.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    echo "  ~ $name 已更新（旧文件备份为 index.js.bak-*）"
  else
    mkdir -p "$tgt/lib"
    echo "  + $name 新增"
  fi
  cp "$d/lib/index.js" "$tgt/lib/index.js"
  [ -f "$d/package.json" ] && cp "$d/package.json" "$tgt/package.json"
done
echo "== 完成。接下来：bash android-app/build.sh coexist =="
