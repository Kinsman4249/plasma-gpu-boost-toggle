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
Kirigami.FormLayout {
	id: page

	property alias cfg_defaultWatts: defaultWattsField.value
	property alias cfg_boostWatts: boostWattsField.value
	property alias cfg_debugLogging: debugLoggingCheck.checked

	// Build/version stamp, only shown when debug logging is on, so it is
	// easy to tell which build a bug report came from. Bump the date
	// suffix (YYYY-MM-DD.N) whenever this plasmoid is changed.
	readonly property string versionStamp: "gpu-boost-toggle 2026-07-25.1"

	// Unprivileged DataSource used only to read power.limit / power.max_limit
	// from nvidia-smi so we can suggest starting values. This never touches
	// root and is separate from the pkexec calls the main widget makes.
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
			// Expected line shape: "150.00 W, 350.00 W"
			const parts = stdout.split(",")
			if (parts.length < 2) {
				queryStatusLabel.text = i18n("Unexpected nvidia-smi output. Enter values manually.")
				return
			}
			const current = parseFloat(parts[0])
			const max = parseFloat(parts[1])
			if (isNaN(current) || isNaN(max)) {
				queryStatusLabel.text = i18n("Unexpected nvidia-smi output. Enter values manually.")
				return
			}
			if (defaultWattsField.value === 0) {
				defaultWattsField.value = Math.round(current)
			}
			if (boostWattsField.value === 0) {
				boostWattsField.value = Math.round(max)
			}
			queryStatusLabel.text = i18n("Suggested values filled in below. Review before saving.")
		}
		function exec(cmd) {
			connectSource(cmd)
		}
	}

	function queryGpu() {
		queryStatusLabel.text = i18n("Querying nvidia-smi...")
		queryExecutable.exec("nvidia-smi --query-gpu=power.limit,power.max_limit --format=csv,noheader")
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
	}

	QQC2.Label {
		Kirigami.FormData.isSection: true
		text: i18n("Debugging")
	}

	QQC2.CheckBox {
		id: debugLoggingCheck
		Kirigami.FormData.label: i18n("Debug logging:")
		text: i18n("Print debug messages to the console")
	}

	QQC2.Label {
		Kirigami.FormData.label: ""
		visible: cfg_debugLogging
		text: page.versionStamp
		opacity: 0.7
	}
}
