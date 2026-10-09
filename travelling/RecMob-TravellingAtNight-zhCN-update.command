#!/bin/sh
# 汉化更新器（macOS）。由补丁自己装进游戏根目录（travelling.app 旁边），
# 双击即可：问一下云端最新版本，比本机装的新就下载小更新包、校验、
# 交给包里的「安装.command」原地升级。装过一次完整包之后就不用再到处找
# 下载链接了。
#
# 网络来的东西一律不直接信：清单里带 zip 的 sha256，包里的安装器又会按
# 自己的清单逐个文件再校验一次，才碰游戏目录。

# 这几行由 scripts/package_release.py 在打包时改写。
PackageName="夜游漫记 Demo 简体中文补丁"
StateFolderName=".travellingzh_patch"
# 更新线路：GitHub 上的同一份文件，经几个镜像，按顺序试，哪个先通用哪个。
UpdateBases="https://fastly.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://gcore.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://cdn.jsdelivr.net/gh/Cynanchum0109/TravellingatNight-zhcn-RecMob@update/travelling https://raw.githubusercontent.com/Cynanchum0109/TravellingatNight-zhcn-RecMob/update/travelling"
ManualHint="请到 QQ 群 815655398 或百度网盘 https://pan.baidu.com/s/1D6q_cTM8dgRdYSNepM7VBQ?pwd=ffoe（提取码 ffoe）下载最新完整包，直接覆盖安装即可。"

