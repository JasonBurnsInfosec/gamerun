# gamerun

**Repeatable benchmark experiments for games on Linux: Steam (Proton / Wine and native), Lutris,
Heroic, umu-launcher or any command.** Define experiments as small files (environment variables such
as `PROTON_NO_NTSYNC` or `WINE_CPU_TOPOLOGY`, wrappers such as gamescope or gamemoderun, temporary
game-setting edits, command rewrites) and switch between them from the terminal. Every launch is
recorded with MangoHud frame times, per-thread CPU data, the Proton/driver/kernel/GPU details and the
sync mode actually in use, and runs can be repeated unattended in interleaved order, so configurations
are compared with statistics instead of eyeballing an FPS counter.

Part of a small toolkit for investigating Linux gaming performance:
**gamerun** (run and record) · [benchsum](https://github.com/JasonBurnsInfosec/benchsum) (frame-time statistics) ·
[threadwatch](https://github.com/JasonBurnsInfosec/threadwatch) (per-thread CPU and wait profiling)

## Why

Comparing two settings properly is tedious: change launch options, launch, run the benchmark, find the
right log, remember which log was which, repeat several times per setting, and hope nothing else changed
in between. gamerun makes each launch a self-describing record and can run interleaved repeats
unattended, so differences can be judged against run-to-run noise.

It was built during an investigation of Total War: ROME II under Proton that found an ntsync vs fsync
gap and a +75% threading workaround
([write-up](https://github.com/ValveSoftware/Proton/issues/512#issuecomment-6919218059)).

## What you can do with it

- Compare Proton settings: ntsync vs fsync, DXVK vs WineD3D, `WINE_CPU_TOPOLOGY`, NVAPI, VKD3D options
- Compare wrappers: gamescope on/off, GameMode, CPU pinning with `taskset`, PRIME offload
- Compare Proton builds, kernels, drivers or power profiles (each run records them; group by them later)
- Change an in-game setting for one run through its config file, restored afterwards
- Run a game's benchmark N times per configuration, unattended, in ABBA order
- Capture per-thread CPU, wineserver load and what the main thread waits on, for every run
- Benchmark non-Steam games (Lutris, Heroic, umu-launcher, a native binary, any command)

## Requirements

- Linux, bash 4.4+, coreutils/procps
- [MangoHud](https://github.com/flightlessmango/MangoHud) for frame-time logs
- Python 3.8+ for benchsum, threadwatch and gamerun-uiflow (standard library only)
- Optional: `vulkaninfo` (GPU/Mesa details in the manifest), `gtm` from
  [gputaskman](https://github.com/shanselman/gputaskman), and for menu automation xdotool (XWayland/X11),
  a screenshot tool (spectacle, grim, gnome-screenshot or ImageMagick `import`) and ImageMagick

## Install

```sh
git clone https://github.com/JasonBurnsInfosec/gamerun ~/src/gamerun
git clone https://github.com/JasonBurnsInfosec/benchsum ~/src/benchsum
git clone https://github.com/JasonBurnsInfosec/threadwatch ~/src/threadwatch
mkdir -p ~/.local/bin
ln -s ~/src/gamerun/gamerun ~/src/gamerun/gamerun-uiflow ~/src/benchsum/benchsum ~/src/threadwatch/threadwatch ~/.local/bin/
```

## Hooking it into your launcher

gamerun wraps the game's command. With no active experiment it simply execs the game, so it can stay
in your launch options permanently.

| launcher | how |
|---|---|
| **Steam** | game → Properties → Launch Options: `/home/<you>/.local/bin/gamerun %command%` (absolute path; Steam's PATH may not include `~/.local/bin`). Game flags go after `%command%` as usual |
| **Steam (Flatpak)** | as above, but the sandbox must see the tools and results: `flatpak override --user --filesystem=~/.local/bin:ro --filesystem=~/src:ro --filesystem=~/.local/share/gamerun com.valvesoftware.Steam` (untested; MangoHud must be the Flatpak extension) |
| **Lutris** | game → Configure → System options → Command prefix: `/home/<you>/.local/bin/gamerun` |
| **Heroic** | game settings → Wrappers → add `/home/<you>/.local/bin/gamerun` |
| **umu-launcher, Wine, a native binary, scripts** | `gamerun run <experiment> -- umu-run /path/Game.exe` (or any command) |

Outside Steam there is no app ID: the run folder is named after `game=` in the experiment (or
`GAMERUN_GAME`), else the `.exe` or program name; `appid=` / `GAMERUN_APPID` set an ID if you want one.

## Quick start: ntsync vs fsync

```sh
gamerun new ntsync                      # creates ~/.config/gamerun/experiments/ntsync.conf from a template
gamerun new fsync
echo 'env PROTON_NO_NTSYNC=1' >> ~/.config/gamerun/experiments/fsync.conf
# for a fixed-length built-in benchmark that follows a loading screen (here 60 s):
echo 'bench_window=auto:60' | tee -a ~/.config/gamerun/experiments/{ntsync,fsync}.conf

gamerun use ntsync     # launch the game, run the benchmark, quit; then:
gamerun use fsync      # ...and alternate a few times (ntsync, fsync, fsync, ntsync, ...)

gamerun runs                                  # what was recorded (sync mode, avg FPS per run)
gamerun compare ntsync fsync --appid 214950   # benchsum: mean ±95% CI, Welch t-test, p-values
gamerun off                                   # back to normal launches
```

More starting points: [`examples/experiments/`](examples/experiments/) (gamescope, GameMode, WineD3D, CPU
topology, CPU pinning, Proton build, native OpenGL, settings files, non-Steam).

## Commands

| command | |
|---|---|
| `gamerun new <name>` | create an experiment from the template |
| `gamerun use <name>` / `off` | choose the active experiment / pass launches straight through |
| `gamerun run <name> -- CMD...` | run any command once with experiment `<name>` (active experiment unchanged) |
| `gamerun status`, `label [name]`, `list`, `edit <name>` | inspect and edit experiments |
| `gamerun runs [filter]` | list runs (including one in progress) with sync mode and windowed avg FPS |
| `gamerun last` | newest run directory |
| `gamerun mark <name>` | timestamp marker in the current run (for hooks and scripts) |
| `gamerun compare LABEL... [--appid ID] [-- benchsum args]` | benchsum over all runs with these labels; the first is the baseline |
| `gamerun batch EXP... --appid ID [-n N] [--order abba\|alternate\|block] [--timeout S] [--cooldown S] [--dry-run]` | launch through Steam once per slot and wait for each run; something (a flow, a hook or you) must end each session |
| `gamerun batch EXP... --launch 'CMD' ...` | the same with any launch command, e.g. `--launch 'lutris lutris:rungameid/12'` |

## Experiment file reference

Lines are `key=value`, or `env NAME=VALUE` to export into the game. `#` starts a comment (after a space).

| key | default | meaning |
|---|---|---|
| `label` | file name | runs with the same label are repeats of one configuration |
| `notes` | | free text, copied into the manifest |
| `game`, `appid` | from Steam | name / ID for the results folder when not launched by Steam |
| `env NAME=VALUE` | | exported into the game (repeatable) |
| `prefix` | | wrapper commands put in front of the game command, e.g. `gamescope -W 1920 -H 1080 -f --`, `gamemoderun`, `taskset -c 0-7`, `prime-run` |
| `replace=FROM=>TO` | | substring replacement in every command argument (repeatable), e.g. skip a launcher or swap the Proton path |
| `args` | | extra arguments appended to the command |
| `mangohud` | `1` | MangoHud frame-time logging |
| `mangohud_opengl` | `0` | add MangoHud's `--dlsym` wrapper for OpenGL games (Vulkan, DXVK and VKD3D don't need it) |
| `mangohud_autostart` | `1` | log from 1 s after start until exit (`0`: toggle with Shift_R+F2, so the log is exactly what you recorded) |
| `mangohud_overlay` | `0` | `0` keeps the HUD invisible (drawn fully transparent; MangoHud must be loaded to log) |
| `bench_window` | | which part of the log is the benchmark: `auto:D[:MS]`, `A-B`, `trim:S:E` or `markers:S:E` (below) |
| `threadwatch` | `1` | per-thread CPU sampling of the game |
| `threadwatch_name` | | regex for the game process (e.g. `^Game\.exe$`); empty = busiest `.exe` |
| `threadwatch_interval` | `0.25` | seconds between samples |
| `threadwatch_also` | `wineserver` | also record these processes (regex; empty = none) |
| `threadwatch_syscalls` | `0` | >0: sample what hot threads are blocked in, at this rate (Hz); keep off for FPS runs |
| `gtm` | `0` | gputaskman GPU snapshots |
| `proton_log` | `0` | `PROTON_LOG=1` into the run directory (large; debugging only) |
| `file_append=PATH::LINE` | | append LINE to PATH for this run only (repeatable; restored on exit) |
| `hook=COMMAND` | | run COMMAND after launch, stop it when the game exits (repeatable) |
| `repin=FROM=>TO` | | move threads whose allowed-CPU list is exactly FROM to TO (repeatable) |
| `repin_name` | `threadwatch_name` | process whose threads `repin` watches |

### Benchmark windows

Without a window, summaries include menus and loading screens, which can dominate the average.

| `bench_window=` | measures | good for |
|---|---|---|
| `auto:D[:MS]` | D seconds starting right after the last loading stall (a frame slower than MS ms, default 250) that still has D s of log after it | fixed-length built-in benchmarks after a loading screen |
| `A-B` | log seconds A to B | known timings |
| `trim:S:E` | the whole log minus S seconds at the start and E at the end | manual runs, captures that start and end at roughly the same place |
| `markers:S:E` | between `gamerun mark S` and `gamerun mark E` | hooks and flows (accurate to ~1 s: MangoHud names logs with 1 s resolution) |

Or set `mangohud_autostart=0` and toggle logging yourself (Shift_R+F2), so the log is the benchmark.
The window is saved as `window.json` in the run directory; benchsum and threadwatch both use it.

### Wrappers (`prefix=`)

`prefix=` goes in front of the whole game command, which is how these tools are normally used from
launch options: `prefix=gamescope -W 2560 -H 1440 -f --` equals `gamescope -W 2560 -H 1440 -f -- %command%`.
The manifest records the final command (and `"gamescope": true` when gamescope is used).

### Temporary file edits

`file_append=PATH::LINE` appends a line to a file for one run. Each file is backed up once before the
launch and restored when the game exits (a file that did not exist is removed again). `%compatdata%`
expands to the game's Proton prefix directory (found in any Steam library, or from `WINEPREFIX`);
`$HOME` and `~` are expanded. Example, ROME II's worker-thread count:

```
file_append=%compatdata%/pfx/drive_c/users/steamuser/AppData/Roaming/The Creative Assembly/Rome2/scripts/preferences.script.txt::number_of_threads 2;
```

The lines are recorded in the manifest, so `benchsum --group-by append` can tell such runs apart.

## Unattended benchmarks: hooks, flows and batches

A **hook** starts after the game and is stopped when it exits. It receives `GAMERUN_RUN` (run
directory), `GAMERUN_APPID`, `GAMERUN_LABEL`, `GAMERUN_EXPERIMENT`, `GAMERUN_GAME_PID` and the display
variables (`DISPLAY`, `WAYLAND_DISPLAY`, `XAUTHORITY`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`);
output goes to `hook.log`. The manifest records `hook_status`: `ok` if every hook exited 0 on its own,
`failed:<code>`, or `killed` if one was still running when the game exited. benchsum skips runs whose
hooks did not succeed, so a hook that drives a benchmark should exit 0 once it is done.

**Flows** are the easy way to write such hooks: `gamerun-uiflow` reads a small text file of steps
(wait for a window or process, press a key, click, compare a screen region with a reference image, set
markers, quit the game).

```
window "ROME 2"                         # wait for the game window
at 34                                   # 34 s after start
key Escape 3                            # skip the intro (plain key, only if the game has focus)
expect menu menu_ref.png 70x400+0+520   # wait until this screen region matches the reference
click 34 684                            # click relative to the window
mark bench_start
sleep 112
mark bench_end
quit "Game\.exe"
```

Complete examples: [`examples/flows/rome2-benchmark.flow`](examples/flows/rome2-benchmark.flow) (menus,
screen checks) and [`examples/flows/timed-capture.flow`](examples/flows/timed-capture.flow) (no menus, no X
tools: wait, record a fixed stretch, quit; also fits games with a command-line benchmark flag set via
`args=`). `gamerun-uiflow --help` lists every command and setting.

Writing a flow for a new game:
1. Run the game windowed at a fixed resolution and note click coordinates relative to the window
   (`xdotool getmouselocation` minus the window position, or measure on a screenshot).
2. For every screen you must be sure of before clicking, save a reference crop once:
   `magick shot.png -crop WxH+X+Y +repage ref.png` (region relative to the game window).
3. Try it with the game running: `gamerun-uiflow my.flow`; `--dry-run` prints what would happen.
4. Add `hook=gamerun-uiflow /path/my.flow` and a `bench_window` to the experiments.

Safety: flows refuse key combinations unless `set allow_chords yes` (a synthetic Alt+F4 through
XWayland once switched a session to another virtual terminal), send keys only when the game window has
focus, and stop if the active virtual terminal changes. `set on_fail <process>` quits the game when a
step fails, so a batch can carry on.

With a hook or flow that ends each session, **batches** run unattended:

```sh
gamerun batch ntsync fsync --appid 214950 -n 4 --dry-run   # order: ntsync fsync fsync ntsync ntsync fsync fsync ntsync
gamerun batch ntsync fsync --appid 214950 -n 4
```

ABBA order (the default) cancels slow drift such as heat soak or background activity. The previously
active experiment is restored afterwards.

## Run directory

`<results>/<appid>-<game>/<timestamp>_<label>/`, where `<results>` is `GAMERUN_RESULTS`, else `results=`
in `~/.config/gamerun/config`, else `~/.local/share/gamerun/runs`.

| file | contents |
|---|---|
| `manifest.json` | game, appid, experiment, label, notes, env applied, file edits, hooks and hook status, bench window, sync mode (ntsync / fsync / esync / server / native, plus which processes hold `/dev/ntsync`), Proton version and path, kernel, GPU model, NVIDIA driver / Mesa version, CPU, RAM, distro, desktop session, power profile / governor / EPP, gamescope used, exit code, start/end/duration, full command |
| `experiment.conf` | the experiment exactly as it was for this run |
| `mangohud/*.csv` | per-frame log |
| `window.json` | benchmark window (log seconds and epoch), avg FPS, frame count |
| `summary.txt` | benchsum summary of this run |
| `threadwatch/` | per-thread samples, `summary.txt` (same window, per-frame figures) |
| `uiflow/` | screenshots taken by a flow |
| `markers.tsv`, `sync.txt`, `hook.log`, `repin.log`, `file_append.backup.N` | markers, probe result, hook output, repin actions, file backups |
| `gtm.jsonl`, `steam-<appid>.log` | if enabled |
| `gamerun.log` | what gamerun did |

`<results>/index.csv` gets one line per finished run (label, experiment, sync mode, env, file edits,
window, avg FPS, frames, exit code, duration) for spreadsheets and quick filtering.

## Configuration file

`~/.config/gamerun/config` (optional, `key=value`):

| key | default | |
|---|---|---|
| `results` | `~/.local/share/gamerun/runs` | where runs are stored |
| `benchsum`, `threadwatch` | found on PATH, else `~/.local/bin/` | tool paths |
| `steam_root` | auto (native, `~/.steam`, Flatpak) | an unusual Steam location |
| `steam_cmd` | `steam` | how `batch` starts Steam, e.g. `flatpak run com.valvesoftware.Steam` |

## Getting reliable numbers

- Repeat each configuration (n ≥ 3, better 4+) and **interleave** them (`gamerun batch`, ABBA).
- Keep the power profile, background apps and game settings identical; the manifest records the power
  profile, governor and EPP so you can check.
- Use a `bench_window`; whole-session averages are dominated by menus.
- Keep syscall sampling and Proton logging out of runs you use for FPS.
- Check the manifest's `sync` field instead of assuming which sync mode Proton picked.
- Comparing machines, kernels or drivers? Keep everything else equal and group by the manifest field:
  `benchsum runs/*/* --group-by field:kernel`.

## Troubleshooting

- **Steam says the game is still running after it closed**: an old version left a side tool running,
  which kept Steam's launch supervisor alive. Current versions stop side tools by PID with SIGINT,
  SIGTERM, then SIGKILL.
- **A hook's X11 tools (xdotool, xwininfo) fail with "Authorization required"**: the hook did not get
  `XAUTHORITY`. Current versions pass it. Under Wayland, xdotool only reaches XWayland windows (most
  Proton games); native Wayland games need other tools.
- **There's an FPS bar on screen although `mangohud_overlay=0`**: probably Steam's own performance
  overlay (Steam → Settings → In Game), not MangoHud.
- **No frame log**: MangoHud 0.8.x's `no_display` also disables logging (gamerun hides the HUD with zero
  alpha instead); OpenGL games need `mangohud_opengl=1`.
- **Runs that should differ are grouped together**: they share a label and differ only in something done
  outside gamerun. Put such edits in `file_append`/`env` so they are recorded, then use
  `benchsum --group-by`.
- **A comparison looks absurd (e.g. hundreds of FPS)**: a window landed on a menu, usually because the
  benchmark never ran. Check `--runs` output and `hook_status`.

## Limitations

- Developed on KDE Plasma (Wayland) with NVIDIA and Steam Proton; AMD/Intel, other desktops, Flatpak
  Steam and the Lutris/Heroic integrations follow documented interfaces but are less tested.
- `batch` needs something to end each game session (a flow, a hook, the game's own benchmark mode, or
  you).
- Flows click at fixed coordinates: they assume the same resolution and window placement as when written.

## Related

- [benchsum](https://github.com/JasonBurnsInfosec/benchsum): statistics for MangoHud and PresentMon frame-time logs
- [threadwatch](https://github.com/JasonBurnsInfosec/threadwatch): per-thread CPU and wait profiling
- [MangoHud](https://github.com/flightlessmango/MangoHud), [Proton](https://github.com/ValveSoftware/Proton),
  [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)

## License

MIT, see [LICENSE](LICENSE).
