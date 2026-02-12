import Foundation

/// Represents a single usage quota metric from any provider.
struct QuotaInfo: Identifiable, Sendable, Equatable, Hashable {
    let id = UUID()
    let name: String          // e.g. "Gemini Pro", "Claude", "Premium"
    let percentage: Double    // 0–100, remaining percentage
    let providerName: String  // e.g. "Gemini", "Antigravity", "Copilot"
    var resetTime: Date? = nil // Optional next reset time

    // Structural equality — ignores UUID so two identical quotas compare equal.
    static func == (lhs: QuotaInfo, rhs: QuotaInfo) -> Bool {
        lhs.name == rhs.name &&
        lhs.providerName == rhs.providerName &&
        lhs.percentage == rhs.percentage
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(providerName)
        hasher.combine(percentage)
    }
}

/// The result of fetching quotas from a single provider.
struct ProviderResult: Identifiable, Sendable, Equatable {
    let id = UUID()
    let providerName: String
    var quotas: [QuotaInfo]
    var error: String?
    var lastUpdated: Date

    // Structural equality — compares data, ignores UUID and timestamp.
    static func == (lhs: ProviderResult, rhs: ProviderResult) -> Bool {
        lhs.providerName == rhs.providerName &&
        lhs.quotas == rhs.quotas &&
        lhs.error == rhs.error
    }
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