# 脚本所在目录（双击运行时 $PWD 是家目录，不能用）
a="/$0"; a=${a%/*}; a=${a#/}; a=${a:-.}
HERE=$(cd "$a" && pwd -P)

say() { printf '\n== %s ==\n' "$1"; }
die() { printf '\n错误：%s\n\n' "$1" 1>&2; printf '按回车结束，然后直接关掉这个窗口。'; read -r _ </dev/tty 2>/dev/null || true; exit 1; }

# 清单是扁平 JSON，一行一个键；这里按行抠值，不依赖 jq/python。
get() { sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\(.*\)\",\{0,1\}[[:space:]]*\$/\1/p" "$2" | head -n 1; }

printf '%s - 检查更新\n' "$PackageName"

# 找游戏目录：拖到图标上的参数 > 本文件就在游戏目录里 > Steam 库记录。
# 所以这个文件放桌面也能用。查库的写法与 安装.command 相同。
GAME=""
if [ -n "$1" ] && [ -d "$1/travelling.app" ]; then
    GAME="$1"
elif [ -d "$HERE/travelling.app" ]; then
    GAME="$HERE"
else
    STEAM="$HOME/Library/Application Support/Steam"
    LIBS="$STEAM/steamapps"
    VDF="$STEAM/steamapps/libraryfolders.vdf"
    if [ -f "$VDF" ]; then
        EXTRA=$(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$VDF")
        LIBS="$LIBS
$(printf '%s\n' "$EXTRA" | sed 's|$|/steamapps|')"
    fi
    OLDIFS=$IFS; IFS='
'
    for lib in $LIBS; do
        [ -d "$lib/common" ] || continue
        for d in "$lib/common"/*; do
            if [ -d "$d/travelling.app" ]; then GAME="$d"; break; fi
        done
        [ -n "$GAME" ] && break
    done
    IFS=$OLDIFS
    [ -n "$GAME" ] && printf '已通过 Steam 自动定位到游戏目录。\n'
fi
[ -n "$GAME" ] || die "没有找到游戏目录。把游戏目录（含 travelling.app 的那个文件夹）拖到本脚本图标上再松手，或者把本文件放进游戏目录后重新双击。"
GAME=$(cd "$GAME" && pwd -P)
printf '游戏目录：%s\n' "$GAME"

STATE="$GAME/$StateFolderName"
[ -f "$STATE/version.txt" ] || die "这台机器上还没装过汉化。更新器只能升级已经装好的汉化，请先下载完整包安装一次。"
installed=$(cat "$STATE/version.txt")
printf '已安装汉化版本：%s\n' "$installed"

localGame="(未知)"
[ -f "$GAME/version.txt" ] && localGame=$(tr -d '\r\n' < "$GAME/version.txt")

say "查询最新版本"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/travellingzh_update.XXXXXX") || die "无法创建临时目录。"
trap 'rm -rf "$WORK"' EXIT
got_manifest=""
for base in $UpdateBases; do
    if curl -fsSL --connect-timeout 8 --max-time 20 "$base/manifest.json?t=$(date +%s)" -o "$WORK/manifest.json" \
        && [ -n "$(get package_version "$WORK/manifest.json")" ]; then
        got_manifest=1; break
    fi
    printf '  连不上 %s，换下一个...\n' "$(printf '%s' "$base" | cut -d/ -f3)"
done
[ -n "$got_manifest" ] || die "所有更新线路都连不上。$ManualHint"
hint=$(get manual_hint "$WORK/manifest.json")
[ -n "$hint" ] && ManualHint="$hint"

latest=$(get package_version "$WORK/manifest.json")
builtFor=$(get built_for_game_version "$WORK/manifest.json")
notes=$(get notes "$WORK/manifest.json")
file=$(get mac_file "$WORK/manifest.json")
url=$(get mac_url "$WORK/manifest.json")
want=$(get mac_sha256 "$WORK/manifest.json")
[ -n "$latest" ] && [ -n "$file$url" ] && [ -n "$want" ] || die "更新服务器返回的信息不完整，本次不更新。"

printf '云端最新版本：%s（对应游戏版本 %s）\n' "$latest" "$builtFor"
if [ "$latest" = "$installed" ]; then
    printf '\n已经是最新版本，无需更新。\n'
    printf '按回车关闭。'; read -r _ </dev/tty 2>/dev/null || true
    exit 0
fi

printf '\n发现新版本：%s  ->  %s\n' "$installed" "$latest"
[ -n "$notes" ] && printf '更新内容：%s\n' "$notes"
if [ -n "$builtFor" ] && [ "$localGame" != "$builtFor" ]; then
    printf '注意：这版汉化是按游戏版本 %s 做的，你的游戏是 %s。\n' "$builtFor" "$localGame"
fi
printf '\n请先完全退出游戏。\n'
printf '现在更新吗？直接按回车开始，输入 n 取消：'
read -r answer </dev/tty 2>/dev/null || answer=""
case "$answer" in
    n*|N*) printf '已取消。\n'; exit 0 ;;
esac

say "下载更新包"
# 文件名带版本号，哪个镜像有这个文件就一定是这一版；每个镜像轮流试，
# 下完都对 sha256，对不上也换下一个。
want=$(printf '%s' "$want" | tr 'a-f' 'A-F')
urls=""
if [ -n "$file" ]; then
    for base in $UpdateBases; do urls="$urls $base/$file"; done
fi
[ -n "$url" ] && urls="$urls $url"
ok=""
for u in $urls; do
    if curl -fL --progress-bar --connect-timeout 10 "$u" -o "$WORK/update.zip"; then
        got=$(shasum -a 256 "$WORK/update.zip" | cut -d' ' -f1 | tr 'a-f' 'A-F')
        [ "$got" = "$want" ] && { ok=1; break; }
    fi
    printf '  从 %s 下载失败，换下一个...\n' "$(printf '%s' "$u" | cut -d/ -f3)"
done
[ -n "$ok" ] || die "更新包下载失败（所有线路都试过了）。$ManualHint"
printf '校验通过。\n'

say "解压"
# ditto 而不是 unzip：保留 zip 里的可执行位，安装.command 才能直接运行。
mkdir -p "$WORK/extract"
ditto -x -k "$WORK/update.zip" "$WORK/extract" || die "解压失败。"
installer=$(find "$WORK/extract" -name "安装.command" -type f | head -n 1)
[ -n "$installer" ] || die "更新包里没有安装器，包可能已损坏。"
chmod +x "$installer"
xattr -dr com.apple.quarantine "$WORK/extract" 2>/dev/null || true

say "安装"
# 安装.command 接受游戏目录作为第一个参数，不用它自己再去 Steam 库里找。
"$installer" "$GAME" || die "安装没有完成，请看上面的提示。"
printf '\n更新完成：%s\n' "$latest"
exit 0
