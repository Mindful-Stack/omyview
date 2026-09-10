#!/usr/bin/env bash
# Fullscreen interplay on a disposable Lua Hyprland: badge un-fullscreen, drops onto a fullscreen
# anchor, in-place re-tile of a fullscreen window, cross-workspace drag of one.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_bins
# Gaps 0 so slot arithmetic is exact. preserve_split so the rig is deterministic: the nested
# output takes the size of its window in the host session (the requested mode is advisory), and
# with dwindle's default preserve_split=false the split orientation is re-derived from the
# parent's aspect ratio on every recalculation — a fullscreen enter/exit is one, so on a portrait
# output a left/right insert silently flips back to top/bottom between the drop and the check.
start_nested 'hl.config({ general = { gaps_in = 0, gaps_out = 0 }, dwindle = { preserve_split = true } })'
fs_on() { hc dispatch "hl.dsp.window.fullscreen({window='address:$1', mode='fullscreen', action='toggle'})" >/dev/null; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
# Optimistic state must clear because fresh data confirmed the change, not because the 1.8 s
# deadline expired — and the difference is wall time, not iterations: every poll here is an IPC
# round trip of its own, so a tick-counted loop can straddle the deadline and still call it PASS.
wait_ack() {   # $1 label, $2 ipc getter (pending|pendingFullscreen), $3 start ms
    local waited
    for _ in $(seq 1 120); do [[ "$(ipc "$2")" == '{}' ]] && break; sleep 0.05; done
    waited=$(( $(now_ms) - $3 ))
    [[ "$(ipc "$2")" == '{}' ]] || { echo "FAIL: $1 never acknowledged (${waited}ms)"; dump; exit 1; }
    (( waited < 1500 )) || { echo "FAIL: $1 ack took ${waited}ms — deadline path?"; dump; exit 1; }
}

hc dispatch 'hl.dsp.focus({workspace="1"})' >/dev/null
a=$(spawn_window); b=$(spawn_window); sleep 0.4
hc dispatch 'hl.dsp.focus({workspace="3"})' >/dev/null
t1=$(spawn_window); t2=$(spawn_window); sleep 0.4
hc dispatch 'hl.dsp.focus({workspace="1"})' >/dev/null
hc dispatch "hl.dsp.focus({window='address:$a'})" >/dev/null; sleep 0.2
start_quickshell
ipc openOverview

# (a0) badge on a window on the HIDDEN workspace, while `a` is focused on workspace 1. The
# compositor can hold focus on one window while another is fullscreen as long as they are on
# different workspaces, so this is the one place the exact focus check is expressible: focus,
# cursor and active workspace must all come back untouched, and t2 returns to its slot.
# It runs FIRST because the fullscreen in (a) drops the active window to null and, with the
# overview's layer surface holding the keyboard grab, no focus dispatch can put one back for the
# rest of the run (verified: three dispatch forms, all no-ops).
before_t2=$(geometry "$t2")
fs_on "$t2"; wait_fs "$t2" 2
[[ "$(hc activewindow -j | jq -r .address)" == "$a" ]] || { echo "FAIL: focus left a when t2 went fullscreen on the hidden workspace (active=$(hc activewindow -j | jq -r .address))"; dump; exit 1; }
cursor=$(settled_cursor)
t0=$(now_ms)
ipc unfullscreen "$t2"
wait_fs "$t2" 0
wait_ack 'hidden-workspace un-fullscreen' pendingFullscreen "$t0"
[[ "$(hc activewindow -j | jq -r .address)" == "$a" ]] || { echo "FAIL: hidden-workspace un-fullscreen changed focus (was $a, now $(hc activewindow -j | jq -r .address))"; dump; exit 1; }
[[ "$(hc cursorpos -j | jq -c .)" == "$cursor" ]] || { echo "FAIL: hidden-workspace un-fullscreen moved the cursor (was $cursor, now $(hc cursorpos -j | jq -c .))"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]] || { echo "FAIL: hidden-workspace un-fullscreen changed the active workspace to $(hc activeworkspace -j | jq .id)"; dump; exit 1; }
[[ "$(geometry "$t2")" == "$before_t2" ]] || { echo 'FAIL: t2 did not return to its slot'; dump; exit 1; }
echo 'PASS: hidden-workspace un-fullscreen leaves focus and cursor untouched'

