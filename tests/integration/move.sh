#!/usr/bin/env bash
# Tier 2 integration test: assert Omyview's drop dispatch performs a SILENT move —
# the window lands on the target workspace and the active workspace does NOT change.
# Runs on a nested, throwaway Hyprland isolated from any live session.
# Requires: Hyprland, foot, jq. SKIPs cleanly if any is missing.
set -euo pipefail

for bin in Hyprland foot jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: '$bin' not found"; exit 0; }
done

TMP=$(mktemp -d)
HYPR_PID=""
NESTED=""
cleanup() {
  [[ -n "$NESTED" ]] && HYPRLAND_INSTANCE_SIGNATURE="$NESTED" hyprctl dispatch exit >/dev/null 2>&1 || true
  [[ -n "$HYPR_PID" ]] && kill "$HYPR_PID" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

cat > "$TMP/hypr.conf" <<'CONF'
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
  vfr = true
}
CONF

LIVE_SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
Hyprland -c "$TMP/hypr.conf" > "$TMP/hypr.log" 2>&1 &
HYPR_PID=$!

# Find the nested instance: newest signature that isn't the live one AND is responsive.
for _ in $(seq 1 60); do
  for s in $(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null); do
    [[ "$s" == "$LIVE_SIG" ]] && continue
    if HYPRLAND_INSTANCE_SIGNATURE="$s" hyprctl monitors -j >/dev/null 2>&1; then NESTED="$s"; break; fi
  done
  [[ -n "$NESTED" ]] && break
  sleep 0.25
done
[[ -n "$NESTED" ]] || { echo "FAIL: nested Hyprland did not come up"; sed -n '1,40p' "$TMP/hypr.log"; exit 1; }

hc() { HYPRLAND_INSTANCE_SIGNATURE="$NESTED" hyprctl "$@"; }

# SAFETY: the nested instance must present a nested/headless output, never a real monitor —
# refuse rather than risk dispatching into a live session.
MON=$(hc monitors -j | jq -r '.[0].name')
case "$MON" in
  WAYLAND-*|WL-*|HEADLESS-*) : ;;
  *) echo "REFUSE: instance monitor '$MON' is not nested; aborting"; exit 1 ;;
esac

hc dispatch workspace 1 >/dev/null
hc dispatch exec foot >/dev/null

# Wait for the foot client to appear.
ADDR=""
for _ in $(seq 1 40); do
  ADDR=$(hc clients -j | jq -r '[.[] | select(.class=="foot")][0].address // empty')
  [[ -n "$ADDR" ]] && break
  sleep 0.25
done
[[ -n "$ADDR" ]] || { echo "FAIL: foot client did not appear"; exit 1; }

ACTIVE_BEFORE=$(hc activeworkspace -j | jq -r '.id')
# NOTE: Omyview's production drop dispatch is the typed expression
#   hl.dsp.window.move({ workspace = N, follow = false, window = "address:.." })
# which works through Quickshell's IPC but is NOT invocable via `hyprctl dispatch`
# (hyprctl reports "Invalid dispatcher"). This harness therefore asserts the
# equivalent silent-move SEMANTICS via the classic dispatcher; the exact typed
# string is covered by the live/manual test.
hc dispatch movetoworkspacesilent "3,address:${ADDR}" >/dev/null
sleep 0.4

WS_OF_WIN=$(hc clients -j | jq -r --arg a "$ADDR" '.[] | select(.address==$a) | .workspace.id')
ACTIVE_AFTER=$(hc activeworkspace -j | jq -r '.id')

rc=0
[[ "$WS_OF_WIN" == "3" ]] || { echo "FAIL: window on ws '$WS_OF_WIN', expected 3"; rc=1; }
[[ "$ACTIVE_AFTER" == "$ACTIVE_BEFORE" ]] || { echo "FAIL: active ws changed ($ACTIVE_BEFORE -> $ACTIVE_AFTER); follow=false broken"; rc=1; }
[[ "$rc" == 0 ]] && echo "PASS: silent move to ws 3, active ws unchanged (addr $ADDR)"
exit "$rc"
