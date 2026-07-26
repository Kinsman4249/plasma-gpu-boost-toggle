import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

// ChromeController
//
// Owns the "Chrome" boost axis: while BOOST is active, deprioritize
// whatever browser processes match a user-configured pattern (lower CPU
// nice value, idle I/O class) so a running game gets first call on the
// CPU/disk, and make a one-shot attempt to push that browser's idle
// memory out to swap/cache via cgroup v2's memory.reclaim. Tracked
// independently from the GPU/services/power-profile axes in main.qml and
// SystemController.qml, for the same reason those are independent: a
// system where this axis turns out to be unsupported still gets whatever
// other axes it does support.
//
// No root needed for any of this - see chrome-boost-helper.sh's own
// header comment for why. All the actual logic lives in that script;
// this file is thin plumbing around it (build the command, run it
// through the same one-process-at-a-time DataSource discipline
// SystemController.qml uses, parse its plain-text stdout).
QtObject {
	id: root

	// --- Inputs, bound from main.qml's Plasmoid.configuration ---
	property bool enabled: false
	property string processPattern: ""
	property int niceValue: 15
	property bool debugLogging: false

	// --- Outputs, read by main.qml ---
	// True once activate() has actually matched and reniced at least one
	// process.
	property bool chromeDeprioritized: false
	// True once activate()'s one-shot memory push actually found a
	// dedicated cgroup to reclaim from. Purely informational (shown in
	// the tooltip) - deactivate() does not need to undo this, since
	// letting the kernel bring pages back in as the browser is used again
	// is the entire point.
	property bool chromeMemoryReclaimed: false
	// Set once at startup (see probe() below) if the helper script is
	// missing or pgrep isn't available. Cleared only by a fresh probe.
	property bool chromeUnsupported: false
	property bool probed: false
	// True while an activate()/deactivate() call is running.
	property bool busy: false

	signal logMessage(string msg)
	function log(msg) {
		if (debugLogging) {
			logMessage(msg)
		}
	}

	// Installed by install.sh with no root needed (unlike
	// gpu-boost-helper.sh, this axis never touches anything requiring
	// elevated rights, so it lives under the user's own home rather than
	// /usr/local/bin). "$HOME" is expanded by the shell the executable
	// engine runs this through, not by QML.
	readonly property string helperPath: "$HOME/.local/share/plasma-gpu-boost-toggle/chrome-boost-helper.sh"

	// Same defense-in-depth validation chrome-boost-helper.sh itself
	// applies: reject anything outside this charset before ever building
	// a command string, rather than relying solely on the script's own
	// check.
	readonly property bool patternValid: /^[A-Za-z0-9._|-]+$/.test(processPattern)

	property Plasma5Support.DataSource execSource: Plasma5Support.DataSource {
		engine: "executable"
		connectedSources: []
		onNewData: (sourceName, data) => {
			disconnectSource(sourceName)
			const exitCode = data["exit code"]
			const stdout = (data["stdout"] || "").toString()
			const stderr = (data["stderr"] || "").toString()
			const cb = root.currentStepCallback
			root.currentStepCallback = null
			if (cb) {
				cb(exitCode, stdout, stderr)
			}
		}
		function exec(cmd) {
			connectSource(cmd)
		}
	}

	property var currentStepCallback: null
	function runCommand(cmd, callback) {
		root.currentStepCallback = callback
		root.log("ChromeController: running: " + cmd)
		execSource.exec(cmd)
	}

	// One-shot capability probe, called once from main.qml at startup -
	// mirrors SystemController.probePowerProfile(). Not repeated on any
	// timer: whether the helper script and pgrep exist does not change
	// while the widget is running.
	function probe() {
		runCommand("sh -c \"[ -x " + helperPath + " ] && command -v pgrep >/dev/null 2>&1\"", (exitCode) => {
			probed = true
			chromeUnsupported = (exitCode !== 0)
			if (chromeUnsupported) {
				root.log("ChromeController: helper script missing or pgrep unavailable")
			}
		})
	}

	function activate() {
		if (busy || !enabled || chromeUnsupported || !patternValid) {
			if (enabled && !patternValid) {
				root.log("ChromeController: processPattern fails validation, skipping: " + processPattern)
			}
			return
		}
		busy = true
		const cmd = helperPath + " on " + niceValue + " '" + processPattern + "'"
		runCommand(cmd, (exitCode, stdout, stderr) => {
			if (exitCode !== 0) {
				root.log("ChromeController: activate failed (exit " + exitCode + "): " + stderr)
				chromeDeprioritized = false
				chromeMemoryReclaimed = false
				busy = false
				return
			}
			chromeDeprioritized = stdout.indexOf("No processes matched") === -1
			chromeMemoryReclaimed = /^reclaimed:/m.test(stdout)
			root.log("ChromeController: " + stdout.trim().split("\n").join(" | "))
			busy = false
		})
	}

	function deactivate() {
		if (busy || !enabled || chromeUnsupported || !patternValid) {
			return
		}
		busy = true
		const cmd = helperPath + " off '" + processPattern + "'"
		runCommand(cmd, (exitCode, stdout, stderr) => {
			if (exitCode !== 0) {
				root.log("ChromeController: deactivate failed (exit " + exitCode + "): " + stderr)
			} else {
				root.log("ChromeController: " + stdout.trim().split("\n").join(" | "))
			}
			chromeDeprioritized = false
			chromeMemoryReclaimed = false
			busy = false
		})
	}
}
