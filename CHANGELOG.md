# Changelog

## v1.1.1

- Added `BoostIcon.qml` for special icon rendering when GPU power axis is
  unsupported but other axes (services, power-profile) are boosted. Uses
  a flame icon as a mask (recoloured to panel text colour) with a bolt
  icon drawn on top in fixed yellow.
- Added `com.kinsman4249.gpuboosttoggle-bolt.svg` icon for the bolt shape
  in the partial boost rendering.
- Ostree distro support (Bazzite, Silverblue): `install.sh` now uses
  `readlink -f` to get the canonical path of the helper script, and the
  polkit policy uses a `@HELPER_REAL_PATH@` placeholder that gets
  replaced. This ensures `pkexec` matches the action id correctly and
  the no-password rule applies on systems where `/usr/local` is a symlink.
- Version stamp bumped to 2026-07-26.6 in `main.qml`.

## v1.1.0

This release adds two optional advanced axes to the widget: background services management and power profile switching. The Services axis allows pausing user-level background services (Baloo file indexer, Akonadi PIM/mail sync, and any custom units) while in BOOST mode, and restoring them when returning to OFF. The Power Profile axis switches to the `performance` power-profiles-daemon profile while boosted and restores the previous profile afterward. Both axes operate without requiring root privileges, using session-scoped tools (balooctl/balooctl6, akonadictl, powerprofilesctl, systemctl --user) that authorize via polkit without a password prompt. The uninstall script has been updated with best-effort restore logic for these axes, reverting services and power profile to their ordinary defaults when returning to OFF. The README documentation has been expanded to describe the multi-axis architecture, partial support scenarios (e.g., laptop GPUs that reject power-limit changes), and graceful degradation when optional tools are unavailable.

## v1.0.5

This release fixes critical icon loading issues on Plasma 6 and improves first-run user experience by auto-querying GPU power limits.

The icon system has been completely rewritten to work with Plasma 6's icon theme resolution. Previously, the widget used Qt.resolvedUrl() to reference bundled SVG files, but Plasma's widget explorer and panel icon rendering use QIcon::fromTheme() which only accepts icon theme names, not file paths. The install.sh script now installs the custom icon to ~/.local/share/icons/hicolor/scalable/apps/ so it can be referenced by theme name. The config.qml, metadata.json, and main.qml files have been updated to use "com.kinsman4249.gpuboosttoggle" and "com.kinsman4249.gpuboosttoggle-on/off" as icon identifiers. The icon files have been reorganized into a dedicated icons/ directory with proper naming.

The power limit queries have been updated to use enforced.power.limit instead of power.limit, and power.default_limit instead of power.limit. This prevents the [N/A] value that appears on some cards until nvidia-smi -pl has been explicitly run at least once since boot. The statusCmd now queries enforced.power.limit and persistence_mode, and the auto-configure DataSource queries power.min_limit, power.default_limit, and power.max_limit for first-run initialization.

A new auto-configure DataSource has been added that runs once when the widget first loads with no configured watt values. This automatically queries nvidia-smi for suggested defaultWatts and boostWatts values, so the widget works immediately after being dragged onto a panel without requiring the user to open the settings dialog first. The DataSource uses a separate executable engine to avoid collision with status polls or toggle requests.

The version stamp has been bumped to 2026-07-26.2 in both main.qml and ConfigGeneral.qml to reflect these changes.
