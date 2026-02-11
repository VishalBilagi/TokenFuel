import Foundation

/// Protocol that all quota providers must implement.
protocol QuotaProvider: Sendable {
    var name: String { get }
    func fetchQuotas() async throws -> [QuotaInfo]
}
