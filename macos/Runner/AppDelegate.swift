import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    // `applicationDidFinishLaunching` is not reliably delivered to the
    // Flutter macOS embedder delegate, so re-apply the persisted icon choice
    // here instead (runs before the Dock shows the app).
    AppIconChannel.applyPersistedIconIfNeeded()
  }

  func setupAppIconChannel(binaryMessenger: FlutterBinaryMessenger) {
    AppIconChannel.install(binaryMessenger: binaryMessenger)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
