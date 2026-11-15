#!/usr/bin/env bash
# Launch from any working directory; GODOT is an executable path, not shell code.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${GODOT:-}" ]]; then
  engine="$GODOT"
elif command -v godot >/dev/null 2>&1; then
  engine="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  engine="$(command -v godot4)"
else
  printf '%s\n' 'Godot 4.3 is required. Install the standard edition and set GODOT to its executable, or add godot/godot4 to PATH.' >&2
  exit 127
fi

if ! command -v "$engine" >/dev/null 2>&1; then
  printf 'Godot executable not found: %s\n' "$engine" >&2
  exit 127
fi
version="$("$engine" --version)"
if [[ ! "$version" =~ ^4\.([0-9]+)\. ]] || (( BASH_REMATCH[1] < 3 )); then
  printf 'Godot 4.3 is required; found %s.\n' "$version" >&2
  exit 2
fi
exec "$engine" --path "$project_dir" "$@"
