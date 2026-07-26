import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

// Settings page for the GPU Boost Toggle widget.
// The "cfg_" prefixed property aliases below are the standard Plasma
// KConfigXT convention: a property named cfg_<entryName> is automatically
// read from and written back to the matching <entry name="entryName"> in
// contents/config/main.xml when the user opens/saves this page.
//
// Root is Kirigami.ScrollablePage - see ConfigAdvanced.qml's header comment
// for why (a plain FormLayout has no scrolling of its own, and wrapping it
// in a manual QQC2.ScrollView broke it outright).
Kirigami.ScrollablePage {
	id: root

	horizontalScrollBarPolicy: QQC2.ScrollBar.AlwaysOff

	property alias cfg_defaultWatts: defaultWattsField.value
	property alias cfg_boostWatts: boostWattsField.value
	property alias cfg_debugLogging: debugLoggingCheck.checked

	Kirigami.FormLayout {
		id: page

		// Build/version stamp, only shown when debug logging is on, so it is
		// easy to tell which build a bug report came from. Bump the date
		// suffix (YYYY-MM-DD.N) whenever this plasmoid is changed.
		readonly property string versionStamp: "gpu-boost-toggle 2026-07-26.8"

		// Unprivileged DataSource used only to read power.min_limit /
		// power.default_limit / power.max_limit from nvidia-smi, both to
		// suggest starting values and to size the SpinBox ranges below to
		// what THIS card actually supports. This never touches root and is
		// separate from the pkexec calls the main widget makes.
		//
		// power.default_limit, not power.limit: power.limit reports "[N/A]"
		// until nvidia-smi -pl has been explicitly run at least once since
		// boot on some cards (e.g. laptop GPUs), which made this query fail
		// with "Unexpected nvidia-smi output" on a freshly booted machine.
		// power.default_limit is always a real number.
		Plasma5Support.DataSource {
			id: queryExecutable
			engine: "executable"
			connectedSources: []
			onNewData: (sourceName, data) => {
				disconnectSource(sourceName)
				const exitCode = data["exit code"]
				const stdout = (data["stdout"] || "").toString().trim()
				if (exitCode !== 0 || stdout.length === 0) {
					queryStatusLabel.text = i18n("Could not query nvidia-smi. Enter values manually.")
					return
				}
				// Expected line shape: "100.00 W, 150.00 W, 350.00 W"
				const parts = stdout.split(",")
				if (parts.length < 3) {
					queryStatusLabel.text = i18n("Unexpected nvidia-smi output. Enter values manually.")
					return
				}
				const min = parseFloat(parts[0])
				const current = parseFloat(parts[1])
				const max = parseFloat(parts[2])
				if (isNaN(min) || isNaN(current) || isNaN(max)) {
					queryStatusLabel.text = i18n("Unexpected nvidia-smi output. Enter values manually.")
					return
				}
				// Size the fields to this GPU's real enforceable range instead
				// of a guessed-at band, so a card whose envelope falls outside
				// some fixed default isn't clamped to the wrong values.
				defaultWattsField.from = Math.floor(min)
				defaultWattsField.to = Math.ceil(max)
				boostWattsField.from = Math.floor(min)
				boostWattsField.to = Math.ceil(max)
				if (defaultWattsField.value === 0) {
					defaultWattsField.value = Math.round(current)
				}
				if (boostWattsField.value === 0) {
					boostWattsField.value = Math.round(max)
				}
				queryStatusLabel.text = i18n("Suggested values filled in below (range: %1-%2 W for this GPU). Review before saving.",
					Math.floor(min), Math.ceil(max))
			}
			function exec(cmd) {
				connectSource(cmd)
			}
		}

		function queryGpu() {
			queryStatusLabel.text = i18n("Querying nvidia-smi...")
			queryExecutable.exec("nvidia-smi --query-gpu=power.min_limit,power.default_limit,power.max_limit --format=csv,noheader")
		}

		// On first open, if nothing has been configured yet, query automatically.
		Component.onCompleted: {
			if (cfg_defaultWatts === 0 && cfg_boostWatts === 0) {
				queryGpu()
			}
		}

		QQC2.Label {
			Kirigami.FormData.isSection: true
			text: i18n("Power limits")
		}

		// from/to below are only a fallback shown before the GPU query below
		// completes (or if it fails); queryGpu() replaces them with this card's
		// real power.min_limit/power.max_limit as soon as it succeeds.
		QQC2.SpinBox {
			id: defaultWattsField
			Kirigami.FormData.label: i18n("Default (OFF) watts:")
			from: 50
			to: 500
			stepSize: 1
		}

		QQC2.SpinBox {
			id: boostWattsField
			Kirigami.FormData.label: i18n("Boost watts:")
			from: 50
			to: 500
			stepSize: 1
		}

		RowLayout {
			Kirigami.FormData.label: ""
			QQC2.Button {
				text: i18n("Query GPU for suggested values")
				icon.name: "view-refresh"
				onClicked: page.queryGpu()
			}
		}

		QQC2.Label {
			id: queryStatusLabel
			Kirigami.FormData.label: ""
			wrapMode: Text.WordWrap
			opacity: 0.8
			Layout.fillWidth: true
		}

		QQC2.Label {
			Kirigami.FormData.isSection: true
			text: i18n("Debugging")
		}

		QQC2.CheckBox {
			id: debugLoggingCheck
			Kirigami.FormData.label: i18n("Debug logging:")
			text: i18n("Print debug messages to the console")
			Layout.fillWidth: true
		}

		QQC2.Label {
			Kirigami.FormData.label: ""
			visible: cfg_debugLogging
			text: page.versionStamp
			opacity: 0.7
		}
	}
}
