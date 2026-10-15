#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${GODOT_BIN:-}" ]; then
  engine="$GODOT_BIN"
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  engine=/Applications/Godot.app/Contents/MacOS/Godot
elif command -v godot >/dev/null 2>&1; then
  engine=$(command -v godot)
elif command -v godot4 >/dev/null 2>&1; then
  engine=$(command -v godot4)
else
  echo 'Godot 4.5.1 is required. Set GODOT_BIN to its executable.' >&2
  exit 1
fi
exec "$engine" --path "$project_dir" "$@"
