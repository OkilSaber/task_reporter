import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Call super first — this is where macOS restores the cached frame
    super.awakeFromNib()

    // Disable frame autosave so the old small frame isn't restored next launch
    self.setFrameAutosaveName("")

    // Enforce minimum size
    self.minSize = NSSize(width: 1100, height: 840)

    // Force a comfortable launch size centered on screen
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let w: CGFloat = max(1200, min(1400, screen.width * 0.85))
    let h: CGFloat = max(900, min(1000, screen.height * 0.90))
    let x = screen.origin.x + (screen.width  - w) / 2
    let y = screen.origin.y + (screen.height - h) / 2
    self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
  }
}
