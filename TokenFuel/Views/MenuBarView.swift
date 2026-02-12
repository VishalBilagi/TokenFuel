import SwiftUI

/// Popover panel shown from the menu bar icon.
struct MenuBarPanel: View {
    let manager: QuotaManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image("MenuBarIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text(String(localized: "TokenFuel", comment: "App name in panel header"))
                    .font(.headline)
                Spacer()
                Button {
                    Task { await manager.refreshAll() }
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                        .animation(
                            manager.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: manager.isLoading
                        )
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Provider sections
                    if manager.results.isEmpty && !manager.isLoading {
                        Text(String(localized: "Loading…", comment: "Shown while data is being fetched"))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(16)
                    }

                    ForEach(manager.results) { result in
                        if manager.selectedProviderFilter == nil || manager.selectedProviderFilter == "Unified" || manager.selectedProviderFilter == result.providerName {
                            providerSection(result)
                        }
                    }

                    // Copilot sign-in
                    if manager.copilotProvider.isSignedIn || !manager.config.copilotClientId.isEmpty {
                        if manager.selectedProviderFilter == nil || manager.selectedProviderFilter == "Unified" || manager.selectedProviderFilter == "Copilot" {
                            copilotAuthSection
                        }
                    }
                }
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer
            HStack {
                Text(String(localized: "Updated: \(manager.lastUpdatedText)", comment: "Footer showing last refresh time"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                SettingsLink {
                    Text(String(localized: "Settings…", comment: "Settings button label"))
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(String(localized: "Quit", comment: "Quit button label")) {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Provider Section

    @ViewBuilder
    private func providerSection(_ result: ProviderResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProviderIconView(providerName: result.providerName, size: 12)
                Text(result.providerName.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)

            if let error = result.error {
                Text("⚠ \(error)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            ForEach(result.quotas) { quota in
                quotaRow(quota)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Quota Row with Progress Ring

    private func quotaRow(_ quota: QuotaInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                ProgressRing(percentage: quota.percentage, size: 14, lineWidth: 2.5)
                Text(quota.name)
                    .font(.system(.body, design: .default))
                Spacer()
                Text("\(Int(quota.percentage))%")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(colorForPercentage(quota.percentage))
            }
            if quota.percentage == 0, let reset = quota.resetTime {
                 Text(String(localized: "Resets at \(reset.formatted(date: .omitted, time: .shortened))", comment: "Reset time label"))
                     .font(.caption2)
                     .foregroundStyle(.red)
                     .padding(.leading, 24) // Indent to align with text
            }
        }
    }

    private func colorForPercentage(_ pct: Double) -> Color {
        if pct > 50 { return .green }
        if pct > 20 { return .yellow }
        return .red
    }

    // MARK: - Copilot Auth

    @ViewBuilder
    private var copilotAuthSection: some View {
        let copilotResult = manager.results.first(where: { $0.providerName == "Copilot" })
        let hasQuotas = copilotResult?.quotas.isEmpty == false
        let isNotSignedIn = copilotResult?.error?.contains("Not signed in") == true

        if isNotSignedIn || (!hasQuotas && !manager.copilotProvider.isSignedIn) {
            VStack(alignment: .leading, spacing: 6) {
                if let code = manager.copilotSignInCode {
                    Text(String(localized: "Enter code at github.com/login/device:", comment: "GitHub device flow instructions"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                    Text(String(localized: "Code copied to clipboard!", comment: "Clipboard confirmation"))
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await manager.startCopilotSignIn() }
                    } label: {
                        Label(String(localized: "Sign in to Copilot", comment: "Copilot sign-in button"), systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(manager.isCopilotSigningIn)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Previews

#Preview("Full Panel") {
    MenuBarPanel(manager: QuotaManager())
        .frame(width: 300, height: 400)
}
