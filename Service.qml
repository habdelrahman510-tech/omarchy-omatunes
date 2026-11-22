import QtQuick
import "lib"

// Persistent companion service entry point.
//
// Omarchy loads this file once, at shell start-up, for any plugin that declares
// the `service` kind — independently of the bar widget and of the popup. It has
// no visual parent and is never destroyed by closing the popup, so the MPRIS
// subscriptions and the queue snapshot in `OmatunesService` stay live for the
// whole session.
//
// The object below is deliberately thin: it exists to instantiate the
// singleton at login and to publish a small, stable status surface for
// diagnostics. Bindings here are read-only observers, never a second state.
QtObject {
  id: root

  // Touching the singleton forces its creation before any popup exists.
  readonly property bool connected: OmatunesService.available
  readonly property string track: OmatunesService.title
  readonly property string repeatMode: OmatunesService.repeatMode
  readonly property bool queueKnown: OmatunesService.hasCompanion

  Component.onCompleted: console.info("omatunes: companion service started")
}
