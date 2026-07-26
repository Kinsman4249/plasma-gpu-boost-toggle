# GPU Boost Toggle

A KDE Plasma 6 panel widget for any Linux distro with an NVIDIA GPU and
`nvidia-smi` available. It shows a panel button that toggles the GPU's
power limit and persistence mode between two profiles:

- **OFF** - your normal/default power limit, persistence mode off.
- **BOOST** - a higher, user-configured power limit, persistence mode on.

Watt values are not hardcoded: you set them yourself in the widget's
settings, and the widget can query `nvidia-smi` to suggest starting
values the first time you open settings.

This project makes no assumptions about your distro (no rpm-ostree, no
distro-specific package manager). It only needs KDE Plasma 6, `nvidia-smi`,
and standard `pkexec`/polkit, which ship on effectively every Plasma
desktop.

## How it works

- The widget polls `nvidia-smi` every few seconds (and on load) to show
  the GPU's real current state, not just whatever you last clicked. If
  you change the power limit from a terminal, the widget catches up on
  the next poll.
- Clicking the panel button toggles between OFF and BOOST.
- Changing the power limit requires root. The widget never calls `sudo`
  itself; it calls `pkexec gpu-boost-helper.sh <mode> <watts>`, which
  triggers a normal polkit authentication prompt. The helper script is
  the only thing that runs as root, and it strictly validates its
  arguments before touching anything.
- The widget always starts **OFF** on first install and after every
  reboot. This is by design: state is intentionally not persisted across
  reboots, since the GPU itself resets to its default power limit and
  persistence-off on reboot anyway, and the widget's next poll will
  confirm that and show OFF.

## Prerequisites

- KDE Plasma 6 (needs `kpackagetool6`)
- An NVIDIA GPU with `nvidia-smi` installed and working
- `pkexec` / polkit (installed by default on virtually all Plasma desktops)

## Quick install

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Kinsman4249/plasma-gpu-boost-toggle/main/quick-install.sh)"
```

This just clones the repo into a temp directory and runs the same
`install.sh` described below - it does not skip the review step for you.
If you'd rather read the scripts first (recommended, since one of them
places root-owned files), use the manual steps instead.

## Manual install

Nothing is installed automatically. Review the scripts, then run:

```sh
git clone https://github.com/Kinsman4249/plasma-gpu-boost-toggle.git
cd plasma-gpu-boost-toggle
./install.sh
```

You will be prompted for your password (via `sudo`) twice, once for each
root-owned file it places:

1. `gpu-boost-helper.sh` -> `/usr/local/bin/gpu-boost-helper.sh` (root:root, 0755)
2. `com.kinsman4249.gpuboost.policy` -> `/usr/share/polkit-1/actions/com.kinsman4249.gpuboost.policy` (root:root, 0644)

It then installs the plasmoid itself for your user account with:

```sh
kpackagetool6 -t Plasma/Applet -i ./plasmoid
```

After installing, add the widget to a panel: right-click the panel >
**Add Widgets...**, search for "GPU Boost Toggle", and drag it on. Then
right-click the widget > **Configure...** to set your default and boost
watt values (or accept the values it suggests from `nvidia-smi`).

## Uninstall

```sh
./uninstall.sh
```

This reverses `install.sh` exactly:

- If the GPU currently appears to be in BOOST state, it first restores
  the default power limit (via `pkexec` and the helper script, using the
  wattage saved in the widget's own settings) so you are not left at a
  raised power limit after uninstalling. If that state can't be read for
  any reason (e.g. `nvidia-smi` missing), this step is skipped and a
  message is printed - you can restore it by hand with:
  `sudo nvidia-smi -pl <watts> && sudo nvidia-smi -pm 0`.
- Removes the plasmoid with `kpackagetool6 -t Plasma/Applet -r`.
- Removes `/usr/local/bin/gpu-boost-helper.sh`.
- Removes `/usr/share/polkit-1/actions/com.kinsman4249.gpuboost.policy`.

`uninstall.sh` does **not** delete the widget's saved settings (watt
values, debug logging flag). Those live in your own Plasma config, under
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`, alongside every other
widget's settings. That file is out of scope for this script; delete the
relevant entry yourself if you want it fully gone, or just leave it -
it's inert once the plasmoid is uninstalled.

## Configuration

Open the widget's settings (right-click > Configure) to set:

- **Default (OFF) watts** - power limit used for the OFF state.
- **Boost watts** - power limit used for the BOOST state.
- **Debug logging** - off by default. When on, the widget prints debug
  messages to the console only (nothing is written to disk). A build
  stamp (e.g. `gpu-boost-toggle 2026-07-25.1`) is shown on the settings
  page whenever debug logging is enabled, so you can tell which build a
  bug report came from.

Watt values must be between 50 and 500 (enforced by both the spin boxes
in settings and, more importantly, by `gpu-boost-helper.sh` itself, since
that script runs as root).

## Project layout

```
plasmoid/                              KPackage source for the widget itself
  metadata.json
  contents/
    ui/
      main.qml                         panel button, polling, toggle logic
      config/ConfigGeneral.qml         settings page
    config/
      main.xml                         KConfigXT schema (defaultWatts, boostWatts, debugLogging)
      config.qml                       lists the settings page above

gpu-boost-helper.sh                    root-run helper (on/off/status), strict arg validation
com.kinsman4249.gpuboost.policy        polkit policy authorizing the helper via pkexec
install.sh                             interactive installer (see Manual install above)
uninstall.sh                           interactive uninstaller (see Uninstall above)
```

## Security notes

- The plasmoid never calls `sudo` and never touches root-owned files at
  runtime. Only `install.sh`/`uninstall.sh`, run manually by you, do that.
- The only root-privileged code path is `gpu-boost-helper.sh`, reached
  exclusively through `pkexec` + the polkit policy. It accepts exactly
  three modes (`on`, `off`, `status`) and, for `on`/`off`, one integer
  watt argument in the 50-500 range. Anything else is rejected.
- Changing a GPU's power limit and persistence mode is reversible and
  does not require any confirmation dialog in the widget itself, per
  `nvidia-smi`'s own documentation on these flags.
