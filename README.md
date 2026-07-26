# GPU Boost Toggle

A KDE Plasma 6 panel widget for any Linux distro with an NVIDIA GPU and
`nvidia-smi` available. It shows a panel button that flips a "boost"
state on and off across up to three independent axes:

- **Power** - the GPU's power limit and persistence mode: **OFF** (your
  normal/default power limit) or **BOOST** (a higher, user-configured
  power limit, persistence mode on). This is the widget's core feature
  and always available.
- **Services** *(optional, off by default)* - pauses user-level
  background services (Baloo file indexer, Akonadi PIM/mail sync, and
  any others you list) while boosted, and resumes only the ones it
  actually paused.
- **Power profile** *(optional, off by default)* - switches to the
  `performance` `power-profiles-daemon` profile (CPU governor + platform
  power profile) while boosted, and restores your previous profile
  afterward.

Watt values are not hardcoded: you set them yourself in the widget's
settings, and the widget can query `nvidia-smi` to suggest starting
values the first time you open settings.

Each axis is probed and toggled independently. Some laptop GPUs reject
power-limit changes outright (the OEM's firmware owns power management
instead of exposing it through `nvidia-smi` - the widget detects this and
reports it rather than pretending the change worked). On a system like
that, this widget still switches services and the power profile - see
"Partial support" below.

This project makes no assumptions about your distro (no rpm-ostree, no
distro-specific package manager). The power axis only needs KDE Plasma 6,
`nvidia-smi`, and standard `pkexec`/polkit, which ship on effectively
every Plasma desktop. The services and power-profile axes are optional
and each degrade gracefully if their underlying tool
(`balooctl`/`balooctl6`, `akonadictl`, `powerprofilesctl`) isn't present.

## How it works

- The widget polls `nvidia-smi` every few seconds (and on load) to show
  the GPU's real current power state, not just whatever you last clicked.
  If you change the power limit from a terminal, the widget catches up on
  the next poll. The services and power-profile axes are only checked at
  the moment you toggle, not on this timer.
- Clicking the panel button toggles every enabled axis at once, moving
  toward BOOST or back to OFF depending on whether anything is currently
  boosted.
- Changing the power limit requires root. The widget never calls `sudo`
  itself; it calls `pkexec gpu-boost-helper.sh <mode> <watts>`, which
  triggers a normal polkit authentication prompt. The helper script is
  the only thing that runs as root, and it strictly validates its
  arguments before touching anything.
- The services and power-profile axes never need root at all:
  `balooctl`/`akonadictl`/`systemctl --user` only ever touch your own
  session, and `power-profiles-daemon` authorizes the active local
  session via polkit without a password prompt.
- The widget always starts **OFF** on first install and after every
  reboot. This is by design: state is intentionally not persisted across
  reboots, since the GPU itself resets to its default power limit and
  persistence-off on reboot anyway, and the widget's next poll will
  confirm that and show OFF. The services/power-profile axes likewise
  track "was this actually running/active before" only in memory for the
  current session - see "Partial support" below for the one tradeoff this
  creates.

## Partial support

Not every axis works on every system, and the widget is built around
that rather than treating any one failure as fatal:

- If the GPU rejects power-limit changes (common on laptop GPUs), the
  widget's icon/tooltip reports "Power: unsupported on this GPU" but
  still applies whichever other enabled axes this system supports.
- If `powerprofilesctl` isn't installed, or this system has no
  `performance` profile to switch to, the power-profile axis reports
  itself unsupported the same way.
- The icon only shows a hard error (nothing works at all) when literally
  every enabled axis is unsupported; otherwise it shows boosted/not
  boosted, with the per-axis breakdown in the tooltip.
- The one honest gap: which services this widget itself paused is
  tracked only in memory, not saved to disk. If Plasma restarts while
  BOOST is active, the widget has no way to know what it personally
  stopped, so it deliberately does nothing on the next OFF click rather
  than guessing and possibly starting something that was never running
  in the first place. `uninstall.sh` uses a simpler, separate heuristic
  for this same reason - see its comments.

## Clock speed is intentionally out of scope

