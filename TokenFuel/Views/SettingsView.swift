import SwiftUI

/// Settings window with General and Providers tabs.
struct SettingsView: View {
    @Bindable var manager: QuotaManager

    var body: some View {
        TabView {
            GeneralTab(manager: manager)
                .tabItem {
                    Label(String(localized: "General", comment: "General settings tab"), systemImage: "gear")
                }

            ProvidersTab(manager: manager)
                .tabItem {
                    Label(String(localized: "Providers", comment: "Providers settings tab"), systemImage: "square.stack.3d.up")
                }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var manager: QuotaManager

    var body: some View {
        Form {
            Section(String(localized: "Menu Bar Display", comment: "Settings section header")) {
                Picker(String(localized: "Display Mode", comment: "Display mode picker label"), selection: $manager.config.displayMode) {
                    Text(String(localized: "Unified (single icon)", comment: "Unified display mode")).tag(DisplayMode.unified)
                    Text(String(localized: "Per Provider (separate icons)", comment: "Per provider display mode")).tag(DisplayMode.perProvider)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: manager.config.displayMode) {
                    manager.saveConfig()
                }
            }

            if manager.config.displayMode == .perProvider {
                Section(String(localized: "Show in Menu Bar", comment: "Menu bar visibility section")) {
                    Toggle("Gemini", isOn: $manager.config.geminiInMenuBar)
                    Toggle("Antigravity", isOn: $manager.config.antigravityInMenuBar)
                    Toggle("Copilot", isOn: $manager.config.copilotInMenuBar)
                    Toggle("Claude", isOn: $manager.config.claudeInMenuBar)
                }
                .onChange(of: manager.config.geminiInMenuBar) { manager.saveConfig() }
                .onChange(of: manager.config.antigravityInMenuBar) { manager.saveConfig() }
                .onChange(of: manager.config.copilotInMenuBar) { manager.saveConfig() }
                .onChange(of: manager.config.claudeInMenuBar) { manager.saveConfig() }
            }

            Section(String(localized: "Notifications", comment: "Notifications section header")) {
                Toggle(String(localized: "Notify when quota depleted", comment: "Notification toggle label"), isOn: Binding(
                    get: { manager.config.sendNotifications ?? false },
                    set: { manager.config.sendNotifications = $0 }
                ))
                .onChange(of: manager.config.sendNotifications) {
                    manager.saveConfig()
                    if manager.config.sendNotifications == true {
                        NotificationManager.shared.requestAuthorization()
                    }
                }
            }

            Section(String(localized: "Refresh", comment: "Refresh interval section header")) {
                 Picker(String(localized: "Interval", comment: "Refresh interval picker label"), selection: Binding(
                     get: { manager.config.refreshInterval ?? 900 },
                     set: { manager.config.refreshInterval = $0 }
                 )) {
                     Text(String(localized: "1 Minute", comment: "Refresh interval option")).tag(TimeInterval(60))
                     Text(String(localized: "5 Minutes", comment: "Refresh interval option")).tag(TimeInterval(300))
                     Text(String(localized: "15 Minutes", comment: "Refresh interval option")).tag(TimeInterval(900))
                     Text(String(localized: "30 Minutes", comment: "Refresh interval option")).tag(TimeInterval(1800))
                     Text(String(localized: "1 Hour", comment: "Refresh interval option")).tag(TimeInterval(3600))
                 }
                 .onChange(of: manager.config.refreshInterval) {
                      manager.saveConfig()
                      manager.restartAutoRefresh()
                 }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Providers Tab

private struct ProvidersTab: View {
    @Bindable var manager: QuotaManager

    var body: some View {
        Form {
            Section {
                providerRow(
                    name: "Gemini",
                    icon: { ProviderIconView(providerName: "Gemini", size: 16) },
                    enabled: $manager.config.showGemini,
                    status: statusFor("Gemini")
                ) {
                    Text(String(localized: "Reads credentials from ~/.gemini/oauth_creds.json", comment: "Gemini provider description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                providerRow(
                    name: "Antigravity",
                    icon: { ProviderIconView(providerName: "Antigravity", size: 16) },
                    enabled: $manager.config.showAntigravity,
                    status: statusFor("Antigravity")
                ) {
                    Text(String(localized: "Auto-detects Codeium language server process", comment: "Antigravity provider description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                providerRow(
                    name: "Copilot",
                    icon: { ProviderIconView(providerName: "Copilot", size: 16) },
                    enabled: $manager.config.showCopilot,
                    status: statusFor("Copilot")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if manager.copilotProvider.isSignedIn {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(String(localized: "Signed in", comment: "Copilot signed in status"))
                                    .font(.caption)
                                Spacer()
                                Button(String(localized: "Sign Out", comment: "Sign out button")) {
                                    Task { await manager.signOutCopilot() }
                                }
                                .font(.caption)
                            }
                        } else {
                            Button {
                                Task { await manager.startCopilotSignIn() }
                            } label: {
                                Label(String(localized: "Sign in with GitHub", comment: "GitHub sign-in button"), systemImage: "person.crop.circle.badge.plus")
                            }
                            .disabled(manager.isCopilotSigningIn || manager.config.copilotClientId.isEmpty)
                        }
                    }
                }
            }

            Section {
                providerRow(
                    name: "Claude",
                    icon: { ProviderIconView(providerName: "Claude", size: 16) },
                    enabled: $manager.config.showClaude,
                    status: String(localized: "Coming soon", comment: "Claude provider status")
                ) {
                    Text(String(localized: "Placeholder — future integration", comment: "Claude provider description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: manager.config.showGemini) { manager.saveConfig() }
        .onChange(of: manager.config.showAntigravity) { manager.saveConfig() }
        .onChange(of: manager.config.showCopilot) { manager.saveConfig() }
        .onChange(of: manager.config.showClaude) { manager.saveConfig() }
    }

    private func statusFor(_ provider: String) -> String {
        if let result = manager.results.first(where: { $0.providerName == provider }) {
            if let error = result.error {
                return "⚠ \(error.prefix(40))"
            }
            return "✓ \(result.quotas.count) metrics"
        }
        return String(localized: "Not loaded", comment: "Provider not loaded status")
    }

    @ViewBuilder
    private func providerRow<Icon: View, Content: View>(
        name: String,
        @ViewBuilder icon: () -> Icon,
        enabled: Binding<Bool>,
        status: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                icon()
                Text(name)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
            }
            Text(status)
                .font(.caption2)
                .foregroundStyle(status.hasPrefix("✓") ? .green : .secondary)
            if enabled.wrappedValue {
                content()
            }
        }
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView(manager: QuotaManager())
}
