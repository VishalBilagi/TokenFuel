import Foundation
import Observation
import AppKit
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "QuotaManager")

/// Central ViewModel that aggregates quota data from all providers.
/// @MainActor guarantees Timer runs on the main RunLoop and all UI
/// state mutations happen on the main thread.
@Observable
@MainActor
final class QuotaManager {
    var results: [ProviderResult] = []
    var isLoading = false
    var lastUpdated: Date?

    // Config
    var config: AppConfig

    // Copilot auth state
    var copilotSignInCode: String?
    var copilotSignInURL: String?
    var isCopilotSigningIn = false

    // Stored provider instances — reused across refreshes (fixes 2.10)
    let copilotProvider = CopilotProvider()
    private let geminiProvider = GeminiProvider()
    private let antigravityProvider = AntigravityProvider()
    
    // UI Filtering (set by StatusBarManager when clicking per-provider icon)
    var selectedProviderFilter: String?

    private var refreshTimer: Timer?
    private var hasStarted = false

    init() {
        self.config = AppConfig.load()
        Task { await copilotProvider.updateClientId(config.copilotClientId) }
        
        if config.sendNotifications == true {
            NotificationManager.shared.requestAuthorization()
        }
        
        // Start fetching immediately on app launch
        startAutoRefresh()
    }

    // MARK: - Active Providers

    private var activeProviders: [any QuotaProvider] {
        var providers: [any QuotaProvider] = []
        if config.showGemini { providers.append(geminiProvider) }
        if config.showAntigravity { providers.append(antigravityProvider) }
        if config.showCopilot { providers.append(copilotProvider) }
        return providers
    }

    // MARK: - Computed Properties

    var menuBarLabel: String {
        if let geminiResult = results.first(where: { $0.providerName == "Gemini" }),
           let proQuota = geminiResult.quotas.first(where: { $0.name == "Gemini Pro" }) {
            return "\(Int(proQuota.percentage))%"
        }
        if let first = results.flatMap({ $0.quotas }).first {
            return "\(Int(first.percentage))%"
        }
        return "—"
    }

    /// Gets the lowest percentage across all quotas for a specific provider.
    func lowestPercentage(for providerName: String) -> Double? {
        guard let result = results.first(where: { $0.providerName == providerName }) else { return nil }
        return result.quotas.map(\.percentage).min()
    }

    var lastUpdatedText: String {
        guard let date = lastUpdated else { return String(localized: "Never", comment: "Last updated time default") }
        return date.formatted(date: .omitted, time: .shortened)
    }


    // MARK: - Config Persistence

    func saveConfig() {
        config.save()
        Task { await copilotProvider.updateClientId(config.copilotClientId) }
    }

    func syncCopilotClientId() {
        Task { await copilotProvider.updateClientId(config.copilotClientId) }
    }

    // MARK: - Actions

    func startAutoRefresh() {
        guard !hasStarted else { return }
        hasStarted = true
        
        let interval = config.refreshInterval ?? 900
        log.info("Starting auto-refresh with interval: \(interval)s")
        
        // Initial fetch
        Task { await refreshAll() }
        
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refreshAll() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        hasStarted = false
    }
    
    func restartAutoRefresh() {
        log.info("Restarting auto-refresh timer...")
        stopAutoRefresh()
        startAutoRefresh()
    }