True GPU overclocking beyond the card's rated boost clock needs
`nvidia-settings` + Coolbits + Xorg, which doesn't work under Plasma
6/Wayland. The Wayland-safe alternative, driver-level clock locking via
`nvidia-smi -lgc`/`-lmc`, was deliberately left out of this project: on
systems already running [LACT](https://github.com/ilya-zlobintsev/LACT)
(a GPU control daemon with its own clock-locking UI and a persistent
profile it reapplies on resume), a second tool writing the same driver
knobs would just fight it. If you want clock-speed control, use LACT (or
similar) for that axis and this widget for power/services/power-profile.

## Prerequisites

- KDE Plasma 6 (needs `kpackagetool6`)
- An NVIDIA GPU with `nvidia-smi` installed and working
- `pkexec` / polkit (installed by default on virtually all Plasma desktops)
- Optional, only if you turn on the matching Advanced setting:
  `balooctl6`/`balooctl` and/or `akonadictl` (for the services axis),
  `powerprofilesctl` (for the power-profile axis). Each degrades to
  "unsupported" gracefully if missing.

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
- If service idling was ever enabled, resumes Baloo/Akonadi/any configured
  custom units if they currently look paused (a simpler heuristic than the
  widget's own "only restart what I personally paused" - see "Partial
  support" above for why uninstall can't do the same thing).
- If the power-profile axis was ever enabled and the profile is currently
  `performance`, restores it to `balanced`.
- Removes the plasmoid with `kpackagetool6 -t Plasma/Applet -r`.
- Removes `/usr/local/bin/gpu-boost-helper.sh`.
- Removes `/usr/share/polkit-1/actions/com.kinsman4249.gpuboost.policy`.

`uninstall.sh` does **not** delete the widget's saved settings (watt
values, debug logging flag, Advanced options). Those live in your own
Plasma config, under `~/.config/plasma-org.kde.plasma.desktop-appletsrc`,
alongside every other widget's settings. That file is out of scope for
this script; delete the relevant entry yourself if you want it fully
gone, or just leave it - it's inert once the plasmoid is uninstalled.

## Configuration

The **General** page (right-click the widget > Configure) sets the power
axis:

- **Default (OFF) watts** - power limit used for the OFF state.
- **Boost watts** - power limit used for the BOOST state.
- **Debug logging** - off by default. When on, the widget prints debug
  messages to the console only (nothing is written to disk). A build
  stamp (e.g. `gpu-boost-toggle 2026-07-26.4`) is shown on the settings
  page whenever debug logging is enabled, so you can tell which build a
  bug report came from.

Watt values must be between 50 and 500 (enforced by both the spin boxes
in settings and, more importantly, by `gpu-boost-helper.sh` itself, since
that script runs as root).

The **Advanced** page sets the two optional axes, both off by default:

- **Idle services while boosted** - enables the axis, plus per-service
  checkboxes for Baloo and Akonadi, and a free-text box for any other
  `systemctl --user` unit names (KAlarm's own unit name varies by distro,
  so it has a dedicated checkbox that tries `kalarm.service` and simply
  has no effect if that unit doesn't exist on your system). Only services
  that were actually running get paused, and only the ones this widget
  itself paused get resumed.
- **Max CPU performance while boosted** - switches to the `performance`
  `power-profiles-daemon` profile and restores your previous profile
  (whatever it was, not a hardcoded guess) when you turn BOOST off.

## Project layout

```
plasmoid/                              KPackage source for the widget itself
  metadata.json
  contents/
    ui/
      main.qml                         panel button, polling, power-axis + toggle orchestration
      SystemController.qml             services + power-profile axes (no root needed)
      config/ConfigGeneral.qml         settings page: power axis
      config/ConfigAdvanced.qml        settings page: services + power-profile axes
    config/
      main.xml                         KConfigXT schema
      config.qml                       lists both settings pages above

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
  watt argument in the 50-500 range. Anything else is rejected. Adding the
  services/power-profile axes did not grow this: neither needs root, and
  neither touches `gpu-boost-helper.sh` or the polkit policy at all.
- Changing a GPU's power limit and persistence mode is reversible and
  does not require any confirmation dialog in the widget itself, per
  `nvidia-smi`'s own documentation on these flags.
- PackageKit, fwupd, snapd, and similar update daemons are deliberately
  **not** offered as idle-able services: they typically run as system
  (not user) services, and stopping/starting them would require giving
  this widget root access it does not otherwise need. If you want those
  paused during gaming, that is a separate, explicit tradeoff to make
  yourself.
- The power-profile axis deliberately only calls `powerprofilesctl`, never
  `cpupower` or the `scaling_governor` sysfs files directly:
  `power-profiles-daemon` already owns the CPU governor as part of
  setting its profile, so writing to both would just make two things
  fight over the same setting (the same reason clock-lock was left to
  LACT - see above).
- `SystemController.qml`'s free-text "custom units" setting is filtered
  to characters valid in a systemd unit name before being used in any
  command, since it is interpolated into a plain command string rather
  than passed through `gpu-boost-helper.sh`'s stricter validation.
