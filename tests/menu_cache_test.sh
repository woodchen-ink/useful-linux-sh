#!/bin/bash
# 所有副作用限制在 mktemp 目录;下载、服务操作均由 mock 接管。
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
# 主脚本目前无 source guard,仅剥离最后一行入口。
source <(sed '$d' "$ROOT/uls.sh")
CONFIG_DIR="$TMP/config"
setup_directories
mkdir -p "$CONFIG_DIR/backup"
printf old > "$CONFIG_DIR/scripts/old.sh"
printf partial > "$CONFIG_DIR/scripts/old.sh.tmp"
printf keep > "$CONFIG_DIR/realm_forward.conf"
printf keep > "$CONFIG_DIR/backup/uls_old.sh"
printf keep > "$CONFIG_DIR/scripts/notes.txt"
sync_script_cache
[[ ! -e "$CONFIG_DIR/scripts/old.sh" && ! -e "$CONFIG_DIR/scripts/old.sh.tmp" ]]
[[ -f "$CONFIG_DIR/realm_forward.conf" && -f "$CONFIG_DIR/backup/uls_old.sh" && -f "$CONFIG_DIR/scripts/notes.txt" ]]
[[ $(cat "$CONFIG_DIR/scripts/.uls-version") = "$SCRIPT_VERSION" ]]
printf current > "$CONFIG_DIR/scripts/current.sh"
sync_script_cache
[[ -f "$CONFIG_DIR/scripts/current.sh" ]]
printf previous > "$CONFIG_DIR/scripts/.uls-version"
sync_script_cache
[[ ! -e "$CONFIG_DIR/scripts/current.sh" ]]
echo 'PASS: cache invalidation, same version retention, config and backup safety'
run_script() { echo "$1" >> "$TMP/selected"; }
proxy_node_menu <<< $'bad\n1\n2\n0'
[[ $(cat "$TMP/selected") = $'setup_v2bx.sh\nsetup_xboard_node.sh' ]]
echo 'PASS: dual backend routing and invalid input'
source "$ROOT/scripts/proxy/setup_xboard_node.sh"
XBCTL="$TMP/xbctl"
cat > "$XBCTL" <<'MOCK'
#!/bin/bash
# 按官方解析器区分追加与删除参数,避免仅记录参数掩盖契约错误。
case "$2" in
    add-node|add-machine) [[ "$3" = --panel-url ]] || exit 64 ;;
    remove-node) [[ "$3" = --panel ]] || exit 64 ;;
    *) exit 64 ;;
esac
printf '%s\n' "$@" > "$CALL_LOG"
MOCK
chmod +x "$XBCTL"
export CALL_LOG="$TMP/call"
add_binding <<< $'https://panel.example.com/\n1\n24\nsecret\ny'
[[ $(cat "$CALL_LOG") = $'bind\nadd-node\n--panel-url\nhttps://panel.example.com\n--token\nsecret\n--node-id\n24' ]]
add_binding <<< $'https://panel.example.com\n2\n3\nsecret\ny'
grep -qx 'add-machine' "$CALL_LOG"
rm "$CALL_LOG"
add_binding <<< $'https://panel.example.com\n1\n24\nsecret\nn'
[[ ! -f "$CALL_LOG" ]]
if add_binding <<< $'https://panel.example.com\n1\n0'; then exit 1; fi
[[ ! -f "$CALL_LOG" ]]
if read_panel <<< 'file:///tmp/bad'; then exit 1; fi
remove_binding <<< $'https://panel.example.com\n24\ny'
grep -qx 'remove-node' "$CALL_LOG"
echo 'PASS: node/machine add, node removal, cancellation and input rejection'
is_installed() { return 0; }
run_installer() { printf '%s\n' "$@" > "$CALL_LOG"; }
if install_node; then exit 1; fi
upgrade_node <<< 'y'
[[ $(cat "$CALL_LOG") = upgrade ]]
uninstall_node <<< $'y\n'
[[ $(cat "$CALL_LOG") = $'uninstall\n--yes' ]]
uninstall_node <<< $'y\npurge'
[[ $(cat "$CALL_LOG") = $'uninstall\n--purge\n--yes' ]]
echo 'PASS: reinstall protection, upgrade and uninstall preserve/purge routing'
# 实测下载失败 / HTML 响应不会替换已有脚本。
source <(sed '$d' "$ROOT/uls.sh")
CONFIG_DIR="$TMP/download"
setup_directories
printf '#!/bin/bash\necho original\n' > "$CONFIG_DIR/scripts/sample.sh"
cp "$CONFIG_DIR/scripts/sample.sh" "$TMP/original"
curl() { return 22; }
if download_script sample.sh scripts/sample.sh; then exit 1; fi
cmp "$TMP/original" "$CONFIG_DIR/scripts/sample.sh"
curl() { printf '<html>error</html>\n' > "${@: -1}"; }
if download_script sample.sh scripts/sample.sh; then exit 1; fi
cmp "$TMP/original" "$CONFIG_DIR/scripts/sample.sh"
echo 'PASS: failed and invalid downloads preserve old script'
# 缓存权限与替换失败时,run_script 必须失败且不能执行旧缓存。
printf '#!/bin/bash\nprintf stale > "$STALE_LOG"\n' > "$CONFIG_DIR/scripts/setup_v2bx.sh"
export STALE_LOG="$TMP/stale-executed"
cp "$CONFIG_DIR/scripts/setup_v2bx.sh" "$TMP/stale-original"
curl() { printf '#!/bin/bash\nexit 0\n' > "${@: -1}"; }
mv() { return 1; }
if run_script setup_v2bx.sh; then exit 1; fi
[[ ! -e "$STALE_LOG" && ! -e "$CONFIG_DIR/scripts/setup_v2bx.sh.tmp" ]]
cmp "$TMP/stale-original" "$CONFIG_DIR/scripts/setup_v2bx.sh"
unset -f mv
chmod() { return 1; }
if run_script setup_v2bx.sh; then exit 1; fi
[[ ! -e "$STALE_LOG" && ! -e "$CONFIG_DIR/scripts/setup_v2bx.sh.tmp" ]]
cmp "$TMP/stale-original" "$CONFIG_DIR/scripts/setup_v2bx.sh"
unset -f chmod
echo 'PASS: chmod/mv failures preserve cache and never execute stale script'
# 使用 workflow 中的实际 sed 表达式,防止未来发布再次改写函数内赋值。
version_sed=$(grep 'sed -i.*SCRIPT_VERSION=' "$ROOT/.github/workflows/release.yml" | cut -d "'" -f2)
[[ -n "$version_sed" && "$version_sed" != *$'\n'* ]]
version_sed=${version_sed//'${{ steps.version.outputs.version }}'/9.8.7}
sed "$version_sed" "$ROOT/uls.sh" > "$TMP/release-uls.sh"
grep -qx 'SCRIPT_VERSION="9.8.7"' "$TMP/release-uls.sh"
grep -Fq '( SCRIPT_VERSION="$latest_version"; sync_script_cache )' "$TMP/release-uls.sh"
cmp <(grep -v '^SCRIPT_VERSION=' "$ROOT/uls.sh") <(grep -v '^SCRIPT_VERSION=' "$TMP/release-uls.sh")
bash -n "$TMP/release-uls.sh"
echo 'PASS: release version substitution preserves dynamic function assignment'
