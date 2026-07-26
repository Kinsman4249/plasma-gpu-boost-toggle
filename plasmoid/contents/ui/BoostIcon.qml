import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// Draws the widget's icon for one of two cases:
//
// - Normal: a single icon, source = Plasmoid.icon (dialog-warning,
//   view-refresh, or the -on/-off flame artwork), same as before this
//   file existed.
// - "GPU power unsupported": the flame (com.kinsman4249.gpuboosttoggle-off,
//   which is drawn with a bolt-shaped cutout - see that file) rendered as
//   a mask so it follows the panel's text colour, with the bolt itself
//   drawn on top in its own fixed yellow, from a separate icon
//   containing only the bolt shape. Two files, because Plasma's isMask
//   recolours an icon's alpha channel with one flat colour - there is no
//   way to mask part of a single SVG and leave the rest in its own
//   colours.
Item {
	id: boostIcon

	property bool active: false
	property bool showNoPowerIcon: false
	property bool maskNormalIcon: false

	Kirigami.Icon {
		anchors.fill: parent
		visible: !boostIcon.showNoPowerIcon
		source: Plasmoid.icon
		active: boostIcon.active
		isMask: boostIcon.maskNormalIcon
	}

	Kirigami.Icon {
		anchors.fill: parent
		visible: boostIcon.showNoPowerIcon
		source: "com.kinsman4249.gpuboosttoggle-off"
		active: boostIcon.active
		isMask: true
	}

	Kirigami.Icon {
		anchors.fill: parent
		visible: boostIcon.showNoPowerIcon
		source: "com.kinsman4249.gpuboosttoggle-bolt"
		active: boostIcon.active
		isMask: false
	}
}
