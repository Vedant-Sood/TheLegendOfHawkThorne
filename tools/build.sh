#!/usr/bin/env bash
# Export with the templates matching the installed editor; never download silently.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-all}"
mode="${2:---release}"
usage() { printf '%s\n' 'Usage: tools/build.sh [linux|windows|all] [--release|--debug]'; }
if [[ "$target" == --help || "$target" == -h ]]; then usage; exit 0; fi
if [[ $# -gt 2 || ! "$target" =~ ^(linux|windows|all)$ || ! "$mode" =~ ^--(release|debug)$ ]]; then
  usage >&2
  exit 2
fi

if [[ -n "${GODOT:-}" ]]; then
  engine="$GODOT"
elif command -v godot >/dev/null 2>&1; then
  engine="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  engine="$(command -v godot4)"
else
  printf '%s\n' 'Godot 4.3 is required. Set GODOT or install godot/godot4 on PATH.' >&2
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
if [[ "$version" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?\.[^.]+) ]]; then
  template_version="${BASH_REMATCH[1]}"
else
  printf 'Cannot determine the export template version from %s.\n' "$version" >&2
  exit 2
fi
engine="$(command -v "$engine")"
if [[ "$engine" != /* ]]; then engine="$PWD/$engine"; fi
# Godot uses the editor data directory, independent of the game's user:// saves.
case "$(uname -s)" in
  Darwin) data_dir="$HOME/Library/Application Support/Godot" ;;
  MINGW*|MSYS*|CYGWIN*)
    data_dir="${APPDATA:?APPDATA is required on Windows}"
    if command -v cygpath >/dev/null 2>&1; then data_dir="$(cygpath -u "$data_dir")"; fi
    data_dir="$data_dir/Godot"
    ;;
  *) data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac
template_dir="$data_dir/export_templates/$template_version"
flavour="${mode#--}"
required=()
if [[ "$target" == linux || "$target" == all ]]; then required+=("linux_${flavour}.x86_64"); fi
if [[ "$target" == windows || "$target" == all ]]; then required+=("windows_${flavour}_x86_64.exe"); fi
for template in "${required[@]}"; do
  if [[ ! -s "$template_dir/$template" ]]; then
    printf 'Missing export template: %s\nInstall the %s templates with Editor > Manage Export Templates, then retry.\n' "$template_dir/$template" "$template_version" >&2
    exit 1
  fi
done

cd -- "$project_dir"
# A normal source launch needs no import step; exporting compiled scripts does.
import_log="$(mktemp)"
if ! "$engine" --headless --path "$project_dir" --editor --import >"$import_log" 2>&1; then
  cat -- "$import_log" >&2
  rm -f -- "$import_log"
  exit 1
fi
cat -- "$import_log"
# Some Godot script-loading errors do not propagate to the editor's exit code.
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$import_log"; then
  rm -f -- "$import_log"
  exit 1
fi
rm -f -- "$import_log"
export_target() {
  local preset="$1" output="$2"
  mkdir -p -- "$(dirname -- "$output")"
  # Export into a temporary name so a failed export cannot overwrite a good build.
  local suffix="${output##*.}"
  local temporary="${output%.*}.pending.$suffix"
  local export_log
  export_log="$(mktemp)"
  if ! "$engine" --headless --path "$project_dir" "--export-$flavour" "$preset" "$temporary" >"$export_log" 2>&1; then
    cat -- "$export_log" >&2
    rm -f -- "$export_log" "$temporary" "${temporary%.*}.pck" "${temporary%.*}.console.exe" "${temporary%.*}.sh"
    return 1
  fi
  cat -- "$export_log"
  if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$export_log"; then
    rm -f -- "$export_log" "$temporary" "${temporary%.*}.pck"
    return 1
  fi
  rm -f -- "$export_log"
  if [[ ! -s "$temporary" ]]; then
    printf 'Export did not create a non-empty executable: %s\n' "$temporary" >&2
    return 1
  fi
  mv -f -- "$temporary" "$output"
  # Console wrappers reference the temporary basename; omit them from release output.
  rm -f -- "${temporary%.*}.console.exe" "${temporary%.*}.sh"
  printf 'Exported %s\n' "$output"
}
if [[ "$target" == linux || "$target" == all ]]; then export_target Linux "$project_dir/build/linux/Hawkthorne.x86_64"; fi
if [[ "$target" == windows || "$target" == all ]]; then export_target 'Windows Desktop' "$project_dir/build/windows/Hawkthorne.exe"; fi
