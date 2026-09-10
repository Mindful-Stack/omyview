#!/usr/bin/env bash
# Exercises the real Overview submit/ack code via Quickshell on a disposable compositor.
set -euo pipefail
for bin in Hyprland hyprctl quickshell foot jq; do
    command -v "$bin" >/dev/null || { echo "SKIP: $bin not installed"; exit 0; }
done
src=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
nested=""; hypr_pid=""; qs_pid=""
cleanup() {
    [[ -z "$qs_pid" ]] || kill "$qs_pid" 2>/dev/null || true
    [[ -z "$nested" ]] || HYPRLAND_INSTANCE_SIGNATURE="$nested" hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || true
    [[ -z "$hypr_pid" ]] || kill "$hypr_pid" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT
cat > "$tmp/hypr.lua" <<'CONF'
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true } })
hl.monitor({output="", mode="1280x720", position="0x1440", scale=1})
hl.workspace_rule({workspace="3", persistent=true})
CONF
Hyprland -c "$tmp/hypr.lua" > "$tmp/hypr.log" 2>&1 & hypr_pid=$!
for _ in $(seq 1 60); do
    nested=$(hyprctl instances -j | jq -r --argjson p "$hypr_pid" '.[] | select(.pid==$p) | .instance')
    [[ -z "$nested" ]] || break
    sleep 0.25
done
[[ -n "$nested" ]] || { cat "$tmp/hypr.log"; exit 1; }
hc() { HYPRLAND_INSTANCE_SIGNATURE="$nested" hyprctl "$@"; }
mon=$(hc monitors -j | jq -r '.[0].name')
case "$mon" in WAYLAND-*|WL-*|HEADLESS-*) ;; *) echo "REFUSE: $mon is not nested"; exit 1;; esac
socket=$(hyprctl instances -j | jq -r --argjson p "$hypr_pid" '.[] | select(.pid==$p) | .wl_socket')
# Offset output catches the global-vs-local coordinate regression.
hc dispatch 'hl.dsp.focus({workspace="1"})'  >/dev/null
hc dispatch 'hl.dsp.exec_cmd("foot")'  >/dev/null
addr=""
for _ in $(seq 1 40); do
    addr=$(hc clients -j | jq -r '[.[]|select(.class=="foot")][0].address // empty')
    [[ -z "$addr" ]] || break
    sleep 0.1
done
[[ -n "$addr" ]] || { echo 'FAIL: foot did not appear'; exit 1; }
hc dispatch "hl.dsp.window.float({window='address:$addr',action='toggle'})" >/dev/null
hc dispatch "hl.dsp.window.resize({window='address:$addr',x='400',y='300'})" >/dev/null
# Ensure the target workspace exists without leaving it active.
hc dispatch 'hl.dsp.focus({workspace="3"})'  >/dev/null
hc dispatch 'hl.dsp.focus({workspace="1"})'  >/dev/null
mkdir -p "$tmp/Commons" "$tmp/Ui"
# Theme-only adapters: actual Quickshell, Wayland and Hyprland modules remain intact.
printf 'module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n' > "$tmp/Commons/qmldir"
printf 'pragma Singleton\nimport QtQuick\nQtObject { readonly property var menu: ({background:"#222",text:"#fff",border:"#888",scrim:"#000",selectedBackground:"#444",selectedText:"#fff"}) }\n' > "$tmp/Commons/Color.qml"
printf 'pragma Singleton\nimport QtQuick\nQtObject { readonly property int cornerRadius: 8 }\n' > "$tmp/Commons/Style.qml"
printf 'module qs.Ui\nUnused 1.0 Unused.qml\n' > "$tmp/Ui/qmldir"
printf 'import QtQuick\nItem {}\n' > "$tmp/Ui/Unused.qml"
cp "$src/Overview.qml" "$src/WindowTile.qml" "$src/logic.js" "$tmp/"
cp "$src/tests/integration/drag.qml" "$tmp/shell.qml"
HYPRLAND_INSTANCE_SIGNATURE="$nested" WAYLAND_DISPLAY="$socket" quickshell -p "$tmp/shell.qml" > "$tmp/qs.log" 2>&1 & qs_pid=$!
ipc() { WAYLAND_DISPLAY="$socket" quickshell ipc -p "$tmp/shell.qml" call dragtest "$@"; }
for _ in $(seq 1 40); do
    ipc pending >/dev/null 2>&1 && break
    sleep 0.1
