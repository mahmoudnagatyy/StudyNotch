import AppKit

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Do NOT call setActivationPolicy before app.run() — setting it here AND again
// in applicationDidFinishLaunching causes the status bar item to silently
// fail to appear on macOS 13+. Single call lives in AppDelegate.
app.run()
