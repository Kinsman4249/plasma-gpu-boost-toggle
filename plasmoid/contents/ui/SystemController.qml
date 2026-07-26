import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

// SystemController
//
// Owns the two non-GPU "boost" axes: pausing user-level background
// services (Baloo, Akonadi, KAlarm, user-supplied custom units) and
// switching to the "performance" power-profiles-daemon profile. Both are
// toggled alongside the GPU power-limit axis in main.qml, but tracked
// independently, so a GPU that rejects power-limit changes still gets
// these. Neither axis needs root: balooctl/akonadictl run as the current
// user, systemctl --user only ever touches the user's own session bus,
// and power-profiles-daemon authorizes the active local session via
// polkit without a password prompt.
//
// Everything here runs through a single Plasma5Support.DataSource and a
// small step-sequence runner, so at most one external process is ever in
// flight from this controller at a time - the same one-command-at-a-time
// discipline the GPU side already uses for its own DataSource.
QtObject {
	id: root

	// --- Inputs, bound from main.qml's Plasmoid.configuration ---
	property bool idlingEnabled: false
	property bool idleBaloo: true
	property bool idleAkonadi: true
	property bool idleKalarm: false
	property string customIdleUnits: ""
	property bool profileEnabled: false
	property bool debugLogging: false

	// --- Outputs, read by main.qml ---
	// True once activate() has actually paused at least one thing.
	property bool servicesIdled: false
	property bool powerProfileMaxed: false
	// Set the moment powerprofilesctl turns out to be missing, or this
	// system has no "performance" profile to switch to (some platforms
	// only expose balanced/power-saver). Cleared only by a fresh probe.
	property bool powerProfileUnsupported: false
	// True while an activate()/deactivate() sequence is running. main.qml
	// checks this so a click mid-sequence doesn't start a second one.
	property bool busy: false

	// Routed through main.qml's own log() function so all debug output
	// shares one console prefix/versionStamp.
	signal logMessage(string msg)
	function log(msg) {
		if (debugLogging) {
			logMessage(msg)
		}
	}

	// Resolved once, lazily: KDE6 renamed this binary on some distros but
	// not others.
	property string balooBin: ""
	property bool balooBinChecked: false

	// In-memory only - which things THIS controller actually paused, so
	// deactivate() only resumes what it personally stopped. Deliberately
	// not persisted: if Plasma restarts mid-boost this is lost on purpose,
	// so the widget never guesses and restarts something it didn't touch.
	// See README for the honest tradeoff this creates.
	property bool balooWasRunning: false
	property bool akonadiWasRunning: false
	property var customUnitsWasRunning: []

	// Saved power-profiles-daemon profile from just before activate(),
	// e.g. "balanced" or "power-saver" - restored verbatim, never a
	// hardcoded guess, since some systems default to power-saver on
	// battery.
	property string savedPowerProfile: ""
	property var availableProfiles: []

	// Only characters valid in a systemd unit name are kept; anything else
	// in the free-text config field is dropped (with a debug log) rather
	// than passed through to a shell command built as a plain string.
	function parseCustomUnits() {
		return customIdleUnits
			.split(/[\n,]/)
			.map(s => s.trim())
			.filter(s => {
				if (s.length === 0) {
					return false
				}
				if (!/^[A-Za-z0-9_.@:-]+$/.test(s)) {
					root.log("SystemController: ignoring invalid unit name in customIdleUnits: " + s)
					return false
				}
				return true
			})
	}

	function resolveGenericUnits() {
		const units = idleKalarm ? ["kalarm.service"] : []
		return units.concat(parseCustomUnits())
	}

	// --- Single-process-at-a-time execution plumbing ---

	property var currentStepCallback: null

	function runCommand(cmd, callback) {
		root.currentStepCallback = callback
		root.log("SystemController: running: " + cmd)
		execSource.exec(cmd)
	}

	// Runs an array of step(next) functions strictly one after another.
	// Each step must call the "next" function it is given exactly once,
	// whether or not it actually ran a command, so a step that finds
	// nothing to do can just call next() straight away.
	function runSequence(steps, onDone) {
		let i = 0
		function advance() {
			if (i >= steps.length) {
				onDone()
				return
			}
			const fn = steps[i]
			i++
			fn(advance)
		}
		advance()
	}

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

	// --- Baloo ---

	function stepResolveBalooBin(next) {
		if (balooBinChecked) {
			next()
			return
		}
		runCommand("sh -c \"command -v balooctl6 || command -v balooctl\"", (exitCode, stdout) => {
			balooBinChecked = true
			const trimmed = stdout.trim()
			balooBin = (exitCode === 0 && trimmed.length > 0) ? trimmed : ""
			if (!balooBin) {
				root.log("SystemController: no baloo control binary found")
			}
			next()
		})
	}

	function stepSuspendBaloo(next) {
		if (!idleBaloo || !balooBin) {
			next()
			return
		}
		runCommand(balooBin + " status", (exitCode, stdout) => {
			// balooctl prints a human sentence like "Baloo File Indexer is
			// running" / "...is not running" / "...is currently disabled" -
			// there is no machine-readable status flag, so this is a
			// best-effort text match.
			const lower = stdout.toLowerCase()
			balooWasRunning = exitCode === 0
				&& lower.indexOf("running") !== -1
				&& lower.indexOf("not running") === -1
			if (!balooWasRunning) {
				next()
				return
			}
			runCommand(balooBin + " suspend", () => next())
		})
	}

	function stepResumeBaloo(next) {
		if (!balooWasRunning || !balooBin) {
			next()
			return
		}
		runCommand(balooBin + " resume", () => {
			balooWasRunning = false
			next()
		})
	}

	// --- Akonadi ---

	function stepStopAkonadi(next) {
		if (!idleAkonadi) {
			next()
			return
		}
		runCommand("akonadictl status", (exitCode) => {
			// akonadictl status has no stable machine-readable output, but
			// its exit code reliably tracks whether the server is up and
			// reachable, so use that instead of parsing text here.
			akonadiWasRunning = (exitCode === 0)
			if (!akonadiWasRunning) {
				next()
				return
			}
			runCommand("akonadictl stop", () => next())
		})
	}

	function stepStartAkonadi(next) {
		if (!akonadiWasRunning) {
			next()
			return
		}
		runCommand("akonadictl start", () => {
			akonadiWasRunning = false
			next()
		})
	}

	// --- KAlarm + custom systemctl --user units, batched ---

	function stepStopGenericUnits(next) {
		const units = resolveGenericUnits()
		if (units.length === 0) {
			next()
			return
		}
		runCommand("systemctl --user is-active " + units.join(" "), (exitCode, stdout) => {
			const lines = stdout.split("\n")
			const activeUnits = []
			for (let i = 0; i < units.length; i++) {
				if ((lines[i] || "").trim() === "active") {
					activeUnits.push(units[i])
				}
			}
			customUnitsWasRunning = activeUnits
			if (activeUnits.length === 0) {
				next()
				return
			}
			runCommand("systemctl --user stop " + activeUnits.join(" "), () => next())
		})
	}

	function stepStartGenericUnits(next) {
		const units = customUnitsWasRunning
		if (units.length === 0) {
			next()
			return
		}
		runCommand("systemctl --user start " + units.join(" "), () => {
			customUnitsWasRunning = []
			next()
		})
	}

	// --- power-profiles-daemon ---

	// One-shot capability probe, called once from main.qml at startup -
	// not part of the activate()/deactivate() sequence, and never repeated
	// on the polling timer.
	function probePowerProfile() {
		runCommand("powerprofilesctl list", (exitCode, stdout) => {
			if (exitCode !== 0) {
				powerProfileUnsupported = true
				root.log("SystemController: powerprofilesctl not available")
				return
			}
			// Profile header lines look like "* balanced:" (active one
			// marked with "*") or "  performance:" - collect the bare name.
			const names = []
			stdout.split("\n").forEach(line => {
				const m = line.match(/^\s*(?:\*\s*)?([a-z-]+):\s*$/)
				if (m) {
					names.push(m[1])
				}
			})
			availableProfiles = names
			powerProfileUnsupported = names.indexOf("performance") === -1
			root.log("SystemController: available power profiles: " + names.join(", "))
		})
	}

	function stepMaxProfile(next) {
		if (!profileEnabled || powerProfileUnsupported) {
			next()
			return
		}
		runCommand("powerprofilesctl get", (exitCode, stdout) => {
			if (exitCode !== 0) {
				powerProfileUnsupported = true
				next()
				return
			}
			savedPowerProfile = stdout.trim()
			runCommand("powerprofilesctl set performance", (exitCode2) => {
				powerProfileMaxed = (exitCode2 === 0)
				if (exitCode2 !== 0) {
					root.log("SystemController: failed to set performance profile")
				}
				next()
			})
		})
	}

	function stepRestoreProfile(next) {
		if (!powerProfileMaxed || !/^[a-z-]+$/.test(savedPowerProfile)) {
			next()
			return
		}
		runCommand("powerprofilesctl set " + savedPowerProfile, (exitCode) => {
			if (exitCode === 0) {
				powerProfileMaxed = false
			} else {
				root.log("SystemController: failed to restore power profile " + savedPowerProfile)
			}
			next()
		})
	}

	// --- Public entry points, called from main.qml's toggle() ---

	function activate() {
		if (busy) {
			return
		}
		busy = true
		const steps = []
		if (idlingEnabled) {
			steps.push(stepResolveBalooBin)
			steps.push(stepSuspendBaloo)
			steps.push(stepStopAkonadi)
			steps.push(stepStopGenericUnits)
		}
		if (profileEnabled) {
			steps.push(stepMaxProfile)
		}
		runSequence(steps, () => {
			servicesIdled = idlingEnabled
				&& (balooWasRunning || akonadiWasRunning || customUnitsWasRunning.length > 0)
			busy = false
		})
	}

	function deactivate() {
		if (busy) {
			return
		}
		busy = true
		const steps = [stepResumeBaloo, stepStartAkonadi, stepStartGenericUnits, stepRestoreProfile]
		runSequence(steps, () => {
			servicesIdled = false
			busy = false
		})
	}
}
