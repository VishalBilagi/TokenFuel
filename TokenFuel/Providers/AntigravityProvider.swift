import Foundation
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "Antigravity")

/// Fetches usage quotas from the local Codeium language server process.
struct AntigravityProvider: QuotaProvider {
    let name = "Antigravity"

    // MARK: - Codable Structs (matching actual API response)

    private struct UserStatusResponse: Codable {
        let userStatus: UserStatus?
    }

    private struct UserStatus: Codable {
        let cascadeModelConfigData: CascadeModelConfigData?
    }

    private struct CascadeModelConfigData: Codable {
        let clientModelConfigs: [ClientModelConfig]?
    }

    private struct ClientModelConfig: Codable {
        let label: String?
        let quotaInfo: QuotaInfoResponse?
    }

    private struct QuotaInfoResponse: Codable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    // MARK: - QuotaProvider

    func fetchQuotas() async throws -> [QuotaInfo] {
        log.info("Starting Antigravity fetch…")

        // 1. Find the language server process
        let (pid, csrfToken) = try await findLanguageServer()
        log.info("Found language server — PID: \(pid), token: \(csrfToken.prefix(8))…")

        // 2. Find the listening port
        let port = try await findListeningPort(pid: pid)
        log.info("Found listening port: \(port)")

        // 3. Call the local API
        let results = try await fetchUserStatus(port: port, csrfToken: csrfToken)
        log.info("Got \(results.count) quota entries")
        return results
    }

    // MARK: - Process Detection

    private func findLanguageServer() async throws -> (pid: String, csrfToken: String) {
        let output = try await runShellCommand("/bin/ps", arguments: ["-ax", "-o", "pid,args"])

        var foundPid: String?
        var foundToken: String?

        for line in output.components(separatedBy: "\n") {
            // Match both language_server_macos and language_server_macos_arm
            guard line.contains("language_server_macos") else { continue }
            // Skip grep itself if it shows up
            guard !line.contains("grep") else { continue }

            // Extract PID (first column)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard let pidStr = parts.first else { continue }
            foundPid = String(pidStr)

            // Extract --csrf_token value
            if let tokenRange = line.range(of: "--csrf_token") {
                let afterToken = String(line[tokenRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                // Handle --csrf_token VALUE (space-separated)
                let value = afterToken.components(separatedBy: " ").first ?? ""
                if !value.isEmpty {
                    foundToken = value
                }
            }

            if foundPid != nil && foundToken != nil { break }
        }

        guard let pid = foundPid else {
            log.error("language_server_macos process not found")
            throw ProviderError.processNotFound(String(localized: "language_server_macos process not found. Is Codeium/Antigravity running?", comment: "Error message when process is missing"))
        }
        guard let token = foundToken, !token.isEmpty else {
            log.error("Could not extract CSRF token from process args")
            throw ProviderError.parseError(String(localized: "Could not extract CSRF token from process args", comment: "Error message when token is missing"))
        }

        return (pid, token)
    }

    private func findListeningPort(pid: String) async throws -> String {
        let output = try await runShellCommand(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", pid]
        )

        log.info("lsof output lines: \(output.components(separatedBy: "\n").count)")

        // Filter to only lines matching our target PID
        for line in output.components(separatedBy: "\n") {
            guard line.contains("LISTEN") else { continue }

            // Verify the line is for our PID — the PID column is the second field
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }
            let linePid = String(fields[1])
            guard linePid == pid else { continue }

            // Extract port from "TCP 127.0.0.1:PORT (LISTEN)" or "TCP *:PORT (LISTEN)"
            if let colonRange = line.range(of: ":", options: .backwards) {
                let afterColon = line[colonRange.upperBound...]
                let portStr = afterColon.prefix(while: { $0.isNumber })
                if !portStr.isEmpty {
                    log.info("Found port \(portStr) for PID \(pid)")
                    return String(portStr)
                }
            }
        }

        log.error("Could not find listening port for PID \(pid)")
        throw ProviderError.parseError(String(localized: "Could not find listening port for PID \(pid)", comment: "Error message when port is missing"))
    }

    // MARK: - API Call

    private func fetchUserStatus(port: String, csrfToken: String) async throws -> [QuotaInfo] {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            throw ProviderError.parseError(String(localized: "Could not construct Antigravity API URL for port \(port)", comment: "Error message for invalid URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 10

        log.info("Calling \(url.absoluteString)")

        // Use a session that trusts localhost self-signed certs
        let session = URLSession(configuration: .default, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            log.info("Response status: \(httpResponse.statusCode)")
        }

        let decoded: UserStatusResponse
        do {
            decoded = try JSONDecoder().decode(UserStatusResponse.self, from: data)
        } catch {
            log.error("Antigravity decoding failed: \(error.localizedDescription)")
            if let str = String(data: data, encoding: .utf8) {
                log.error("Raw response: \(str)")
            }
            throw error
        }
        
        // ... rest of the function
        let configs = decoded.userStatus?.cascadeModelConfigData?.clientModelConfigs ?? []

        log.info("Found \(configs.count) model configs")
        
        // Define known models we expect to see
        // Note: Codeium/Antigravity often changes these labels. We try to fuzzy match.
        // If we want to guarantee visibility, we need to know the exact labels or just show what returns.
        // BUT the user issue is "when quota is 0%, I see nothing". This implies the API *omits* them when 0.
        // If the API omits them, we need to know what to inject.
        // Let's look for common ones: "claude-3.5-sonnet", "gpt-4o", etc.
        // Since we can't guess valid labels if they aren't there, we might need to rely on cached knowledge or just what's in the list.
        // Wait, if the user says "I see nothing for the claude models", maybe they ARE in the list but remainingFraction is 0?
        // My previous code was: `guard let fraction = config.quotaInfo?.remainingFraction else { return nil }`
        // If remainingFraction is 0, `guard` passes.
        // But if `quotaInfo` is nil (common for unlimited/zero?), it returns nil.
        // So we should handle nil quotaInfo as 0%?
        
        return configs.compactMap { config in
            guard let label = config.label else { return nil }
            
            let fraction = config.quotaInfo?.remainingFraction ?? 0.0
            
            // Parse reset time if available
            // quotaInfo.resetTime might be ISO8601 string?
            var resetDate: Date?
            if let rs = config.quotaInfo?.resetTime {
                 // Try standard ISO parsers
                 if let date = ISO8601DateFormatter().date(from: rs) {
                     resetDate = date
                 }
            }

            let displayName = label // Use raw label
            log.info("  \(displayName): \(Int(fraction * 100))%")

            return QuotaInfo(
                name: displayName,
                percentage: fraction * 100.0,
                providerName: name,
                resetTime: resetDate
            )
        }
    }

    // MARK: - Shell Helper (non-blocking)

    private func runShellCommand(_ path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let pipe = Pipe()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = arguments
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    // IMPORTANT: Read pipe BEFORE waitUntilExit to avoid deadlock.
                    // If the pipe buffer fills (~64KB), the process blocks on write,
                    // and waitUntilExit blocks on the process — deadlock.
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    log.error("Shell command failed: \(path) — \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Localhost TLS Trust

/// Trusts localhost self-signed certificates for the local Codeium language server.
/// Safety: @unchecked Sendable is acceptable here because this class has NO mutable
/// stored properties. All state is passed via method parameters. The @unchecked is
/// required only because NSObject subclasses cannot conform to Sendable automatically.
final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.host == "127.0.0.1",
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
