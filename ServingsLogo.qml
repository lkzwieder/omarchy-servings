import QtQuick
import qs.Commons

// The Servings mark: a rack of three bars, the things being served, with the
// status light sitting in the corner the short top bar leaves free. Drawn
// from rectangles so it takes whatever color the bar or panel hands it.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color dotColor: color

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real barHeight: Math.max(1.5, iconSize * 0.17)
  readonly property real gap: Math.max(1, iconSize * 0.13)
  readonly property real dotSize: Math.max(3, iconSize * 0.30)
  readonly property real stackHeight: barHeight * 3 + gap * 2
  readonly property real stackTop: (height - stackHeight) / 2

  Rectangle {
    x: 0
    y: root.stackTop
    width: root.width - root.dotSize - root.gap
    height: root.barHeight
    radius: height / 2
    color: root.color
  }

  Rectangle {
    x: root.width - root.dotSize
    y: root.stackTop + root.barHeight / 2 - root.dotSize / 2
    width: root.dotSize
    height: root.dotSize
    radius: width / 2
    color: root.dotColor

    Behavior on color {
      ColorAnimation { duration: 200 }
    }
  }

  Rectangle {
    x: 0
    y: root.stackTop + root.barHeight + root.gap
    width: root.width
    height: root.barHeight
    radius: height / 2
    color: root.color
  }

  Rectangle {
    x: 0
    y: root.stackTop + (root.barHeight + root.gap) * 2
    width: root.width
    height: root.barHeight
    radius: height / 2
    color: root.color
  }
}
