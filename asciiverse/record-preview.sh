#!/bin/sh
# Records fortress-earth.cast, the catalog preview (hub/RECORDING.md): the
# game's own --demo autopilot fighting a war, in the --preview view (the
# reports panel and a window of the map that follows the landings) at
# 100x30, headless. The full screen is 186x55, too big for a preview.
#
# Usage: asciiverse/record-preview.sh <fortress-earth binary> [seed] [out.cast]
#
# The program runs by name from a throwaway folder, with a throwaway home
# and a clean environment, so nothing of this machine ends up in the cast.
# Needs asciinema 3.
set -eu

binary=$1
seed=${2:-1}
out=${3:-fortress-earth.cast}

asciinema=$(command -v asciinema)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home"
cp "$binary" "$work/bin/fortress-earth"

env -i \
  HOME="$work/home" PATH="$work/bin:/usr/bin:/bin" \
  TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 \
  USER=player LOGNAME=player \
  "$asciinema" rec --headless --overwrite \
    --window-size 100x30 \
    --idle-time-limit 2 \
    --capture-env "TERM,COLORTERM,LANG" \
    --title "Fortress Earth" \
    --command "fortress-earth --demo --preview --seed $seed --quit-after 55" \
    "$out"
