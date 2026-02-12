import Foundation
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "AppConfig")

/// Display mode for menu bar items.
enum DisplayMode: String, Codable, CaseIterable {
    case unified = "unified"
    case perProvider = "perProvider"
}

/// App configuration — loaded from the bundled config.json,
/// with user overrides saved to Application Support.
struct AppConfig: Codable {
    var copilotClientId: String {
        guard let infoPlistId = Bundle.main.object(forInfoDictionaryKey: "COPILOT_CLIENT_ID") as? String,
              !infoPlistId.isEmpty else {
            return ""
        }
        return infoPlistId
    }
    var displayMode: DisplayMode
    var showGemini: Bool
    var showAntigravity: Bool
    var showCopilot: Bool
    var showClaude: Bool

    // Per-provider menu bar visibility (only used in perProvider mode)
    var geminiInMenuBar: Bool
    var antigravityInMenuBar: Bool
    var copilotInMenuBar: Bool
    var claudeInMenuBar: Bool
    
    // Notifications
    var sendNotifications: Bool?
    
    // Refresh Interval (seconds)
    var refreshInterval: TimeInterval?

    static let `default` = AppConfig(
        displayMode: .unified,
        showGemini: true,
        showAntigravity: true,
        showCopilot: true,
        showClaude: false,
        geminiInMenuBar: true,
        antigravityInMenuBar: true,
        copilotInMenuBar: true,
        claudeInMenuBar: false,
        sendNotifications: true,
        refreshInterval: 900
    )

    // MARK: - Persistence

    /// User overrides go to Application Support (auto-created by macOS).
    private static var userConfigURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            log.error("Could not locate Application Support directory")
            // Fallback to a temporary location — should never happen on macOS
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("TokenFuel")
                .appendingPathComponent("config.json")
        }
        let dir = appSupport.appendingPathComponent("TokenFuel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    /// Load config: user overrides first, then fall back to bundled config.json.
    /// If the copilotClientId is empty, attempt to read from Info.plist
    /// (injected at build time via Secrets.xcconfig).
    static func load() -> AppConfig {
        var config: AppConfig

        // 1. Try user overrides
        if let data = try? Data(contentsOf: userConfigURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            log.info("Config loaded from user overrides")
            config = loaded
        }
        // 2. Fall back to bundled config.json
        else if let url = Bundle.main.url(forResource: "config", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            log.info("Config loaded from bundle")
            config = loaded
        } else {
            log.info("No config found, using defaults")
            config = .default
        }



        return config
    }

    /// Save user overrides to Application Support.
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.userConfigURL, options: .atomic)
            log.debug("Config saved")
        } catch {
            log.error("Failed to save config: \(error.localizedDescription)")
        }
    }
}

