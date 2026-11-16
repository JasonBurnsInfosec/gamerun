# Example experiments

Copy one into `~/.config/gamerun/experiments/`, set `label=`, `bench_window=` (and `threadwatch_name=` for
better thread data), then `gamerun use <name>` or `gamerun batch a b --appid ID -n 4`.

| file | compares |
|---|---|
| `baseline.conf` | nothing changed; the reference every other experiment is compared against |
| `fsync.conf` | Proton with fsync instead of ntsync (`PROTON_NO_NTSYNC=1`) |
| `wined3d.conf` | WineD3D (OpenGL) instead of DXVK, for D3D8-11 games |
| `cpu-topology.conf` | fewer CPUs reported to the game (`WINE_CPU_TOPOLOGY`) |
| `gamescope.conf` | running inside gamescope (`prefix=`) |
| `gamemode.conf` | Feral GameMode (`prefix=gamemoderun`) |
| `pinned-cores.conf` | the whole game restricted to some CPUs (`prefix=taskset`) |
| `proton-version.conf` | a different Proton build for the same launch (`replace=`) |
| `native-opengl.conf` | a native OpenGL game (MangoHud needs its wrapper there) |
| `settings-file.conf` | an in-game setting changed through its config file for one run (`file_append=`) |
| `nonsteam.conf` | a game started outside Steam (`gamerun run nonsteam -- <command>`) |
