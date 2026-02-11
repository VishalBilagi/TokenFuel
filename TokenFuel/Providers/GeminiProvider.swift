import Foundation
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "Gemini")

/// Fetches Gemini usage quotas by reading local Gemini CLI credentials.
struct GeminiProvider: QuotaProvider {
    let name = "Gemini"

    // MARK: - Credential File

    private var credentialURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    // MARK: - Codable Structs

    /// Matches the actual ~/.gemini/oauth_creds.json format
    private struct OAuthCreds: Codable {
        let access_token: String
        let refresh_token: String
        let expiry_date: Int64 // milliseconds since epoch
        // scope, token_type, id_token also exist but we don't need them
    }

    private struct QuotaResponse: Codable {
        let buckets: [Bucket]?
    }

    private struct Bucket: Codable {
        let modelId: String?
        let remainingFraction: Double?
        let resetTime: String? // ISO8601 string e.g. "2023-10-27T10:00:00Z"
    }

    // MARK: - QuotaProvider

    func fetchQuotas() async throws -> [QuotaInfo] {
        log.info("Starting Gemini fetch…")

        guard FileManager.default.fileExists(atPath: credentialURL.path) else {
            throw ProviderError.missingConfig(String(localized: "No Gemini credentials found. Run 'gemini' CLI to sign in.", comment: "Error message when credentials file is missing"))
        }

        let creds = try loadCredentials()

        // Check if token is expired
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now >= creds.expiry_date {
            log.warning("Gemini token expired. User needs to re-auth via Gemini CLI.")
            throw ProviderError.missingConfig(String(localized: "Gemini token expired. Run 'gemini' CLI to refresh.", comment: "Error message when token is expired"))
        }

        return try await fetchQuotaData(accessToken: creds.access_token)
    }

    // MARK: - Private Helpers

    private func loadCredentials() throws -> OAuthCreds {
        let data = try Data(contentsOf: credentialURL)
        let creds = try JSONDecoder().decode(OAuthCreds.self, from: data)
        log.info("Loaded Gemini creds, expires: \(creds.expiry_date)")
        return creds
    }

    private func fetchQuotaData(accessToken: String) async throws -> [QuotaInfo] {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
            throw ProviderError.parseError(String(localized: "Invalid Gemini API URL", comment: "Error message for invalid URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 15

        log.info("Calling Gemini quota API…")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            log.info("Gemini API status: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                throw ProviderError.missingConfig(String(localized: "Gemini token rejected (401). Run 'gemini' CLI to re-auth.", comment: "Error message when API rejects token"))
            }
        }

        let quotaResponse = try JSONDecoder().decode(QuotaResponse.self, from: data)
        let buckets = quotaResponse.buckets ?? []

        log.info("Got \(buckets.count) buckets")

        // Parse buckets
        var proPct: Double?
        var flashPct: Double?
        var proReset: Date?
        var flashReset: Date?
        
        // Helper formatter for ISO8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for bucket in buckets {
            guard let modelId = bucket.modelId?.lowercased() else { continue }
            
            // If remainingFraction is nil, assume 0? Or maybe implicit 0 if bucket present?
            // Usually valid bucket has fraction.
            let fraction = bucket.remainingFraction ?? 0.0
            let pct = fraction * 100.0
            
            // Parse reset time
            var resetDate: Date?
            if let rs = bucket.resetTime {
                 resetDate = isoFormatter.date(from: rs)
            }

            if modelId.contains("pro") {
                // Keep the lowest of the 'pro' buckets found? Or usually just one.
                if proPct == nil || pct < proPct! {
                    proPct = pct
                    proReset = resetDate
                }
            }
            if modelId.contains("flash") {
                if flashPct == nil || pct < flashPct! {
                    flashPct = pct
                    flashReset = resetDate
                }
            }
        }

        var results: [QuotaInfo] = []

        // Always return Pro/Flash, defaulting to 0 if missing
        let finalPro = proPct ?? 0.0
        results.append(QuotaInfo(name: "Gemini Pro", percentage: finalPro, providerName: name, resetTime: proReset))
        
        let finalFlash = flashPct ?? 0.0
        results.append(QuotaInfo(name: "Gemini Flash", percentage: finalFlash, providerName: name, resetTime: flashReset))

        return results
    }
}
