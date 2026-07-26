import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Advanced settings page: the two non-GPU boost axes (background service
// idling, power-profiles-daemon performance profile). Kept on a separate
// page from ConfigGeneral.qml since power limits + these two axes would
// crowd a single form. See SystemController.qml for the logic these
// settings drive.
Kirigami.FormLayout {
	id: page

	property alias cfg_serviceIdlingEnabled: idlingEnabledCheck.checked
	property alias cfg_idleBaloo: idleBalooCheck.checked
	property alias cfg_idleAkonadi: idleAkonadiCheck.checked
	property alias cfg_idleKalarm: idleKalarmCheck.checked
	property alias cfg_customIdleUnits: customUnitsField.text
	property alias cfg_powerProfileEnabled: profileEnabledCheck.checked
	property alias cfg_chromeIdlingEnabled: chromeEnabledCheck.checked
	property alias cfg_chromeProcessPattern: chromePatternField.text
	property alias cfg_chromeNiceValue: chromeNiceField.value

	QQC2.Label {
		Kirigami.FormData.isSection: true
		text: i18n("Background services")
	}

	QQC2.CheckBox {
		id: idlingEnabledCheck
		Kirigami.FormData.label: i18n("Idle services while boosted:")
		text: i18n("Pause the services below while BOOST is active")
	}

	QQC2.CheckBox {
		id: idleBalooCheck
		Kirigami.FormData.label: i18n("Baloo:")
		text: i18n("Suspend the file indexer (balooctl suspend/resume)")
		enabled: idlingEnabledCheck.checked
	}

	QQC2.CheckBox {
		id: idleAkonadiCheck
		Kirigami.FormData.label: i18n("Akonadi:")
		text: i18n("Stop PIM/mail sync (akonadictl stop/start)")
		enabled: idlingEnabledCheck.checked
	}

	QQC2.CheckBox {
		id: idleKalarmCheck
		Kirigami.FormData.label: i18n("KAlarm:")
		text: i18n("Stop kalarm.service, if present on this system")
		enabled: idlingEnabledCheck.checked
	}

	QQC2.TextArea {
		id: customUnitsField
		Kirigami.FormData.label: i18n("Custom units:")
		placeholderText: i18n("One systemctl --user unit per line, e.g. my-sync.service")
		enabled: idlingEnabledCheck.checked
		Layout.fillWidth: true
		Layout.preferredHeight: Kirigami.Units.gridUnit * 4
	}

	QQC2.Label {
		Kirigami.FormData.label: ""
		wrapMode: Text.WordWrap
		opacity: 0.8
		text: i18n("Only units that were actually running are paused, and only those "
			+ "this widget itself paused are resumed. PackageKit, fwupd, and similar "
			+ "update daemons are deliberately not offered here: they typically run as "
			+ "system services, and automating them would require giving this widget "
			+ "root access it does not otherwise need.")
	}

	QQC2.Label {
		Kirigami.FormData.isSection: true
		text: i18n("Power profile")
	}

	QQC2.CheckBox {
		id: profileEnabledCheck
		Kirigami.FormData.label: i18n("Max CPU performance while boosted:")
		text: i18n("Switch to the \"performance\" power-profiles-daemon profile")
	}

	QQC2.Label {
		Kirigami.FormData.label: ""
		wrapMode: Text.WordWrap
		opacity: 0.8
		text: i18n("Uses power-profiles-daemon (powerprofilesctl), the same mechanism "
			+ "System Settings' own Energy Saving page uses - no root needed. Your "
			+ "previous profile is restored exactly when you turn BOOST off. If this "
			+ "system has no \"performance\" profile available, this option has no "
			+ "effect and is reported as unsupported in the widget's tooltip.")
	}

	QQC2.Label {
		Kirigami.FormData.isSection: true
		text: i18n("Browser")
	}

	QQC2.CheckBox {
		id: chromeEnabledCheck
		Kirigami.FormData.label: i18n("Deprioritize browser while boosted:")
		text: i18n("Lower CPU/IO priority for matching browser processes")
	}

	QQC2.TextField {
		id: chromePatternField
		Kirigami.FormData.label: i18n("Process pattern:")
		placeholderText: "chrome|chromium"
		enabled: chromeEnabledCheck.checked
		Layout.fillWidth: true
	}

	QQC2.SpinBox {
		id: chromeNiceField
		Kirigami.FormData.label: i18n("Nice value:")
		from: 0
		to: 19
		stepSize: 1
		enabled: chromeEnabledCheck.checked
	}

	QQC2.Label {
		Kirigami.FormData.label: ""
		wrapMode: Text.WordWrap
		opacity: 0.8
		text: i18n("Matches process command lines against the pattern above (an "
			+ "extended-regex alternation of names, e.g. \"chrome|chromium|brave\") "
			+ "and lowers their CPU nice value and sets idle I/O class - no root "
			+ "needed, since you can always deprioritize your own processes. "
			+ "Reapplied every time you turn BOOST on, so new tabs/renderer "
			+ "processes started afterward are not covered until the next toggle. "
			+ "Also makes a one-shot attempt to push that browser's idle memory out "
			+ "to swap/cache via cgroup v2, but only when the browser is confined to "
			+ "its own cgroup (true for Flatpak browsers; not guaranteed for a "
			+ "natively-installed one) - otherwise that part is silently skipped so "
			+ "it never risks reclaiming memory from anything else.")
	}
}
