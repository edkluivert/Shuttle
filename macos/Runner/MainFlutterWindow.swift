import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Chromeless titlebar: the Flutter view runs the full height of the window
    // and paints under the bar, so the top strip picks up the app's own theme
    // instead of AppKit's grey. Only the traffic lights are left drawn on top.
    //
    // Nothing has to be pushed to Swift when the theme changes — the strip is
    // Flutter pixels now, so it follows the light/dark palette for free.
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    // AppKit still owns that strip for input: it is the drag region that moves
    // the window, and it swallows clicks meant for whatever is painted below
    // it. The Dart side keeps its chrome clear of it — see `MacTitlebarInset`.
    self.minSize = NSSize(width: 720, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
