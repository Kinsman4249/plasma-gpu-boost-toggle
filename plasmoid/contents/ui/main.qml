import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

// GPU Boost Toggle
//
// A panel button that flips an NVIDIA GPU between two power-limit
// profiles: OFF (default watts, persistence mode off) and BOOST (higher
// watts, persistence mode on). It never assumes the last-clicked state is
// the real state: it polls "nvidia-smi" on a timer and on load, so a
// change made from a terminal is picked up too. Root-only work (actually
// changing the power limit) is done through pkexec + a helper script, see
// gpu-boost-helper.sh; this QML file never calls sudo/pkexec-protected
// commands directly with hardcoded watt numbers.
PlasmoidItem {
	id: root

	// Bumped whenever this file (or its config page) changes in a way
	// worth mentioning in a bug report. Only surfaced when debug logging
	// is on, see contents/ui/config/ConfigGeneral.qml.
	readonly property string versionStamp: "gpu-boost-toggle 2026-07-26.2"

	readonly property int defaultWatts: Plasmoid.configuration.defaultWatts
	readonly property int boostWatts: Plasmoid.configuration.boostWatts
	readonly property bool debugLogging: Plasmoid.configuration.debugLogging
	readonly property bool configured: defaultWatts > 0 && boostWatts > 0

	// Reflects the GPU's actual current state, as last learned from
	// polling. This is intentionally not saved to config: the widget must
	// always start at OFF after a reboot (the GPU itself resets to its
	// default power limit and persistence-off, so a fresh poll will agree).
	property bool boosted: false
	property bool busy: false
	property bool pollFailed: false

	// These two must be icon-theme names, not Qt.resolvedUrl() file
	// paths: Kirigami.Icon (below) rendered a raw file:// source as a
	// blank/invisible icon in the panel on this Plasma build, even though
	// the same source loaded fine in notifications and the widget
	// explorer. install.sh installs these into
	// ~/.local/share/icons/hicolor/scalable/apps/ so the theme name
	// resolves.
	Plasmoid.icon: !configured ? "dialog-warning"
		: busy ? "view-refresh"
		: boosted ? "com.kinsman4249.gpuboosttoggle-on"
		: "com.kinsman4249.gpuboosttoggle-off"

	toolTipMainText: i18n("GPU Boost Toggle")
	toolTipSubText: {
		if (!configured) {
			return i18n("Not configured. Right-click > Configure to set watt values.")
		}
		if (pollFailed) {
			return i18n("Could not read GPU state. Is nvidia-smi installed?")
		}
		if (busy) {
			return i18n("Applying change...")
		}
		return boosted
			? i18n("BOOST active (%1 W)", boostWatts)
			: i18n("OFF (%1 W)", defaultWatts)
	}

	function log(msg) {
		// User explicitly chose console-only debug output (no on-disk log
		// file), so this stays a plain console.log gated on the toggle.
		if (debugLogging) {
			console.log("[" + versionStamp + "] " + msg)
		}
	}

	// Single DataSource reused for both the unprivileged status poll and
	// the pkexec-protected on/off calls. Commands run one at a time
	// (guarded by "busy") so onNewData never has to juggle overlapping
	// requests.
	Plasma5Support.DataSource {
		id: executable
		engine: "executable"
		connectedSources: []
		onNewData: (sourceName, data) => {
			disconnectSource(sourceName)
			const exitCode = data["exit code"]
			const stdout = (data["stdout"] || "").toString()
			const stderr = (data["stderr"] || "").toString()
			root.handleResult(sourceName, exitCode, stdout, stderr)
		}
		function exec(cmd) {
			connectSource(cmd)
		}
	}

	// enforced.power.limit (not power.limit) because power.limit reports
	// "[N/A]" until nvidia-smi -pl has been explicitly run at least once
	// since boot on some cards; enforced.power.limit always reflects the
	// power ceiling actually in effect right now.
	readonly property string statusCmd:
		"nvidia-smi --query-gpu=enforced.power.limit,persistence_mode --format=csv,noheader"

	function pollStatus() {
		root.log("polling GPU status")
		executable.exec(statusCmd)
	}

	// Separate, one-shot DataSource for the first-run auto-configure query
	// below, kept apart from "executable" so it can't collide with a
	// status poll or toggle request that happens to be in flight.
	Plasma5Support.DataSource {
		id: autoConfigure
		engine: "executable"
		connectedSources: []
		onNewData: (sourceName, data) => {
			disconnectSource(sourceName)
			const exitCode = data["exit code"]
			const stdout = (data["stdout"] || "").toString().trim()
			if (exitCode !== 0 || stdout.length === 0) {
				root.log("auto-configure: could not query nvidia-smi, leaving unconfigured")
				return
			}
			// Expected line shape: "1.00 W, 125.00 W, 140.00 W"
			const parts = stdout.split(",")
			if (parts.length < 3) {
				root.log("auto-configure: unexpected nvidia-smi output: " + stdout)
				return
			}
			const min = parseFloat(parts[0])
			const def = parseFloat(parts[1])
			const max = parseFloat(parts[2])
			if (isNaN(min) || isNaN(def) || isNaN(max)) {
				root.log("auto-configure: unexpected nvidia-smi output: " + stdout)
				return
			}
			Plasmoid.configuration.defaultWatts = Math.round(def)
			Plasmoid.configuration.boostWatts = Math.round(max)
			root.log("auto-configure: set defaultWatts=" + Plasmoid.configuration.defaultWatts
				+ " boostWatts=" + Plasmoid.configuration.boostWatts)
		}
		function exec(cmd) {
			connectSource(cmd)
		}
	}

	// Runs once, the first time this widget instance loads with no watt
	// values set yet, so it works the moment it is dragged onto a panel
	// and never requires opening the settings dialog first. Uses
	// power.default_limit (not power.limit, see statusCmd above) for the
	// same [N/A]-until-first-set reason.
	Component.onCompleted: {
		if (!configured) {
			root.log("not configured yet, auto-querying nvidia-smi for suggested watt values")
			autoConfigure.exec("nvidia-smi --query-gpu=power.min_limit,power.default_limit,power.max_limit --format=csv,noheader")
		}
	}

	function toggle() {
		if (!configured || busy) {
			return
		}
		busy = true
		if (boosted) {
			root.log("requesting OFF (" + defaultWatts + " W)")
			executable.exec("pkexec /usr/local/bin/gpu-boost-helper.sh off " + defaultWatts)
		} else {
			root.log("requesting BOOST (" + boostWatts + " W)")
			executable.exec("pkexec /usr/local/bin/gpu-boost-helper.sh on " + boostWatts)
		}
	}

	function handleResult(cmd, exitCode, stdout, stderr) {
		if (cmd === statusCmd) {
			parseStatus(exitCode, stdout, stderr)
			return
		}
		// Anything else was an on/off request via the helper script.
		busy = false
		if (exitCode !== 0) {
			root.log("toggle command failed (exit " + exitCode + "): " + stderr)
		}
		// Do not assume success (the user may have cancelled the polkit
		// prompt). Re-poll so the button always reflects the real GPU
		// state, never just the last thing we asked for.
		pollStatus()
	}

	function parseStatus(exitCode, stdout, stderr) {
		if (exitCode !== 0 || stdout.trim().length === 0) {
			pollFailed = true
			root.log("status poll failed (exit " + exitCode + "): " + stderr)
			return
		}
		// Expected line shape: "150.00 W, Disabled" or "350.00 W, Enabled"
		const parts = stdout.split(",")
		if (parts.length < 2) {
			pollFailed = true
			root.log("unexpected status output: " + stdout)
			return
		}
		const currentWatts = parseFloat(parts[0])
		const persistenceOn = parts[1].toLowerCase().indexOf("enabled") !== -1
		if (isNaN(currentWatts)) {
			pollFailed = true
			root.log("unexpected status output: " + stdout)
			return
		}
		pollFailed = false
		// Treat "close to the configured boost wattage, with persistence
		// on" as boosted. nvidia-smi reports watts with decimals while the
		// configured value is an integer, so allow a small tolerance.
		root.boosted = configured
			&& persistenceOn
			&& Math.abs(currentWatts - boostWatts) < 1.0
		root.log("status: " + currentWatts + " W, persistence " + (persistenceOn ? "on" : "off")
			+ " -> boosted=" + root.boosted)
	}

	Timer {
		id: pollTimer
		interval: 7000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: root.pollStatus()
	}

	compactRepresentation: MouseArea {
		id: compactRoot
		acceptedButtons: Qt.LeftButton
		onClicked: root.toggle()

		Layout.minimumWidth: Kirigami.Units.iconSizes.small
		Layout.minimumHeight: Kirigami.Units.iconSizes.small

		Kirigami.Icon {
			anchors.fill: parent
			source: Plasmoid.icon
		}
	}
}