done
ipc pending >/dev/null || { cat "$tmp/qs.log"; exit 1; }
assert_position() {
    local ws="$1" x="$2" y="$3"
    for _ in $(seq 1 40); do
        if hc clients -j | jq -e --arg a "$addr" --argjson ws "$ws" --argjson x "$x" --argjson y "$y" \
            '.[] | select(.address==$a) | .workspace.id==$ws and .at==[$x,$y]' >/dev/null; then
            [[ "$(ipc pending)" == '{}' ]] && break
        fi
        sleep 0.1
    done
    hc clients -j | jq -e --arg a "$addr" --argjson ws "$ws" --argjson x "$x" --argjson y "$y" \
        '.[] | select(.address==$a) | .workspace.id==$ws and .at==[$x,$y]' >/dev/null || {
        hc clients -j | jq '[.[]|{address,at,size,workspace}]'; cat "$tmp/qs.log"; exit 1;
    }
    [[ "$(ipc pending)" == '{}' ]] || { echo 'FAIL: move not acknowledged'; cat "$tmp/qs.log"; exit 1; }
    [[ "$(hc activeworkspace -j | jq '.id')" == 1 ]] || { echo 'FAIL: focus changed'; exit 1; }
}
ipc openOverview
ipc drop "$addr" 1 100 1540
assert_position 1 100 1540
echo 'PASS: real typed floating move on offset monitor, acknowledged'
ipc drop "$addr" 1 150 1580
assert_position 1 150 1580
echo 'PASS: repeated floating move reaches a new position'
ipc drop "$addr" 3 200 1600
assert_position 3 200 1600
echo 'PASS: real typed cross-workspace floating move, silent and acknowledged'
hc dispatch "hl.dsp.window.float({window='address:$addr',action='toggle'})" >/dev/null
sleep 0.2
ipc drop "$addr" 1 100 1540
for _ in $(seq 1 40); do
    [[ "$(hc clients -j | jq -r --arg a "$addr" '.[]|select(.address==$a)|.workspace.id')" == 1 && "$(ipc pending)" == '{}' ]] && break
    sleep 0.1
done
[[ "$(hc clients -j | jq -r --arg a "$addr" '.[]|select(.address==$a)|.workspace.id')" == 1 ]]
[[ "$(ipc pending)" == '{}' ]]
[[ "$(hc activeworkspace -j | jq '.id')" == 1 ]]
echo 'PASS: tiled workspace transfer, silent and acknowledged'

spawn_window() {
    local old count found
    old=$(hc clients -j | jq '[.[].address]')
    hc dispatch 'hl.dsp.exec_cmd("foot")' >/dev/null
    for _ in $(seq 1 40); do
        found=$(hc clients -j | jq -r --argjson old "$old" '.[]|.address as $a|select($old|index($a)|not)|.address' | head -1)
        [[ -z "$found" ]] || { echo "$found"; return; }
        sleep 0.1
    done
    return 1
}
geometry() { hc clients -j | jq -c --arg a "$1" '.[]|select(.address==$a)|{at,size}'; }
wait_pending() {
    for _ in $(seq 1 40); do
        [[ "$(ipc pending)" == '{}' ]] && return
        sleep 0.1
    done
    echo 'FAIL: swap not acknowledged'; cat "$tmp/qs.log"; exit 1
}
second=$(spawn_window)
third=$(spawn_window)
sleep 0.4
first_before=$(geometry "$addr")
third_before=$(geometry "$third")
pointer_before=$(hc cursorpos -j | jq -c .)
ipc dropOn "$addr" "$third"
wait_pending
[[ "$(geometry "$addr")" == "$third_before" ]]
[[ "$(geometry "$third")" == "$first_before" ]]
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]]
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]]
echo 'PASS: production tiled swap exchanges positions/sizes and preserves workspace/pointer'
# Two destination windows: choose the first, while default insertion follows the second.
hc dispatch 'hl.dsp.focus({workspace="3"})' >/dev/null
target=$(spawn_window)
last_target=$(spawn_window)
hc dispatch 'hl.dsp.focus({workspace="1"})' >/dev/null
sleep 0.4
target_before=$(geometry "$target")
pointer_before=$(hc cursorpos -j | jq -c .)
ipc dropOn "$addr" "$target"
wait_pending
[[ "$(hc clients -j | jq -r --arg a "$addr" '.[]|select(.address==$a)|.workspace.id')" == 3 ]]
[[ "$(hc clients -j | jq -r --arg a "$target" '.[]|select(.address==$a)|.workspace.id')" == 3 ]]
[[ "$(geometry "$addr")" == "$target_before" ]] || {
    echo "FAIL: source did not take selected target slot"; hc clients -j | jq '[.[]|{address,at,size,workspace}]'; cat "$tmp/qs.log"; exit 1;
}
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]]
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]]
echo 'PASS: production tiled transfer takes selected slot on hidden workspace'
if rg -i 'TypeError|ReferenceError|Error loading|Failed to load|Invalid dispatcher'  "$tmp/qs.log"; then exit 1; fi