# (a) badge: un-fullscreen b silently; b returns to the slot it had before.
before_b=$(geometry "$b")
fs_on "$b"; wait_fs "$b" 2
# Fullscreening a window on the ACTIVE workspace drops the compositor's active window to null
# (0.56.2; on a hidden workspace it does not — see (a0), where focus stays on `a`), and focusing
# another window on that workspace exits the fullscreen, so the pre-badge focus cannot be forced
# back to `a` here. Snapshot whatever is focused instead: the invariant is that the badge leaves
# it alone, and a chunk that focused its target would leave `b` focused and fail.
focused=$(hc activewindow -j | jq -r .address)
cursor=$(settled_cursor)
t0=$(now_ms)
ipc unfullscreen "$b"
wait_fs "$b" 0
wait_ack 'un-fullscreen' pendingFullscreen "$t0"
[[ "$(geometry "$b")" == "$before_b" ]] || { echo "FAIL: b did not return to its slot"; dump; exit 1; }
[[ "$(hc activeworkspace -j | jq .id)" == 1 ]] || { echo 'FAIL: active workspace changed'; dump; exit 1; }
[[ "$(hc activewindow -j | jq -r .address)" == "$focused" ]] || { echo "FAIL: focus changed (was $focused, now $(hc activewindow -j | jq -r .address))"; dump; exit 1; }
[[ "$(hc cursorpos -j | jq -c .)" == "$cursor" ]] || { echo 'FAIL: cursor moved'; dump; exit 1; }
echo 'PASS: badge un-fullscreen is silent and lands in the old slot'

# (b) drops onto each side of a FULLSCREEN anchor on hidden workspace 3. After each drop: a is on
# that side inside the anchor's slot, t2 is fullscreen again, active workspace/cursor untouched.
# Then a goes back to workspace 1.
# The anchor's slot is MEASURED here, while it is still tiled, and not derived from the usable
# area: window borders inset a tiled window from its slot, so complement arithmetic over the
# monitor rect is off by the border width and picks the wrong split axis. This single measurement
# is what all four sides below and case (c) are checked against, so it has to stay true across the
# whole block: each drop is undone by moving `a` back to workspace 1, and dwindle re-merges the
# split so t2's slot returns to exactly this rect (with preserve_split pinned, it does).
read -r sx sy sw sh _ < <(boxof "$t2")
fs_on "$t2"; wait_fs "$t2" 2
midx=$(( sx + sw / 2 )); midy=$(( sy + sh / 2 ))
drop_side() {   # $1 side, $2 gx, $3 gy, $4 jq predicate over {x,y,w,h} of `a` given $sx.. as args
    local cursor; cursor=$(settled_cursor)
    ipc dropPoint "$a" 3 "$2" "$3"
    wait_pending
    read -r ax ay aw ah aws < <(boxof "$a")
    [[ "$aws" == 3 ]] || { echo "FAIL($1): a not on workspace 3"; dump; exit 1; }
    jq -ne --argjson x "$ax" --argjson y "$ay" --argjson w "$aw" --argjson h "$ah" \
        --argjson sx "$sx" --argjson sy "$sy" --argjson sw "$sw" --argjson sh "$sh" "$4" >/dev/null || {
        echo "FAIL($1): a not on the $1 side of the fullscreen anchor's slot"; dump; exit 1; }
    [[ "$(fsmode "$t2")" == 2 ]] || { echo "FAIL($1): anchor lost fullscreen"; dump; exit 1; }
    [[ "$(hc activeworkspace -j | jq .id)" == 1 ]] || { echo "FAIL($1): active workspace changed to $(hc activeworkspace -j | jq .id)"; dump; exit 1; }
    [[ "$(hc cursorpos -j | jq -c .)" == "$cursor" ]] || { echo "FAIL($1): cursor moved (was $cursor, now $(hc cursorpos -j | jq -c .))"; dump; exit 1; }
    hc dispatch "hl.dsp.window.move({workspace='1', follow=false, window='address:$a'})" >/dev/null
    wait_ws "$a" 1
    echo "PASS: drop on the $1 side of a fullscreen anchor lands there; anchor stays fullscreen"
}
drop_side left   $(( sx + 8 ))        "$midy" '$x == $sx and ($x + $w) <= ($sx + $sw / 2 + 1) and $h == $sh'
drop_side right  $(( sx + sw - 8 ))   "$midy" '($x + $w) == ($sx + $sw) and $x >= ($sx + $sw / 2 - 1) and $h == $sh'
drop_side top    "$midx" $(( sy + 8 ))        '$y == $sy and ($y + $h) <= ($sy + $sh / 2 + 1) and $w == $sw'
drop_side bottom "$midx" $(( sy + sh - 8 ))   '($y + $h) == ($sy + $sh) and $y >= ($sy + $sh / 2 - 1) and $w == $sw'

