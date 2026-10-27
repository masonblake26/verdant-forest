#!/bin/sh
# Screenshot run that never shows up: the window starts minimised and forest.gd parks it unfocusable and off-screen
# (still draws, unlike minimised). No --windowed/--position: Godot moves windows created off-screen onto the main one.
# Usage: tools/shot.sh <out.png> [W H] [extra -- args]; log lands next to the shot as .log.
cd "$(dirname "$0")/.." || exit 1
G="${GODOT:-godot}"   # path to a Godot 4.7 executable (the _console build on Windows shows the log)
out="$1"; w="${2:-1600}"; h="${3:-900}"; shift; [ $# -ge 2 ] && shift 2
timeout 420 "$G" --path . -- --shot="$out" --w="$w" --h="$h" "$@" > "${out%.png}.log" 2>&1
grep -E "saved|ERROR|SCRIPT" "${out%.png}.log" | sort | uniq -c
