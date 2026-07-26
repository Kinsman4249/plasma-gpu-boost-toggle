# Changelog

## v1.0.1

This release adds GPU-specific power limit validation to prevent invalid wattage values.

The power limit validation now reads the actual GPU's power.min_limit and power.max_limit from nvidia-smi instead of using a hardcoded 50-500 watt range. This ensures that cards with power envelopes outside the arbitrary default band are handled correctly. The gpu-boost-helper.sh script now validates that requested wattage values fall within the GPU's actual supported range before applying persistence mode settings.

The ConfigGeneral.qml page has been updated to query three power values (min_limit, limit, max_limit) instead of two, and the SpinBox ranges are now dynamically sized based on the GPU's actual enforceable power range. This prevents users from entering values that their specific GPU cannot support.

The version stamp has been bumped to 2026-07-25.2 in both main.qml and ConfigGeneral.qml to reflect these changes.
