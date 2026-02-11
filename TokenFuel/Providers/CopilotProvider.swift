import Foundation
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "Copilot")

/// Fetches GitHub Copilot usage quotas using GitHub Device Flow OAuth.
/// Actor isolation serializes all access, eliminating the previous data race risk
/// from @unchecked Sendable.
actor CopilotProvider: QuotaProvider {
    nonisolated let name = "Copilot"

    /// Client ID loaded from config at init time.
    private var clientId: String

    private static let keychainAccount = "copilot_token"

    /// Legacy token file path — used only for one-time migration to Keychain.
    private var legacyTokenFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tokenfuel")
        return dir.appendingPathComponent("copilot_token.json")
    }

    init(clientId: String = "") {
        self.clientId = clientId
    }

    func updateClientId(_ id: String) {
        self.clientId = id
    }

    func fetchClientId() -> String {
        return clientId
    }

    /// Published so the UI can show "Sign in to Copilot" when nil.
    nonisolated var isSignedIn: Bool {
        KeychainHelper.load(account: CopilotProvider.keychainAccount) != nil
    }

    // MARK: - Codable Structs

    private struct StoredToken: Codable {
        let access_token: String
        let token_type: String
        let scope: String
    }

    // Device Flow structs
    private struct DeviceCodeResponse: Codable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let expires_in: Int
        let interval: Int
    }

    private struct AccessTokenResponse: Codable {
        let access_token: String?
        let token_type: String?
        let scope: String?
        let error: String?
    }

    // Copilot API structs
    private struct CopilotUserResponse: Codable {
        let quota_snapshots: QuotaSnapshots?
    }

    private struct QuotaSnapshots: Codable {
        let premium_interactions: QuotaSnapshot?
        let chat: QuotaSnapshot?
    }

    private struct QuotaSnapshot: Codable {
        let percent_remaining: Double?
    }

    // MARK: - QuotaProvider

    func fetchQuotas() async throws -> [QuotaInfo] {
        log.info("Starting Copilot fetch…")

        guard !clientId.isEmpty else {
            throw ProviderError.missingConfig(String(localized: "Copilot client_id not set. See CopilotProvider.swift.", comment: "Error message when client ID is missing"))
        }

        guard let stored = loadToken() else {
            throw ProviderError.missingConfig(String(localized: "Not signed in to Copilot. Click 'Sign in to Copilot' in the menu.", comment: "Error message when not signed in"))
        }

        return try await fetchUserData(token: stored.access_token)
    }

    // MARK: - Device Flow Auth

    /// Step 1: Request a device code from GitHub.
    func requestDeviceCode() async throws -> (userCode: String, verificationURL: String, deviceCode: String, interval: Int) {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw ProviderError.parseError("Invalid device code URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["client_id": clientId, "scope": "read:user"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)

        log.info("Device code received: \(resp.user_code)")

        return (resp.user_code, resp.verification_uri, resp.device_code, resp.interval)
    }

    /// Step 2: Poll GitHub until the user authorizes.
    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw ProviderError.parseError("Invalid access token URL")
        }

        let pollInterval = max(interval, 5)

        for _ in 0..<60 { // Max ~5 minutes of polling
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "client_id": clientId,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(AccessTokenResponse.self, from: data)

            if let token = resp.access_token {
                // Save it to Keychain
                let stored = StoredToken(
                    access_token: token,
                    token_type: resp.token_type ?? "bearer",
                    scope: resp.scope ?? ""
                )
                try saveToken(stored)
                log.info("Copilot token obtained and saved to Keychain!")
                return token
            }

            if let error = resp.error {
                if error == "authorization_pending" {
                    continue
                } else if error == "slow_down" {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // Extra 5s
                    continue
                } else {
                    throw ProviderError.missingConfig(String(localized: "GitHub auth failed: \(error)", comment: "Error message for auth failure"))
                }
            }
        }

        throw ProviderError.missingConfig(String(localized: "GitHub auth timed out. Please try again.", comment: "Error message for auth timeout"))
    }

    /// Remove the stored token from Keychain.
    func signOut() {
        KeychainHelper.delete(account: Self.keychainAccount)
        // Also clean up legacy file if it still exists
        try? FileManager.default.removeItem(at: legacyTokenFileURL)
        log.info("Copilot token removed from Keychain")
    }

    // MARK: - Token Persistence (Keychain)

    /// Load the OAuth token from Keychain.
    /// On first call, migrates from legacy plaintext file if Keychain is empty.
    private func loadToken() -> StoredToken? {
        // Try Keychain first
        if let data = KeychainHelper.load(account: Self.keychainAccount),
           let token = try? JSONDecoder().decode(StoredToken.self, from: data) {
            return token
        }

        // One-time migration: read from legacy file → save to Keychain → delete file
        if FileManager.default.fileExists(atPath: legacyTokenFileURL.path),
           let data = try? Data(contentsOf: legacyTokenFileURL),
           let token = try? JSONDecoder().decode(StoredToken.self, from: data) {
            log.info("Migrating Copilot token from plaintext file to Keychain")
            if let _ = try? saveToken(token) {
                // Successfully migrated — delete the old file
                try? FileManager.default.removeItem(at: legacyTokenFileURL)
                log.info("Legacy token file deleted after Keychain migration")
            }
            return token
        }

        return nil
    }

    /// Save the OAuth token to Keychain.
    @discardableResult
    private func saveToken(_ token: StoredToken) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(token)
        try KeychainHelper.save(data: data, account: Self.keychainAccount)
        return true
    }

    // MARK: - API Call

    private func fetchUserData(token: String) async throws -> [QuotaInfo] {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw ProviderError.parseError("Invalid Copilot API URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        log.info("Calling Copilot API…")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            log.info("Copilot API status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                // Token invalid, remove it
                signOut()
                throw ProviderError.missingConfig(String(localized: "Copilot token expired. Please sign in again.", comment: "Error message for expired token"))
            }
        }

        let decoded = try JSONDecoder().decode(CopilotUserResponse.self, from: data)

        var results: [QuotaInfo] = []

        if let premium = decoded.quota_snapshots?.premium_interactions,
           let remaining = premium.percent_remaining {
            log.info("Premium: \(Int(remaining))%")
            results.append(QuotaInfo(name: "Premium", percentage: remaining, providerName: name))
        } else {
             // Default to 0 if missing but authenticated
             results.append(QuotaInfo(name: "Premium", percentage: 0.0, providerName: name))
        }

        if let chat = decoded.quota_snapshots?.chat,
           let remaining = chat.percent_remaining {
            log.info("Chat: \(Int(remaining))%")
            results.append(QuotaInfo(name: "Chat", percentage: remaining, providerName: name))
        } else {
             results.append(QuotaInfo(name: "Chat", percentage: 0.0, providerName: name))
        }

        return results
    }
}
