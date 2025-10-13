import AppKit
import os

let app = NSApplication.shared
let delegate = AppDelegate()
let logger = Logger(subsystem: "com.GST.focd", category: "FOCD")
app.delegate = delegate
app.setActivationPolicy(.accessory)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
