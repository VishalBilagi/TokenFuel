import Foundation

/// Represents a single usage quota metric from any provider.
struct QuotaInfo: Identifiable, Sendable {
    let id = UUID()
    let name: String          // e.g. "Gemini Pro", "Claude", "Premium"
    let percentage: Double    // 0–100, remaining percentage
    let providerName: String  // e.g. "Gemini", "Antigravity", "Copilot"
    var resetTime: Date? = nil // Optional next reset time
}

/// The result of fetching quotas from a single provider.
struct ProviderResult: Identifiable, Sendable {
    let id = UUID()
    let providerName: String
    var quotas: [QuotaInfo]
    var error: String?
    var lastUpdated: Date
}

/// Shared error type for all providers.
enum ProviderError: LocalizedError {
    case missingConfig(String)
    case processNotFound(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig(let msg): return msg
        case .processNotFound(let msg): return msg
        case .parseError(let msg): return msg
        }
    }
}
