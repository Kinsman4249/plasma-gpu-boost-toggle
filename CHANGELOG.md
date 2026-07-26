# Changelog

## v1.0.5

This release fixes critical icon loading issues on Plasma 6 and improves first-run user experience by auto-querying GPU power limits.

The icon system has been completely rewritten to work with Plasma 6's icon theme resolution. Previously, the widget used Qt.resolvedUrl() to reference bundled SVG files, but Plasma's widget explorer and panel icon rendering use QIcon::fromTheme() which only accepts icon theme names, not file paths. The install.sh script now installs the custom icon to ~/.local/share/icons/hicolor/scalable/apps/ so it can be referenced by theme name. The config.qml, metadata.json, and main.qml files have been updated to use "com.kinsman4249.gpuboosttoggle" and "com.kinsman4249.gpuboosttoggle-on/off" as icon identifiers. The icon files have been reorganized into a dedicated icons/ directory with proper naming.

The power limit queries have been updated to use enforced.power.limit instead of power.limit, and power.default_limit instead of power.limit. This prevents the [N/A] value that appears on some cards until nvidia-smi -pl has been explicitly run at least once since boot. The statusCmd now queries enforced.power.limit and persistence_mode, and the auto-configure DataSource queries power.min_limit, power.default_limit, and power.max_limit for first-run initialization.

A new auto-configure DataSource has been added that runs once when the widget first loads with no configured watt values. This automatically queries nvidia-smi for suggested defaultWatts and boostWatts values, so the widget works immediately after being dragged onto a panel without requiring the user to open the settings dialog first. The DataSource uses a separate executable engine to avoid collision with status polls or toggle requests.

The version stamp has been bumped to 2026-07-26.2 in both main.qml and ConfigGeneral.qml to reflect these changes.
