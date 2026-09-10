#!/usr/bin/env bash
# Real-parse check: renders the atomic Lua chunks logic.js builds (via a tiny throwaway QML
# script that imports logic.js the same way the plugin does) and feeds each one to a real Lua
# interpreter's `load()`. Substring assertions in tst_layout.qml can't catch a chunk that is
# simply not valid Lua -- and an unparseable chunk is dropped silently by the compositor, not
# reported anywhere -- so this closes that gap.
set -euo pipefail
src=$(cd "$(dirname "$0")/.." && pwd)

QML_BIN=""
for c in qml6 qml; do
  if command -v "$c" >/dev/null 2>&1; then QML_BIN="$c"; break; fi
done
LUA_BIN=""
for c in lua5.4 lua luajit; do
  if command -v "$c" >/dev/null 2>&1; then LUA_BIN="$c"; break; fi
done

if [ -z "$QML_BIN" ] || [ -z "$LUA_BIN" ]; then
  echo "SKIP: lua-check needs a Qt6 qml runtime (qml6/qml) and a Lua interpreter (lua5.4/lua/luajit) -- missing one of them"
  exit 0
fi

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/dump.qml" <<EOF
import QtQuick
import "$src/logic.js" as Logic
QtObject { Component.onCompleted: {
    console.log("CHUNK " + Logic.unfullscreenLua("0xabc"))
    console.log("CHUNK " + Logic.tiledInsertLua("0xabc", 3, { anchor: "0xdef", side: "left", x: 1, y: 2 }))
    console.log("CHUNK " + Logic.tiledInsertLua("0xabc", 2, { anchor: "", side: "", x: 10, y: 20 }))
    Qt.quit()
} }
EOF

# console.log routes through qDebug, which on a systemd session defaults to the journal rather
# than this process's stderr -- QT_FORCE_STDERR_LOGGING pins it back to stderr so the pipe below
# actually sees the lines. qml6's own "qml: " prefix (and any other noise before it) is stripped
# by only keeping what follows "CHUNK ".
chunks=$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$QML_BIN" "$fixture/dump.qml" 2>&1 | sed -n 's/^.*CHUNK //p')

count=$(printf '%s\n' "$chunks" | grep -c . || true)
if [ "$count" -lt 3 ]; then
  echo "FAIL: expected at least 3 generated Lua chunks, got $count (silent/empty output must not pass)" >&2
  exit 1
fi

if ! printf '%s\n' "$chunks" | "$LUA_BIN" -e '
for line in io.lines() do
  local f, err = load("return " .. line)
  if not f then
    io.stderr:write("LUA PARSE FAIL: " .. err .. "\n" .. line .. "\n")
    os.exit(1)
  end
end'; then
  exit 1
fi

echo "PASS: $count generated Lua chunks parse"
