import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "StatusBarManager")

@MainActor
class StatusBarManager: NSObject, NSPopoverDelegate {
    private var manager: QuotaManager
    private let popover = NSPopover()
    private var statusItems: [String: NSStatusItem] = [:]

    init(manager: QuotaManager) {
        self.manager = manager
        super.init()
        
        // Configure popover
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(manager: manager))
        popover.delegate = self
        
        // Initial build
        rebuildStatusItems()
        updateLabels()
        
        // Observe changes reactively instead of polling (fixes 2.8)
        observeChanges()
    }
    
    /// Uses `withObservationTracking` to reactively update when `manager.results`
    /// or `manager.config` changes, instead of a 1-second polling timer.
    private func observeChanges() {
        withObservationTracking {
            // Access the properties we want to observe
            _ = self.manager.results
            _ = self.manager.config
        } onChange: {
            Task { @MainActor [weak self] in
                self?.rebuildStatusItems()
                self?.updateLabels()
                // Re-register observation (withObservationTracking is one-shot)
                self?.observeChanges()
            }
        }
    }
    
    private func rebuildStatusItems() {
        let config = manager.config
        
        if config.displayMode == .unified {
            ensureItem(key: "Unified", iconName: "MenuBarIcon")
            removeItem(key: "Gemini")
            removeItem(key: "Antigravity")
            removeItem(key: "Copilot")
            removeItem(key: "Claude")
        } else {
            removeItem(key: "Unified")
            
            if config.geminiInMenuBar {
                ensureItem(key: "Gemini", iconName: "GeminiIcon")
            } else {
                removeItem(key: "Gemini")
            }
            
            if config.antigravityInMenuBar {
                ensureItem(key: "Antigravity", iconName: "AntigravityIcon")
            } else {
                removeItem(key: "Antigravity")
            }
            
            if config.copilotInMenuBar {
                ensureItem(key: "Copilot", iconName: "CopilotIcon")
            } else {
                removeItem(key: "Copilot")
            }
            
            if config.claudeInMenuBar {
                ensureItem(key: "Claude", iconName: "ClaudeIcon")
            } else {
                removeItem(key: "Claude")
            }
        }
    }
    
    private func ensureItem(key: String, iconName: String, isSystem: Bool = false) {
        if statusItems[key] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                if isSystem {
                    button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: key)
                } else {
                    if let img = NSImage(named: iconName) {
                        img.size = NSSize(width: 18, height: 18)
                        img.isTemplate = true
                        button.image = img
                    } else {
                        button.image = NSImage(systemSymbolName: "questionmark", accessibilityDescription: key)
                    }
                }
                button.imagePosition = .imageLeft
                button.target = self
                button.action = #selector(itemClicked(_:))
                // Store key in identifier so we know which one was clicked
                button.identifier = NSUserInterfaceItemIdentifier(key)
            }
            statusItems[key] = item
        }
    }
    
    private func removeItem(key: String) {
        if let item = statusItems[key] {
            NSStatusBar.system.removeStatusItem(item) // Critical to remove from menu bar
            statusItems.removeValue(forKey: key)
        }
    }
    
    // Track which item triggered the popover
    private var currentOpenIdentifier: String?
    
    @objc func itemClicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue else { return }
        
        // If popover is shown and attached to THIS item, close it
        if popover.isShown, currentOpenIdentifier == id {
            popover.performClose(sender)
            currentOpenIdentifier = nil
            return
        }
        
        // Set filter based on clicked item
        manager.selectedProviderFilter = id
        
        // Show popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        currentOpenIdentifier = id
        
        // Activate app to bring popover to front and handle focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Start monitoring for clicks outside to close
        startEventMonitor()
    }
    
 
    
    // MARK: - Event Monitor for Dismissal
    
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    private func startEventMonitor() {
        // Only start if not already running
        guard globalEventMonitor == nil else { return }
        
        // 1. Global monitor (clicks outside the app)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
        
        // 2. Local monitor (clicks inside the app, e.g. Settings window)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            
            // If the click is inside the popover window, do NOT close
            if let popoverWindow = self.popover.contentViewController?.view.window,
               let eventWindow = event.window {
                if popoverWindow == eventWindow {
                    return event
                }
                
                // If the click is on one of our status items, do NOT close
                // (Let the button action handle the toggle)
                for item in self.statusItems.values {
                    if let buttonWindow = item.button?.window, buttonWindow == eventWindow {
                        return event
                    }
                }
            }
            
            // Otherwise (clicked Settings window or elsewhere in app), close
            log.info("Local click detected outside popover - closing")
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
            return event
        }
    }
    
    private func stopEventMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
    
    private func updateLabels() {
        for (key, item) in statusItems {
            guard let button = item.button else { continue }
            
            if key == "Unified" {
                // Unified: Show lowest percentage of ALL quotas
                let allPcts = manager.results.flatMap({ $0.quotas }).map(\.percentage)
                if let minPct = allPcts.min() {
                    button.title = String(localized: "\(Int(minPct))%", comment: "Menu bar percentage label")
                } else {
                    button.title = ""
                }
            } else {
                // Per-Provider: Show lowest percentage for THAT provider
                // Key matches provider name exactly (Gemini, Antigravity, Copilot, Claude)
                if let minPct = manager.lowestPercentage(for: key) {
                    button.title = String(localized: "\(Int(minPct))%", comment: "Menu bar percentage label")
                } else {
                    button.title = ""
                }
            }
        }
    }
    
    // MARK: - NSPopoverDelegate
    
    func popoverDidClose(_ notification: Notification) {
        // Only clear the tracking identifier so we know it's closed
        currentOpenIdentifier = nil
        // Do NOT clear selectedProviderFilter here. 
        // If we switch items, clearing it causes the "Unified" bug.
        // The filter is irrelevant when closed, and will be set correctly 
        // by the next itemClicked call.
        
        stopEventMonitor()
    }
}
