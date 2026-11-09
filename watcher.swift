// ChromeSecureInputFix watcher
//
// Keeps Google Chrome running with
//   --disable-features=RWHVMacHasFocusReturnsFalseForNonKeyWindow
// which works around the Chrome 156+ bug where Chrome keeps macOS Secure Input
// enabled after a password field was focused and the window went to background
// (Chromium issue 567613584). That bug breaks Logi Options+ keystroke actions.
//
// Whenever Chrome is launched without the flag (Dock, Spotlight, a link from
// another app, login item...), the watcher quits it gracefully and relaunches
// it with the flag plus --restore-last-session, so the same windows/tabs return.
//
// Remove once Google ships a fix: ./uninstall.sh

import AppKit
import Darwin

let chromeBundleID = "com.google.Chrome"
let featureName = "RWHVMacHasFocusReturnsFalseForNonKeyWindow"
let relaunchArgs = ["--disable-features=\(featureName)", "--restore-last-session"]

func log(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(ts) \(message)\n".data(using: .utf8)!)
}

/// Command-line arguments of another process (same user) via KERN_PROCARGS2.
func arguments(of pid: pid_t) -> [String]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

    var argc: Int32 = 0
    memcpy(&argc, buffer, MemoryLayout<Int32>.size)
    var i = MemoryLayout<Int32>.size
    while i < size && buffer[i] != 0 { i += 1 }   // skip executable path
    while i < size && buffer[i] == 0 { i += 1 }   // skip padding

    var args: [String] = []
    while args.count < Int(argc) && i < size {
        let start = i
        while i < size && buffer[i] != 0 { i += 1 }
        args.append(String(decoding: buffer[start..<i], as: UTF8.self))
        i += 1
    }
    return args
}

func hasFlag(_ app: NSRunningApplication) -> Bool {
    guard let args = arguments(of: app.processIdentifier) else { return true } // unknown: leave it alone
    return args.contains { $0.hasPrefix("--disable-features=") && $0.contains(featureName) }
}

var busy = false

func relaunchWithFlag(_ app: NSRunningApplication) {
    guard !busy else { return }
    busy = true
    let chromeURL = app.bundleURL
    log("Chrome pid \(app.processIdentifier) started without the flag; restarting it")

    var attempts = 0
    func waitForExit() {
        if app.isTerminated {
            guard let url = chromeURL else { busy = false; return }
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = relaunchArgs
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { newApp, error in
                if let error = error { log("Relaunch failed: \(error)") }
                else { log("Relaunched Chrome pid \(newApp?.processIdentifier ?? -1) with the flag") }
                DispatchQueue.main.async { busy = false }
            }
            return
        }
        attempts += 1
        if attempts % 10 == 1 { app.terminate() }   // re-send quit every ~2 s
        if attempts > 75 {                             // ~15 s: probably a "Leave site?" dialog
            log("Chrome did not quit; giving up for this launch")
            busy = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: waitForExit)
    }
    // Let Chrome finish initializing so it handles the quit event cleanly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: waitForExit)
}

func check(_ app: NSRunningApplication) {
    guard app.bundleIdentifier == chromeBundleID, !app.isTerminated else { return }
    if !hasFlag(app) { relaunchWithFlag(app) }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { note in
    if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        check(app)
    }
}

// Chrome may already be running when the agent starts (e.g. Chrome is a login item).
NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID).forEach(check)

log("Watcher started")
RunLoop.main.run()
