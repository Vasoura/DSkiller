import AppKit

let app = NSApplication.shared
let delegate = DSkillerStatusApp()
app.delegate = delegate
delegate.start()
app.run()