# (c) re-tile the FULLSCREEN window t2 in its own workspace onto the FAR edge of t1: still
# fullscreen afterwards, acknowledged well inside the 1.8 s deadline, and once un-fullscreened it
# sits on that side of t1. The side is picked from where t2's slot sits now (the nested output can
# be portrait or landscape, so dwindle's initial split axis varies): dropping it back onto the
# side it already occupies moves nothing, and an acknowledgement with no geometry change to see
# could only come from the deadline.
read -r x1 y1 w1 h1 _ < <(boxof "$t1")
if [[ "$sx" != "$x1" ]]; then
    gy=$(( y1 + h1 / 2 ))
    if [[ "$sx" -lt "$x1" ]]; then far=right; gx=$(( x1 + w1 - 8 )); else far=left; gx=$(( x1 + 8 )); fi
else
    gx=$(( x1 + w1 / 2 ))
    if [[ "$sy" -lt "$y1" ]]; then far=bottom; gy=$(( y1 + h1 - 8 )); else far=top; gy=$(( y1 + 8 )); fi
fi
t0=$(now_ms)
ipc dropPoint "$t2" 3 "$gx" "$gy"
wait_ack 're-tile' pending "$t0"
[[ "$(fsmode "$t2")" == 2 ]] || { echo 'FAIL: t2 not fullscreen after in-place re-tile'; dump; exit 1; }
ipc unfullscreen "$t2"; wait_fs "$t2" 0
read -r x2 y2 w2 h2 _ < <(boxof "$t2"); read -r x1 y1 w1 h1 _ < <(boxof "$t1")
case "$far" in
    left)   [[ "$y2" == "$y1" && "$h2" == "$h1" && $((x2 + w2)) -le "$x1" ]] ;;
    right)  [[ "$y2" == "$y1" && "$h2" == "$h1" && "$x2" -ge $((x1 + w1)) ]] ;;
    top)    [[ "$x2" == "$x1" && "$w2" == "$w1" && $((y2 + h2)) -le "$y1" ]] ;;
    bottom) [[ "$x2" == "$x1" && "$w2" == "$w1" && "$y2" -ge $((y1 + h1)) ]] ;;
    *)      echo "FAIL(c): unexpected far side $far"; dump; exit 1 ;;
esac || { echo "FAIL: t2 not on the $far side of t1"; dump; exit 1; }
echo 'PASS: fullscreen window re-tiled in place keeps fullscreen; acknowledged promptly'

# (d) a fullscreen window dragged to another workspace arrives tiled (not fullscreen), splitting
# the window it was dropped on: `a` keeps its row and gives up half its width.
fs_on "$t2"; wait_fs "$t2" 2
read -r xa0 ya0 wa0 ha0 _ < <(boxof "$a")
ipc dropPoint "$t2" 1 $(( xa0 + wa0 - 8 )) $(( ya0 + ha0 / 2 ))
wait_pending
# `a` is split by the insert, so compare against its POST-drop geometry, not the one above.
read -r x2 y2 w2 h2 ws2 < <(boxof "$t2"); read -r xa ya wa ha _ < <(boxof "$a")
[[ "$ws2" == 1 && "$(fsmode "$t2")" == 0 && "$y2" == "$ya" && "$h2" == "$ha" && "$x2" -ge $((xa + wa - 1)) ]] || { echo 'FAIL: t2 did not arrive tiled right of a'; dump; exit 1; }
# Landing right of `a` is not enough: t2 must have SPLIT it, so `a` now holds half the width it
# had (borders make the two halves sum to slightly less than the original).
[[ $((wa * 2)) -ge $((wa0 - 8)) && $((wa * 2)) -le $((wa0 + 8)) ]] || { echo "FAIL: a was not split by the insert (width $wa0 -> $wa)"; dump; exit 1; }
echo 'PASS: fullscreen window dragged across workspaces arrives tiled'

[[ "$(hc getoption dwindle:smart_split | head -1 | tr -d ' ')" == "bool:false" ]] || { echo "FAIL: smart_split not restored"; dump; exit 1; }
[[ "$(hc getoption dwindle:use_active_for_splits | head -1 | tr -d ' ')" == "bool:true" ]] || { echo "FAIL: use_active_for_splits not restored"; dump; exit 1; }
if rg -i 'TypeError|ReferenceError|Error loading|Failed to load|Invalid dispatcher' "$tmp/qs.log"; then
    echo 'FAIL: QML errors in qs.log'; exit 1
fi
