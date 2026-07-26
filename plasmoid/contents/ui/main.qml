import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

// GPU Boost Toggle
//
// A panel button that flips a "boost" state on and off across up to three
// independent axes:
//   - Power: an NVIDIA GPU's power-limit + persistence-mode profile,
//     handled inline below via nvidia-smi/gpu-boost-helper.sh.
//   - Services: pausing user-level background services (Baloo, Akonadi,
//     etc.), handled by SystemController.qml.
//   - Power profile: switching to the "performance" power-profiles-daemon
//     profile, also handled by SystemController.qml.
// Each axis is probed and toggled independently, so a laptop GPU that
// rejects the power-limit change (common - see powerUnsupported below)
// still gets the benefit of whichever other axes this system supports,
// instead of the whole widget considering itself unsupported.
//
// It never assumes the last-clicked state is the real state: it polls
// "nvidia-smi" on a timer and on load, so a change made from a terminal
// is picked up too. Root-only work (actually changing the power limit) is
// done through pkexec + a helper script, see gpu-boost-helper.sh; this
// QML file never calls sudo/pkexec-protected commands directly with
// hardcoded watt numbers. The services/power-profile axes never need
// root at all - see SystemController.qml.
PlasmoidItem {
	id: root

	// Bumped whenever this file (or its config pages) changes in a way
	// worth mentioning in a bug report. Only surfaced when debug logging
	// is on, see contents/ui/config/ConfigGeneral.qml.
	readonly property string versionStamp: "gpu-boost-toggle 2026-07-26.4"

	readonly property int defaultWatts: Plasmoid.configuration.defaultWatts
	readonly property int boostWatts: Plasmoid.configuration.boostWatts
	readonly property bool debugLogging: Plasmoid.configuration.debugLogging
	readonly property bool configured: defaultWatts > 0 && boostWatts > 0

	// Reflects the GPU's actual current power state, as last learned from
	// polling. This is intentionally not saved to config: the widget must
	// always start at OFF after a reboot (the GPU itself resets to its
	// default power limit and persistence-off, so a fresh poll will agree).
	property bool powerBoosted: false
	property bool busy: false
	property bool pollFailed: false

	// Set when the helper script's own verification catches the GPU
	// silently refusing the requested power limit (nvidia-smi -pl exits 0
	// even when the driver rejects the change outright - common on
	// laptop GPUs). Cleared the moment a toggle attempt exits cleanly, so
	// it never sticks around once the GPU does accept a change.
	property bool powerUnsupported: false

	// Owns the services and power-profile axes. Its inputs are wired
	// directly from this widget's config; its outputs (servicesIdled,
	// powerProfileMaxed, powerProfileUnsupported, busy) are read below to
	// build the combined boosted/tooltip state.
	property SystemController systemController: SystemController {
		idlingEnabled: Plasmoid.configuration.serviceIdlingEnabled
		idleBaloo: Plasmoid.configuration.idleBaloo
		idleAkonadi: Plasmoid.configuration.idleAkonadi
		idleKalarm: Plasmoid.configuration.idleKalarm
		customIdleUnits: Plasmoid.configuration.customIdleUnits
		profileEnabled: Plasmoid.configuration.powerProfileEnabled
		debugLogging: root.debugLogging
		onLogMessage: (msg) => root.log(msg)
	}

	// True the moment ANY enabled axis is currently boosted/idled/maxed -
	// drives the on/off icon and isMask.
	readonly property bool anyBoosted: powerBoosted || systemController.servicesIdled || systemController.powerProfileMaxed

	// True only once every ENABLED axis that also turns out to be
	// supported on this system is actually in its boosted state. An axis
	// that is disabled in settings, or unsupported on this hardware,
	// doesn't hold this back - that is the whole point of "partial mode".
	readonly property bool fullyBoosted:
		(powerUnsupported || powerBoosted)
		&& (!systemController.idlingEnabled || systemController.servicesIdled)
		&& (systemController.powerProfileUnsupported || !systemController.profileEnabled || systemController.powerProfileMaxed)

	// True only when literally nothing enabled is supported here - this
	// is the "the whole widget is useless on this system" case, distinct
	// from powerUnsupported alone (which today's partial mode treats as
	// just one axis being unavailable).
	readonly property bool nothingSupported:
		powerUnsupported
		&& !systemController.idlingEnabled
		&& (systemController.powerProfileUnsupported || !systemController.profileEnabled)

	readonly property bool overallBusy: busy || systemController.busy

	// These two must be icon-theme names, not Qt.resolvedUrl() file
	// paths: Kirigami.Icon (below) rendered a raw file:// source as a
	// blank/invisible icon in the panel on this Plasma build, even though
	// the same source loaded fine in notifications and the widget
	// explorer. install.sh installs these into
	// ~/.local/share/icons/hicolor/scalable/apps/ so the theme name
	// resolves.
	Plasmoid.icon: !configured ? "dialog-warning"
		: nothingSupported ? "dialog-error"
		: overallBusy ? "view-refresh"
		: anyBoosted ? "com.kinsman4249.gpuboosttoggle-on"
		: "com.kinsman4249.gpuboosttoggle-off"

	toolTipMainText: i18n("GPU Boost Toggle")
	toolTipSubText: {
		if (!configured) {
			return i18n("Not configured. Right-click > Configure to set watt values.")
		}
		if (nothingSupported) {
			return i18n("This system doesn't support any of the configured boost options.")
		}
		if (pollFailed) {
			return i18n("Could not read GPU state. Is nvidia-smi installed?")
		}
		if (overallBusy) {
			return i18n("Applying change...")
		}
		const lines = []
		if (anyBoosted) {
			lines.push(fullyBoosted ? i18n("BOOST") : i18n("BOOST (partial - see below)"))
		} else {
			lines.push(i18n("OFF"))
		}
		lines.push(powerUnsupported
			? i18n("Power: unsupported on this GPU")
			: (powerBoosted ? i18n("Power: BOOST (%1 W)", boostWatts) : i18n("Power: OFF (%1 W)", defaultWatts)))
		if (systemController.idlingEnabled) {
			lines.push(systemController.servicesIdled ? i18n("Services: idled") : i18n("Services: normal"))
		}
		if (systemController.profileEnabled) {
			lines.push(systemController.powerProfileUnsupported
				? i18n("Power profile: unsupported")
				: (systemController.powerProfileMaxed ? i18n("Power profile: performance") : i18n("Power profile: normal")))
		}
		return lines.join("\n")
	}

	function log(msg) {
		// User explicitly chose console-only debug output (no on-disk log
		// file), so this stays a console message gated on the toggle.
		//
		// console.warn, not console.log: QML's console.log maps to qDebug,
		// which plasmashell filters out of the journal by default, so
		// enabling debug logging appeared to do nothing at all. console.warn
		// maps to qWarning, which is shown.
		if (debugLogging) {
			console.warn("[" + versionStamp + "] " + msg)
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
		// Cheap, one-shot capability check so the power-profile axis knows
		// whether it's supported before the user ever opens settings -
		// never repeated on the polling timer.
		systemController.probePowerProfile()
	}

	function toggle() {
		if (!configured || overallBusy) {
			return
		}
		const goingUp = !anyBoosted
		busy = true
		if (goingUp) {
			root.log("requesting BOOST (" + boostWatts + " W)")
			executable.exec("pkexec /usr/local/bin/gpu-boost-helper.sh on " + boostWatts)
			systemController.activate()
		} else {
			root.log("requesting OFF (" + defaultWatts + " W)")
			executable.exec("pkexec /usr/local/bin/gpu-boost-helper.sh off " + defaultWatts)
			systemController.deactivate()
		}
	}

	function handleResult(cmd, exitCode, stdout, stderr) {
		if (cmd === statusCmd) {
			parseStatus(exitCode, stdout, stderr)
			return
		}
		// Anything else was an on/off request via the helper script.
		busy = false
		// Exit code 3 specifically is the helper script's own
		// post-change verification catching the GPU silently rejecting
		// the power limit (see gpu-boost-helper.sh); other nonzero codes
		// are ordinary failures (cancelled polkit prompt, bad watts,
		// nvidia-smi missing, etc), not this GPU's own capability.
		powerUnsupported = (exitCode === 3)
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
		root.powerBoosted = configured
			&& persistenceOn
			&& Math.abs(currentWatts - boostWatts) < 1.0
		root.log("status: " + currentWatts + " W, persistence " + (persistenceOn ? "on" : "off")
			+ " -> powerBoosted=" + root.powerBoosted)
	}

	Timer {
		id: pollTimer
		interval: 7000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: root.pollStatus()
	}

	// This widget is a plain click-to-toggle button: it has no popup and
	// no full representation. Plasma decides between the compact and full
	// representation by comparing the space it has to switchWidth/
	// switchHeight, and with those left at their defaults it never picked
	// the compact one - it instantiated an empty full representation, so
	// the applet drew nothing while still occupying a clickable panel
	// slot. Setting both (as KDE's own keyboardindicator applet does)
	// makes the panel-sized applet resolve to the compact representation.
	switchWidth: Kirigami.Units.gridUnit * 12
	switchHeight: Kirigami.Units.gridUnit * 12
	preferredRepresentation: compactRepresentation

	// Shown when the widget is placed on the desktop rather than a panel
	// (where it is too big for the compact representation). Plasma's
	// representation switching also expects this to exist: with only a
	// compact representation defined, it created neither.
	fullRepresentation: Item {
		implicitWidth: Kirigami.Units.gridUnit * 10
		implicitHeight: Kirigami.Units.gridUnit * 6

		MouseArea {
			anchors.fill: parent
			onClicked: root.toggle()

			Column {
				anchors.centerIn: parent
				spacing: Kirigami.Units.smallSpacing

				Kirigami.Icon {
					anchors.horizontalCenter: parent.horizontalCenter
					width: Kirigami.Units.iconSizes.large
					height: width
					source: Plasmoid.icon
				}

				Text {
					anchors.horizontalCenter: parent.horizontalCenter
					text: root.toolTipSubText
					color: Kirigami.Theme.textColor
					wrapMode: Text.WordWrap
					horizontalAlignment: Text.AlignHCenter
					width: Kirigami.Units.gridUnit * 9
				}
			}
		}
	}

	compactRepresentation: MouseArea {
		id: compactRoot
		acceptedButtons: Qt.LeftButton
		hoverEnabled: true
		onClicked: root.toggle()

		// Layout.minimumWidth/Height (attached properties) are only read
		// by an actual Layout container, which the panel's compact-
		// representation slot is not - they were silently ignored here,
		// leaving this MouseArea at its implicit 0x0 size. That made the
		// Kirigami.Icon below (anchors.fill: parent) invisible even
		// though the panel still reserved a clickable slot for it, sized
		// from Plasmoid's own defaults. implicitWidth/implicitHeight are
		// read directly by PlasmoidItem's compact representation, so use
		// those instead, matching how KDE's own kdeconnect applet sizes
		// its equivalent icon.
		implicitWidth: Kirigami.Units.iconSizes.small
		implicitHeight: Kirigami.Units.iconSizes.small

		Kirigami.Icon {
			anchors.fill: parent
			source: Plasmoid.icon
			active: compactRoot.containsMouse

			// The OFF artwork is a flat dark-grey flame, which is nearly
			// invisible on a dark panel. Drawing it as a mask makes Plasma
			// tint it with the panel's own text colour, so it stays legible
			// on light and dark panels alike. The BOOST artwork is
			// deliberately full-colour (and dialog-warning/view-refresh are
			// already theme icons), so those must not be masked.
			isMask: root.configured && !root.overallBusy && !root.anyBoosted
		}
	}
}
