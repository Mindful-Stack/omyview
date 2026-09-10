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
    echo 'FAIL: drop not acknowledged'; cat "$tmp/qs.log"; exit 1
}
box() { hc clients -j | jq -r --arg a "$1" '.[]|select(.address==$a)|"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.workspace.id)"'; }
dump() { hc clients -j | jq '[.[]|{address,at,size,workspace:.workspace.id}]'; cat "$tmp/qs.log"; }
# Native-drag semantics: a tiled drop re-tiles the window as a split of the hovered window on
# the hovered side. With three windows, drop W on the LEFT edge of `third` (vertical centre):
# W must end up left of `third`, same row/height, nobody swapped.
second=$(spawn_window)
third=$(spawn_window)
sleep 0.4
# Reviewer's case (PR #2): with two vertically stacked windows, dropping the LOWER one near the
# UPPER one's bottom edge previewed "bottom" but inserted it above. Detaching the lower window
# first doubles the upper one's height, so a point taken from the pre-drop layout ends up in the
# upper half of the expanded anchor. The placement must come from the anchor's geometry after
# detachment. First build the stack with the tool itself (drop `third` on `second`'s bottom
# edge, whatever dwindle's initial arrangement), then repeat the same drop on the stack.
stack_below() {   # $1 upper, $2 lower: drop `lower` at `upper`'s bottom edge and assert it stays below
    local ux uy uw uh lx ly lw lh lws
    read -r ux uy uw uh _ < <(box "$1")
    ipc dropPoint "$2" 1 $((ux + uw / 2)) $((uy + uh - 8))
    wait_pending
    read -r ux uy uw uh _ < <(box "$1"); read -r lx ly lw lh lws < <(box "$2")
    [[ "$lws" == 1 && "$lx" == "$ux" && "$lw" == "$uw" && "$ly" -ge $((uy + uh)) ]]
}
stack_below "$second" "$third" || { echo "FAIL: could not stack third below second"; dump; exit 1; }
stack_below "$second" "$third" || {
    echo "FAIL: lower window dropped at the upper window's bottom edge was not kept below it"; dump; exit 1; }
echo 'PASS: production tiled drop places on the previewed side after detachment re-lays out the workspace'
read -r tx ty tw th _ < <(box "$third")
pointer_before=$(hc cursorpos -j | jq -c .)
ipc dropPoint "$addr" 1 $((tx + 8)) $((ty + th / 2))
wait_pending
read -r wx wy ww wh wws < <(box "$addr"); read -r tx2 ty2 tw2 th2 _ < <(box "$third")
[[ "$wws" == 1 && "$wy" == "$ty2" && "$wh" == "$th2" && $((wx + ww)) -le "$tx2" ]] || {
    echo "FAIL: W not inserted left of the hovered window"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]]
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]]
echo 'PASS: production tiled drop re-tiles left of the hovered window (native drag semantics)'
# Drop W on the TOP edge of `second` → W above `second`, same column/width (vertical split).
read -r tx ty tw th _ < <(box "$second")
ipc dropPoint "$addr" 1 $((tx + tw / 2)) $((ty + 8))
wait_pending
read -r wx wy ww wh wws < <(box "$addr"); read -r tx2 ty2 tw2 th2 _ < <(box "$second")
[[ "$wws" == 1 && "$wx" == "$tx2" && "$ww" == "$tw2" && $((wy + wh)) -le "$ty2" ]] || {
    echo "FAIL: W not inserted above the hovered window"; dump; exit 1; }
echo 'PASS: production tiled drop re-tiles above the hovered window'
# Hidden workspace 3 with two windows: drop W on the RIGHT edge of the first → inserted right of
# it, on the hidden workspace, active workspace and pointer untouched, config restored.
hc dispatch 'hl.dsp.focus({workspace="3"})' >/dev/null
target=$(spawn_window)
last_target=$(spawn_window)
hc dispatch 'hl.dsp.focus({workspace="1"})' >/dev/null
sleep 0.4
read -r tx ty tw th _ < <(box "$target")
pointer_before=$(hc cursorpos -j | jq -c .)
ipc dropPoint "$addr" 3 $((tx + tw - 8)) $((ty + th / 2))
wait_pending
read -r wx wy ww wh wws < <(box "$addr"); read -r tx2 ty2 tw2 th2 tws2 < <(box "$target")
[[ "$wws" == 3 && "$tws2" == 3 && "$wy" == "$ty2" && "$wh" == "$th2" && "$wx" -ge $((tx2 + tw2)) ]] || {
    echo "FAIL: W not inserted right of the hovered window on workspace 3"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]]
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]]
[[ "$(hc getoption dwindle:smart_split | head -1 | tr -d ' ')" == "bool:false" ]] || { echo "FAIL: smart_split not restored"; exit 1; }
[[ "$(hc getoption dwindle:use_active_for_splits | head -1 | tr -d ' ')" == "bool:true" ]] || { echo "FAIL: use_active_for_splits not restored"; exit 1; }
echo 'PASS: production tiled drop inserts at the drop point on a hidden workspace; state restored'
if rg -i 'TypeError|ReferenceError|Error loading|Failed to load|Invalid dispatcher'  "$tmp/qs.log"; then exit 1; fi
