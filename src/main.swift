import ApplicationServices
import Cocoa
import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        stopDriver()
    }
}

let appDelegate = AppDelegate()

var signalSources: [DispatchSourceSignal] = []
func installSignalHandlers() {
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            print("[main] shutting down")
            stopDriver()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

func main() {
    let _ = NSApplication.shared
    NSApp.delegate = appDelegate
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    installSignalHandlers()  // stop staying on, driver!!!!!

    // Check accessibility
    let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
    let options = [checkOptPrompt: true] as CFDictionary?

    if !AXIsProcessTrusted() && !AXIsProcessTrustedWithOptions(options) {
        return
    }

    let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength)
    statusItem.button?.image = Bundle.main.image(forResource: "trackpad_status_icon")!
    statusItem.button?.image!.isTemplate = true

    // Hook a popover to the status bar item
    let statusMenu = StatusMenu(statusItem: statusItem)

    // start driver !!
    if driverSettings.enabled {
        startDriver()
    }

    let onDisplayChange: CGDisplayReconfigurationCallBack = { (displayID, flags, userInfo) in
        print("[main] displays changed! restarting driver")
        restartDriver()
    }
    CGDisplayRegisterReconfigurationCallback(onDisplayChange, nil)

    // Atart app
    NSApp.run()
}

let driverProcessUrl = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/driver")

var driverSettings: DriverSettings = DriverSettings()
var process: Process? = nil
func startDriver() {
    if process == nil {
        let p = Process()
        p.executableURL = driverProcessUrl
        p.arguments = driverSettings.toArgs()
        p.terminationHandler = nil
        do {
            try p.run()
            process = p
            print("[main] driver process started (pid \(p.processIdentifier))")
        } catch {
            print("[main] error starting driver: \(error)")
        }
    } else {
        print(
            "[main] startDriver called but driver already running (pid \(process!.processIdentifier))"
        )
    }
}
func stopDriver() {
    if let p = process {
        print("[main] stopping driver (pid \(p.processIdentifier))")
        p.terminate()
        process = nil
    } else {
        print("[main] stopDriver called but no driver running")
    }
}
func restartDriver() {
    stopDriver()
    startDriver()
}

main()
