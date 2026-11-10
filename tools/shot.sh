#!/bin/sh
# usage: tools/shot.sh out.png [seconds] [extra game args...]   (dev helper: renders a frame under Xvfb)
GODOT=${GODOT:-godot}
OUT=$1; T=${2:-3}; shift; shift
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$(dirname "$0")/.." --rendering-driver opengl3 --resolution 1280x720 -- --shot="$OUT" --shot-t="$T" "$@" 2>&1 | grep -E "ERROR|SCRIPT|at:" | head -20
