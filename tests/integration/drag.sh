#!/usr/bin/env bash
# Exercises the real Overview submit/ack code via Quickshell on a disposable compositor.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_bins
start_nested
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
start_quickshell
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
wait_ws "$addr" 1
wait_pending
[[ "$(hc activeworkspace -j | jq '.id')" == 1 ]] || { echo 'FAIL: active workspace changed'; dump; exit 1; }
echo 'PASS: tiled workspace transfer, silent and acknowledged'

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
pointer_before=$(settled_cursor)
ipc dropPoint "$addr" 1 $((tx + 8)) $((ty + th / 2))
wait_pending
read -r wx wy ww wh wws < <(box "$addr"); read -r tx2 ty2 tw2 th2 _ < <(box "$third")
[[ "$wws" == 1 && "$wy" == "$ty2" && "$wh" == "$th2" && $((wx + ww)) -le "$tx2" ]] || {
    echo "FAIL: W not inserted left of the hovered window"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]] || { echo 'FAIL: active workspace changed'; dump; exit 1; }
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]] || { echo 'FAIL: pointer moved'; dump; exit 1; }
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
pointer_before=$(settled_cursor)
ipc dropPoint "$addr" 3 $((tx + tw - 8)) $((ty + th / 2))
wait_pending
read -r wx wy ww wh wws < <(box "$addr"); read -r tx2 ty2 tw2 th2 tws2 < <(box "$target")
[[ "$wws" == 3 && "$tws2" == 3 && "$wy" == "$ty2" && "$wh" == "$th2" && "$wx" -ge $((tx2 + tw2)) ]] || {
    echo "FAIL: W not inserted right of the hovered window on workspace 3"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]] || { echo 'FAIL: active workspace changed'; dump; exit 1; }
[[ "$(hc cursorpos -j | jq -c .)" == "$pointer_before" ]] || { echo "FAIL: pointer moved (was $pointer_before, now $(hc cursorpos -j | jq -c .))"; dump; exit 1; }
[[ "$(hc getoption dwindle:smart_split | head -1 | tr -d ' ')" == "bool:false" ]] || { echo "FAIL: smart_split not restored"; exit 1; }
[[ "$(hc getoption dwindle:use_active_for_splits | head -1 | tr -d ' ')" == "bool:true" ]] || { echo "FAIL: use_active_for_splits not restored"; exit 1; }
echo 'PASS: production tiled drop inserts at the drop point on a hidden workspace; state restored'
if rg -i 'TypeError|ReferenceError|Error loading|Failed to load|Invalid dispatcher'  "$tmp/qs.log"; then
    echo 'FAIL: QML errors in qs.log'; exit 1
fi
