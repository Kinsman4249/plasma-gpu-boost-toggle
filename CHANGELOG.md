# Changelog

## v1.0.2

This release adds GPU-specific power limit validation to prevent invalid wattage values.

The power limit validation now reads the actual GPU's power.min_limit and power.max_limit from nvidia-smi instead of using a hardcoded 50-500 watt range. This ensures that cards with power envelopes outside the arbitrary default band are handled correctly. The gpu-boost-helper.sh script now validates that requested wattage values fall within the GPU's actual supported range before applying persistence mode settings.

The ConfigGeneral.qml page has been updated to query three power values (min_limit, limit, max_limit) instead of two, and the SpinBox ranges are now dynamically sized based on the GPU's actual enforceable power range. This prevents users from entering values that their specific GPU cannot support.

The version stamp has been bumped to 2026-07-25.2 in both main.qml and ConfigGeneral.qml to reflect these changes.

## v1.0.3

This release fixes polkit policy installation on ostree-based systems (Bazzite, Silverblue) and improves the build workflow.

The install.sh script previously attempted to write the polkit policy to /usr/share/polkit-1/actions, which fails on ostree-based systems because /usr is read-only. The script now installs the policy to /usr/local/share/polkit-1/actions instead, which is writable on ostree systems and works identically on traditional distros. The kpackagetool6 check has been removed since plasmoid installation is now handled separately via the new build script.

A new build-plasmoid.sh script has been added to package the plasmoid directory into a gpu-boost-toggle.plasmoid zip file. This allows users to build and install the widget without re-running install.sh, enabling independent updates of the widget itself. The install.sh instructions have been updated to reflect this new workflow.

A new .gitignore entry has been added to exclude *.plasmoid files from version control, keeping the repository clean of build artifacts.