    func refreshAll() async {
        let providers = activeProviders
        log.info("refreshAll() started with \(providers.count) providers")
        isLoading = true

        let oldResults = results
        var newResults: [ProviderResult] = []

        await withTaskGroup(of: ProviderResult.self) { group in
            for provider in providers {
                let providerName = provider.name
                group.addTask {
                    do {
                        let quotas = try await provider.fetchQuotas()
                        return ProviderResult(providerName: providerName, quotas: quotas, error: nil, lastUpdated: Date())
                    } catch {
                        return ProviderResult(providerName: providerName, quotas: [], error: error.localizedDescription, lastUpdated: Date())
                    }
                }
            }
            for await result in group {
                newResults.append(result)
            }
        }

        let order = ["Gemini", "Antigravity", "Copilot"]
        results = newResults.sorted { a, b in
            (order.firstIndex(of: a.providerName) ?? 99) < (order.firstIndex(of: b.providerName) ?? 99)
        }
        lastUpdated = Date()
        isLoading = false
        
        if config.sendNotifications == true {
            checkForZeroQuotas(old: oldResults, new: self.results)
        }
        
        log.info("refreshAll() complete — \(self.results.count) results")
    }

    // MARK: - Notifications
    
    private func checkForZeroQuotas(old: [ProviderResult], new: [ProviderResult]) {
        for newRes in new {
            for newQuota in newRes.quotas {
                // Find old quota
                let oldRes = old.first(where: { $0.providerName == newRes.providerName })
                if let oldQuota = oldRes?.quotas.first(where: { $0.name == newQuota.name }) {
                    
                    // 1. Replenished: Was 0, now > 0
                    if oldQuota.percentage == 0 && newQuota.percentage > 0 {
                        let title = String(localized: "\(newQuota.providerName) Replenished", comment: "Notification title")
                        let body = String(localized: "\(newQuota.providerName) — \(newQuota.name) is now at \(Int(newQuota.percentage))%.", comment: "Notification body")
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                    
                    // 2. Depleted: Was > 0, now 0
                    if oldQuota.percentage > 0 && newQuota.percentage == 0 {
                        let title = String(localized: "\(newQuota.providerName) Depleted", comment: "Notification title")
                        var body = String(localized: "\(newQuota.providerName) — \(newQuota.name) has reached 0%.", comment: "Notification body")
                        
                        // If reset time is known, schedule a notification for then
                        if let reset = newQuota.resetTime {
                            let resetStr = reset.formatted(date: .omitted, time: .shortened)
                            body += " " + String(localized: "Resets at \(resetStr).", comment: "Notification body appendix")
                            
                            // Schedule future alert
                            let id = "replenish-\(newQuota.providerName)-\(newQuota.name)"
                            NotificationManager.shared.scheduleNotification(
                                at: reset,
                                id: id,
                                title: String(localized: "\(newQuota.providerName) Replenished", comment: "Future notification title"),
                                body: String(localized: "\(newQuota.name) quota should be reset now.", comment: "Future notification body")
                            )
                        }
                        
                        // Send immediate depletion alert
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                }
            }
        }
    }

    // MARK: - Copilot Device Flow

    func startCopilotSignIn() async {
        let currentClientId = await copilotProvider.fetchClientId()
        guard !currentClientId.isEmpty else {
            log.error("Copilot client_id is empty")
            return
        }
        isCopilotSigningIn = true
        do {
            let (userCode, verificationURL, deviceCode, interval) = try await copilotProvider.requestDeviceCode()
            copilotSignInCode = userCode
            copilotSignInURL = verificationURL

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(userCode, forType: .string)

            if let url = URL(string: verificationURL) {
                NSWorkspace.shared.open(url)
            }

            Task {
                do {
                    _ = try await copilotProvider.pollForToken(deviceCode: deviceCode, interval: interval)
                    copilotSignInCode = nil
                    copilotSignInURL = nil
                    isCopilotSigningIn = false
                    await refreshAll()
                } catch {
                    copilotSignInCode = nil
                    copilotSignInURL = nil
                    isCopilotSigningIn = false
                    log.error("Copilot sign-in failed: \(error.localizedDescription)")
                }
            }
        } catch {
            isCopilotSigningIn = false
            log.error("Copilot device code request failed: \(error.localizedDescription)")
        }
    }

    func signOutCopilot() async {
        await copilotProvider.signOut()
        results.removeAll { $0.providerName == "Copilot" }
    }
}
