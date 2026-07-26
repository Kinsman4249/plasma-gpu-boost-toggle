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
}
