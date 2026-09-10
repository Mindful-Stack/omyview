#!/usr/bin/env bash
# Retain the established entry point; exercise production typed dispatch in Lua mode.
set -euo pipefail
exec bash "$(dirname "$0")/drag.sh"
