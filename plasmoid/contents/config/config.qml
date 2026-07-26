import QtQuick
import org.kde.plasma.configuration

// Lists the config pages shown in the widget's settings dialog.
// "source" paths are resolved relative to contents/ui/.
ConfigModel {
	ConfigCategory {
		name: i18n("General")
		icon: "com.kinsman4249.gpuboosttoggle"
		source: "config/ConfigGeneral.qml"
	}
	ConfigCategory {
		name: i18n("Advanced")
		icon: "configure"
		source: "config/ConfigAdvanced.qml"
	}
}
