# gamerun

**Repeatable benchmark experiments for Steam games on Linux (Proton / Wine and native).**
Set a game's Steam launch options once, then switch experiments from the terminal: environment
variables (`PROTON_NO_NTSYNC`, `WINE_CPU_TOPOLOGY`, DXVK/VKD3D options), temporary game-setting
edits, command rewrites. Every launch is recorded with MangoHud frame times, per-thread CPU data,
the Proton/driver/kernel versions and the sync mode actually in use, so configurations can be
compared with real statistics instead of eyeballing an FPS counter.

Part of a small toolkit for investigating Linux gaming performance:
**gamerun** (run and record) · [benchsum](https://github.com/JasonBurnsInfosec/benchsum) (frame-time statistics) ·
[threadwatch](https://github.com/JasonBurnsInfosec/threadwatch) (per-thread CPU and wait profiling)

## Why

Comparing two Proton settings properly is tedious: edit launch options, launch, run the benchmark,
find the right log, remember which log was which, repeat several times per setting, and hope
nothing else changed in between. gamerun makes each launch a self-describing record and can run
interleaved repeats unattended, so differences can be judged against run-to-run noise.

It was built during an investigation of Total War: ROME II under Proton that found an ntsync vs
fsync gap and a +75% threading workaround
([write-up](https://github.com/ValveSoftware/Proton/issues/512#issuecomment-6919218059)).

## Features

- **Experiments as files**: `~/.config/gamerun/experiments/<name>.conf`; `gamerun use <name>` picks
  what the next launch does. Inactive = plain pass-through with zero overhead.
- **Per-run record**: MangoHud frame-time CSV, `manifest.json` (game, Proton version, NVIDIA/Mesa
  driver, kernel, CPU, power profile, env applied, exit code), and the **sync mode probed from the
  running game** (ntsync / fsync / esync / wineserver).
- **Benchmark windows**: summaries cover only the benchmark (auto-detected after the loading screen,
  fixed seconds, or script markers), not menus running at hundreds of FPS.
- **Temporary file edits** (`file_append`): change a game's settings file for one run and restore
  it automatically afterwards.
- **Hooks**: start your own script with each launch, e.g. to drive a built-in benchmark and quit.
- **Unattended batches**: `gamerun batch a b --appid ID -n 4` launches through Steam in ABBA order.
- **Companion tools run automatically**: threadwatch (per-thread CPU, wineserver, syscall waits),
  benchsum summaries, optional gputaskman GPU snapshots and Proton logs.
- **Command rewrites**: skip a launcher (`replace=launcher.exe=>Game.exe`), append arguments.
- **Affinity rewrites** (`repin`): move game threads that pin themselves to the wrong CPUs.

## Requirements

- Linux, Steam, bash 4.4+, coreutils/procps
- [MangoHud](https://github.com/flightlessmango/MangoHud) for frame-time logs
- Python 3.8+ for benchsum and threadwatch (stdlib only)
- Optional: `gtm` from [gputaskman](https://github.com/shanselman/gputaskman); for UI-automation hooks,
  whatever your script uses (the ROME II example uses xdotool, spectacle and ImageMagick)

## Install

```sh
git clone https://github.com/JasonBurnsInfosec/gamerun ~/src/gamerun
git clone https://github.com/JasonBurnsInfosec/benchsum ~/src/benchsum
git clone https://github.com/JasonBurnsInfosec/threadwatch ~/src/threadwatch
mkdir -p ~/.local/bin
ln -s ~/src/gamerun/gamerun ~/src/benchsum/benchsum ~/src/threadwatch/threadwatch ~/.local/bin/
```

Then in Steam: game → Properties → Launch Options (absolute path; Steam's PATH may not include
`~/.local/bin`):

```
/home/<you>/.local/bin/gamerun %command%
```

## Quick start: ntsync vs fsync

```sh
gamerun new ntsync                      # creates ~/.config/gamerun/experiments/ntsync.conf from a template
gamerun new fsync
echo 'env PROTON_NO_NTSYNC=1' >> ~/.config/gamerun/experiments/fsync.conf
# optional, for a fixed-length built-in benchmark that follows a loading screen:
echo 'bench_window=auto:112' | tee -a ~/.config/gamerun/experiments/{ntsync,fsync}.conf

gamerun use ntsync     # launch the game from Steam, run the benchmark, quit; repeat 3-4 times
gamerun use fsync      # same again
gamerun use ntsync     # ...ideally alternate (ABBA) rather than doing all of one first

gamerun runs                                  # what was recorded
gamerun compare ntsync fsync --appid 214950   # benchsum: mean ±95% CI, Welch t-test, p-values
gamerun off                                   # back to normal launches
```

## Commands

| command | |
|---|---|
| `gamerun new <name>` | create an experiment from the template |
| `gamerun use <name>` / `off` | choose the active experiment / pass launches straight through |
| `gamerun status`, `label [name]`, `list`, `edit <name>` | inspect and edit experiments |
| `gamerun runs [filter]` | list runs (including one in progress) with sync mode and windowed avg FPS |
| `gamerun last` | newest run directory |
| `gamerun mark <name>` | timestamp marker in the current run (for hooks and scripts) |
| `gamerun compare LABEL... [--appid ID] [-- benchsum args]` | benchsum over all runs with these labels; the first is the baseline |
| `gamerun batch EXP... --appid ID [-n N] [--order abba\|alternate\|block] [--timeout S] [--cooldown S] [--dry-run]` | launch through Steam once per slot and wait for each run; something (a hook or you) must end each session |

## Experiment file reference

Lines are `key=value`, or `env NAME=VALUE` to export into the game. `#` starts a comment.

| key | default | meaning |
|---|---|---|
| `label` | file name | runs with the same label are repeats of one configuration |
| `notes` | | free text, copied into the manifest |
| `env NAME=VALUE` | | exported into the game (repeatable) |
| `mangohud` | `1` | MangoHud frame-time logging |
| `mangohud_autostart` | `1` | log from 1 s after start until exit (`0`: toggle with Shift_R+F2) |
| `mangohud_overlay` | `0` | `0` keeps the HUD invisible (drawn fully transparent; MangoHud must be loaded to log) |
| `bench_window` | | which part of the log is the benchmark: `auto:D[:MS]`, `A-B` or `markers:S:E` (below) |
| `threadwatch` | `1` | per-thread CPU sampling of the game |
| `threadwatch_name` | | regex for the game process (e.g. `^rome2\.exe$`); empty = busiest `.exe` |
| `threadwatch_interval` | `0.25` | seconds between samples |
| `threadwatch_also` | `wineserver` | also record these processes (regex; empty = none) |
| `threadwatch_syscalls` | `0` | >0: sample what hot threads are blocked in, at this rate (Hz); keep off for FPS runs |
| `gtm` | `0` | gputaskman GPU snapshots |
| `proton_log` | `0` | `PROTON_LOG=1` into the run directory (large; debugging only) |
| `replace=FROM=>TO` | | substring replacement in every command argument (repeatable) |
| `args` | | extra arguments appended to the command |
| `file_append=PATH::LINE` | | append LINE to PATH for this run only (repeatable; restored on exit) |
| `hook=COMMAND` | | run COMMAND after launch, stop it when the game exits (repeatable) |
| `repin=FROM=>TO` | | move threads whose allowed-CPU list is exactly FROM to TO (repeatable) |
| `repin_name` | `threadwatch_name` | process whose threads `repin` watches |

### Benchmark windows

Without a window, summaries include menus and loading screens, which can dominate the average.

- `bench_window=auto:D[:MS]`: a D-second benchmark that starts right after the last loading stall
  (a frame slower than MS ms, default 250) with D seconds of log after it. Fits fixed-length built-in
  benchmarks that follow a loading screen.
- `bench_window=A-B`: log seconds A to B.
- `bench_window=markers:S:E`: between `gamerun mark S` and `gamerun mark E` (from a hook). Accurate to
  about 1 s, because MangoHud names its logs with 1 s resolution.

The window is saved as `window.json` in the run directory; benchsum and threadwatch both use it.

### Temporary file edits

`file_append=PATH::LINE` appends a line to a file for one run. Each file is backed up once before the
launch and restored when the game exits (a file that did not exist is removed again). `%compatdata%`
expands to the game's Proton prefix directory; `$HOME` and `~` are expanded. Example, ROME II's thread
count:

```
file_append=%compatdata%/pfx/drive_c/users/steamuser/AppData/Roaming/The Creative Assembly/Rome2/scripts/preferences.script.txt::number_of_threads 2;
```

The lines are recorded in the manifest, so `benchsum --group-by append` can tell such runs apart.

### Hooks and unattended batches

A hook starts after the game and is stopped when it exits. It receives `GAMERUN_RUN` (run directory),
`GAMERUN_APPID`, `GAMERUN_LABEL`, `GAMERUN_EXPERIMENT`, `GAMERUN_GAME_PID` and the display variables
(`DISPLAY`, `WAYLAND_DISPLAY`, `XAUTHORITY`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`). Output
goes to `hook.log`.

The manifest records `hook_status`: `ok` if every hook exited 0 on its own, `failed:<code>`, or
`killed` if a hook was still running when the game exited. benchsum skips runs whose hooks did not
succeed (their logs usually contain no benchmark), so a hook that drives a benchmark should exit 0
once it is done.

With a hook that drives a benchmark and quits the game, batches run unattended:

```sh
gamerun batch ntsync fsync --appid 214950 -n 4 --dry-run   # order: ntsync fsync fsync ntsync ntsync fsync fsync ntsync
gamerun batch ntsync fsync --appid 214950 -n 4
```

ABBA order (the default) cancels slow drift such as heat soak or background activity. The previously
active experiment is restored afterwards.
[`examples/rome2-benchmark-hook.sh`](examples/rome2-benchmark-hook.sh) is a complete hook for Total War:
ROME II's built-in benchmark (skips the intro, opens the benchmark by mouse clicks after checking the
screen, quits when done).

## Run directory

`${GAMERUN_RESULTS:-~/linux-gaming-dev/runs}/<appid>-<game>/<timestamp>_<label>/`

| file | contents |
|---|---|
| `manifest.json` | game, appid, experiment, label, notes, env applied, file edits, hooks and hook status, bench window, sync mode (+ which processes hold `/dev/ntsync`), Proton version and path, kernel, NVIDIA driver / Mesa version, CPU, power profile / governor / EPP, gamescope used, exit code, start/end/duration, full command |
| `experiment.conf` | the experiment exactly as it was for this run |
| `mangohud/*.csv` | per-frame log |
| `window.json` | benchmark window (log seconds and epoch), avg FPS, frame count |
| `summary.txt` | benchsum summary of this run |
| `threadwatch/` | per-thread samples, `summary.txt` (same window, per-frame figures) |
| `markers.tsv`, `sync.txt`, `hook.log`, `repin.log`, `file_append.backup.N` | markers, probe result, hook output, repin actions, file backups |
| `gtm.jsonl`, `steam-<appid>.log` | if enabled |
| `gamerun.log` | what gamerun did |

`<results>/index.csv` gets one line per finished run (label, experiment, sync mode, env, file edits,
window, avg FPS, frames, exit code, duration) for spreadsheets and quick filtering.

## Getting reliable numbers

- Repeat each configuration (n ≥ 3, better 4+) and **interleave** them (`gamerun batch`, ABBA).
- Keep the power profile, background apps and game settings identical; gamerun records the power
  profile, governor and EPP so you can check.
- Use a `bench_window`; whole-session averages are dominated by menus.
- Keep syscall sampling and Proton logging out of runs you use for FPS.
- Check the manifest's `sync` field instead of assuming which sync mode Proton picked.

## Troubleshooting

- **Steam says the game is still running after it closed**: an old version left a side tool running,
  which kept Steam's launch supervisor alive. Current versions stop side tools by PID with SIGINT,
  SIGTERM, then SIGKILL.
- **A hook's X11 tools (xdotool, xwininfo) fail with "Authorization required"**: the hook did not get
  `XAUTHORITY`. Current versions pass it.
- **There's an FPS bar on screen although `mangohud_overlay=0`**: that is probably Steam's own
  performance overlay (Steam → Settings → In Game), not MangoHud.
- **MangoHud logs nothing**: MangoHud 0.8.x's `no_display` also disables logging, which is why gamerun
  hides the HUD with zero alpha instead.
- **Runs that should differ are grouped together**: they share a label and differ only in something
  done outside gamerun. Put such edits in `file_append`/`env` so they are recorded, then use
  `benchsum --group-by`.
- **Never automate games with synthetic modifier chords** (Alt+F4, Ctrl+Alt+…): through XWayland one
  once switched the session to another virtual terminal. The example hook uses mouse clicks and a plain
  Escape only.

## Limitations

- Tested on KDE Plasma (Wayland) with NVIDIA; the sync probe and Proton detection assume Steam's
  standard Proton layout.
- `batch` needs something to end each game session; without a hook, you quit the game yourself.
- The results directory default (`~/linux-gaming-dev/runs`) reflects the author's setup; set
  `GAMERUN_RESULTS` to change it.

## Related

- [benchsum](https://github.com/JasonBurnsInfosec/benchsum): statistics for MangoHud frame-time logs
- [threadwatch](https://github.com/JasonBurnsInfosec/threadwatch): per-thread CPU and wait profiling
- [MangoHud](https://github.com/flightlessmango/MangoHud), [Proton](https://github.com/ValveSoftware/Proton)

## License

MIT, see [LICENSE](LICENSE).
