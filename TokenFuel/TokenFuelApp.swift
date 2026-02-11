import SwiftUI

/// App Delegate to bridge SwiftUI App lifecycle with AppKit's NSStatusItem management
class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = QuotaManager()
    var statusBarManager: StatusBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the manager that handles all menu bar items & popovers
        statusBarManager = StatusBarManager(manager: manager)
    }
}

@main
struct TokenFuelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No MenuBarExtra here — it's all handled by AppDelegate/StatusBarManager
        
        Settings {
            SettingsView(manager: appDelegate.manager)
        }
    }
}
