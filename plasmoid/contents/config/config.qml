import QtQuick
import org.kde.plasma.configuration

// Lists the config pages shown in the widget's settings dialog.
// "source" paths are resolved relative to contents/ui/.
ConfigModel {
	ConfigCategory {
		name: i18n("General")
		icon: "utilities-system-monitor"
		source: "config/ConfigGeneral.qml"
	}
}
