#!/usr/bin/env bash
# gamerun hook: run Total War: ROME II's built-in "forest" benchmark unattended, then quit the game.
#
#   experiment:  hook=$HOME/src/gamerun/examples/rome2-benchmark-hook.sh
#                bench_window=auto:112          (the benchmark is 1:52; start found from loading stalls)
#   batch:       gamerun batch exp-a exp-b --appid 214950 -n 4
#
# Assumptions (from the investigation this was written for):
# - windowed 2560x1440 (preferences.script.txt: gfx_fullscreen false; x_res 2560; y_res 1440)
# - KDE Wayland; X11 tools (xdotool/xwininfo) available in the toolbox "gamescope-dev" for XWayland
# - reference crops in ~/.config/gamerun/hooks/rome2/{menu_ref.png,adv_ref.png} (not in the repo)
#
# Safety: mouse clicks and window moves only, plus plain Escape (to skip intros) and only when the
# game window has focus. Never sends modifier chords: a synthetic Alt+F4 once switched the session
# to another VT. Aborts without clicking if the screen does not match the expected menu.
set -u
REF=${ROME2_REF_DIR:-$HOME/.config/gamerun/hooks/rome2}
TB=${ROME2_TOOLBOX:-gamescope-dev}
OUT=${GAMERUN_RUN:-/tmp}/rome2-hook; mkdir -p "$OUT"
log() { echo "[rome2-hook $(date +%T)] $*"; }
# toolbox errors go to toolbox-errors.log (silently discarding them hid a failure once);
# every call has a timeout so a stuck podman exec cannot freeze the hook.
X() { timeout 30 toolbox run -c "$TB" bash -c "$1" 2>>"$OUT/toolbox-errors.log" </dev/null; }
VT=$(cat /sys/class/tty/tty0/active)
mark() { command -v gamerun >/dev/null && gamerun mark "$1"; }
quit_game() { pkill -TERM -x Rome2.exe; }
abort() { log "ABORT: $*"; quit_game; exit 1; }

win() { X 'xdotool search --onlyvisible --name "ROME 2" | head -1'; }
geom() { local w; w=$(win); [ -n "$w" ] && X "xwininfo -id $w" | awk '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}/Width/{w=$2}/Height/{h=$2}END{print x,y,w,h}'; }
click() { local gx gy gw gh; read -r gx gy gw gh < <(geom); [ -n "$gx" ] || abort "no game window for click"
          X "xdotool mousemove $((gx + $1)) $((gy + $2)); sleep 0.3; xdotool click 1"; }
shot() { local gx gy gw gh; read -r gx gy gw gh < <(geom)
         timeout 15 spectacle -b -n -f -o "$OUT/full.png" >/dev/null 2>&1
         if [ -n "$gx" ]; then magick "$OUT/full.png" -crop "${gw}x${gh}+${gx}+${gy}" +repage "$OUT/$1.png"; else cp "$OUT/full.png" "$OUT/$1.png"; fi; }
matches() {  # matches NAME REF CROP THRESHOLD
    magick "$OUT/$1.png" -crop "$3" +repage "$OUT/$1-crop.png" 2>/dev/null || return 1
    local d; d=$(compare -metric RMSE "$REF/$2" "$OUT/$1-crop.png" null: 2>&1 | sed 's/.*(\(.*\)).*/\1/')
    log "$1 vs $2: rmse=$d"; awk -v d="$d" -v t="$4" 'BEGIN{exit !(d < t)}'
}

[ -f "$REF/menu_ref.png" ] && [ -f "$REF/adv_ref.png" ] || abort "reference images missing in $REF"
T0=$(date +%s)
log "waiting for the game window (toolbox $TB, DISPLAY=${DISPLAY:-unset})"
for i in $(seq 90); do w=$(X 'xdotool search --name "ROME 2"' | head -1); [ -n "$w" ] && break; [ $((i % 10)) = 0 ] && log "still no window (try $i)"; sleep 2; done
[ -n "${w:-}" ] || abort "no game window after 180 s"
sleep 3; X "xdotool windowmove $w 0 0"

# Skip the intro movies: plain Escape x3 at ~+37 s (earlier presses are ignored by the game).
el=$(( $(date +%s) - T0 )); [ $el -lt 34 ] && sleep $((34 - el))
[ "$(cat /sys/class/tty/tty0/active)" = "$VT" ] || abort "VT changed before sending keys"
X 'w=$(xdotool search --name "ROME 2" | head -1); [ "$w" = "$(xdotool getactivewindow 2>/dev/null)" ] || exit 0; for i in 1 2 3; do xdotool key --clearmodifiers Escape; sleep 1; done'
[ "$(cat /sys/class/tty/tty0/active)" = "$VT" ] || { log "VT CHANGED after Escape; stopping"; exit 2; }

log "waiting for the main menu"
ok=0; for _ in $(seq 90); do shot menu; matches menu menu_ref.png 70x400+0+520 0.08 && { ok=1; break; }; sleep 2; done
[ $ok = 1 ] || abort "main menu not recognised"
sleep 6
click 34 684; sleep 2       # Options (gear)
click 220 583; sleep 3      # Graphics
click 1280 488; sleep 3     # Advanced Options
shot advanced; matches advanced adv_ref.png 840x720+860+390 0.08 || abort "Advanced Options screen not recognised"
click 1280 1010; sleep 3    # Run Benchmark
click 920 554; sleep 1      # "forest"
click 1244 944              # confirm
mark bench_click
log "benchmark started"
sleep 135                   # ~10 s loading + 112 s benchmark + margin
mark bench_done
shot summary                # the game's own "Average FPS" summary screen, kept as evidence
magick "$OUT/summary.png" -crop 900x600+840+280 +repage "$OUT/summary-crop.png" 2>/dev/null
rm -f "$OUT"/full.png "$OUT"/*-crop.png.tmp
log "quitting the game"
quit_game
