import AppKit

/// Ares Spectator: full screen in its own Space, so the presenter can swipe between it and the console.
/// `--windowed` opens a normal window instead; `--background` also leaves it behind other windows.
@main
final class SpectatorApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var activity: NSObjectProtocol?

  static func main() {
    let app = NSApplication.shared
    let delegate = SpectatorApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let args = ProcessInfo.processInfo.arguments
    let windowed = args.contains("--windowed") || args.contains("--background")
    buildMenu()
    let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = windowed ? NSRect(x: screen.minX + 60, y: screen.minY + 60, width: 1440, height: 900) : screen
    window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Ares Spectator"
    window.isReleasedWhenClosed = false
    window.backgroundColor = .black
    window.collectionBehavior = [.fullScreenPrimary, .managed]
    window.contentViewController = SpectatorController()
    window.setFrame(frame, display: true)
    if args.contains("--background") {
      window.orderBack(nil)
    } else {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    if !windowed { window.toggleFullScreen(nil) }
    // A spectator screen that dims mid-demo is no use.
    activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Ares spectator view")
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  private func buildMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Ares Spectator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let viewItem = NSMenuItem()
    main.addItem(viewItem)
    let viewMenu = NSMenu(title: "View")
    let fs = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
    fs.keyEquivalentModifierMask = [.control, .command]
    viewItem.submenu = viewMenu
    NSApp.mainMenu = main
  }
}
