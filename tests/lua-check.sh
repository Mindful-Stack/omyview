#!/usr/bin/env bash
# Real-Lua check of the atomic chunks logic.js builds: render them through a throwaway QML
# script (importing logic.js the way the plugin does), parse each with a real interpreter's
# `load()` -- an unparseable chunk is dropped silently by the compositor, not reported
# anywhere -- then run the behaviour suite (tests/lua/tst_chunks.lua) against a mock `hl`.
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)

QML_BIN=""
for c in qml6 qml /usr/lib/qt6/bin/qml; do   # Ubuntu's qml-qt6 installs off PATH
  if command -v "$c" >/dev/null 2>&1; then QML_BIN="$c"; break; fi
done
LUA_BIN=""
for c in lua5.4 lua luajit; do
  if command -v "$c" >/dev/null 2>&1; then LUA_BIN="$c"; break; fi
done

if [ -z "$QML_BIN" ] || [ -z "$LUA_BIN" ]; then
  msg="lua-check needs a Qt6 qml runtime (qml6, qml, /usr/lib/qt6/bin/qml) and a Lua interpreter (lua5.4/lua/luajit) -- missing one of them"
  if [ -n "${CI:-}" ]; then echo "FAIL: $msg (CI must install them)" >&2; exit 1; fi
  echo "SKIP: $msg"; exit 0
fi

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/dump.qml" <<EOF
import QtQuick
import "$src/logic.js" as Logic
QtObject { Component.onCompleted: {
    console.log("CHUNK UNFULLSCREEN " + Logic.unfullscreenLua("0xabc"))
    console.log("CHUNK TILED_INSERT " + Logic.tiledInsertLua("0xabc", 3, { anchor: "0xdef", side: "left", x: 1, y: 2 }))
    console.log("CHUNK TILED_INSERT_NO_ANCHOR " + Logic.tiledInsertLua("0xabc", 3, { anchor: "", side: "", x: 10, y: 20 }))
    console.log("CHUNK FLOATING_MOVE " + Logic.floatingMoveLua("0xabc", 3, { x: 200, y: 1600 }))
    Qt.quit()
} }
EOF

# console.log routes through qDebug, which on a systemd session defaults to the journal rather
# than this process's stderr -- QT_FORCE_STDERR_LOGGING pins it back to stderr. Only what
# follows "CHUNK " is kept (qml's own "qml: " prefix and other noise are dropped). Chunks are
# single-line by construction, so one line per chunk is sound.
QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$QML_BIN" "$fixture/dump.qml" 2>&1 \
  | sed -n 's/^.*CHUNK //p' > "$fixture/chunks.txt"

count=$(grep -c . "$fixture/chunks.txt" || true)
if [ "$count" -lt 4 ]; then
  echo "FAIL: expected 4 generated Lua chunks, got $count (silent/empty output must not pass)" >&2
  cat "$fixture/chunks.txt" >&2
  exit 1
fi

# stdin, not an argument: `lua -e stat file` would run `file` as a script.
"$LUA_BIN" -e '
for line in io.lines() do
  local name, body = line:match("^(%S+) (.+)$")
  local f, err = load("return " .. body, name)
  if not f then io.stderr:write("LUA PARSE FAIL (" .. name .. "): " .. err .. "\n" .. body .. "\n"); os.exit(1) end
end' < "$fixture/chunks.txt"
echo "PASS: $count generated Lua chunks parse"

"$LUA_BIN" "$src/tests/lua/tst_chunks.lua" "$fixture/chunks.txt"
