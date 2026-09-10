#!/usr/bin/env bash
# Probe: does the typed fullscreen dispatcher honour a `window` selector (0.56.2)?
# Prints PREFERRED (it does) or FALLBACK (it only acts on the focused window).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_bins
start_nested
hc dispatch 'hl.dsp.focus({workspace="1"})' >/dev/null
a=$(spawn_window); b=$(spawn_window); sleep 0.4
# Focus `a` explicitly, then ask for fullscreen on `b` by selector.
hc dispatch "hl.dsp.focus({window='address:$a'})" >/dev/null; sleep 0.2
[[ "$(hc activewindow -j | jq -r .address)" == "$a" ]] || { echo "FAIL: could not focus a"; dump; exit 1; }
hc dispatch "hl.dsp.window.fullscreen({window='address:$b', mode='fullscreen', action='toggle'})" >/dev/null || true
sleep 0.3
echo "a fullscreen=$(fsmode "$a") b fullscreen=$(fsmode "$b") active=$(hc activewindow -j | jq -r .address)"
grep -iE 'invalid dispatcher|invalid arg|lua' "$tmp/hypr.log" | tail -3 || true
if [[ "$(fsmode "$b")" == 2 && "$(fsmode "$a")" == 0 ]]; then
    echo PREFERRED
    # Second half: does the same call turn it back off (toggle semantics with the same mode)?
    hc dispatch "hl.dsp.window.fullscreen({window='address:$b', mode='fullscreen', action='toggle'})" >/dev/null; sleep 0.3
    if [[ "$(fsmode "$b")" == 0 ]]; then
        echo 'PREFERRED: toggle with the same mode turns it off'
    else
        echo 'WARN: toggle did not turn it off — inspect hypr.log'
        exit 1
    fi
else
    echo FALLBACK
    exit 1
fi
