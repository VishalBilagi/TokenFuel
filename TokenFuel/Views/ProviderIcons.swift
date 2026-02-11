import SwiftUI

// MARK: - Provider Icon Helpers

/// A view that displays the provider's brand icon at the given size.
struct ProviderIconView: View {
    let providerName: String
    var size: CGFloat = 14

    var body: some View {
        Self.icon(for: providerName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    /// Returns an Image from the asset catalog for the given provider.
    static func icon(for name: String) -> Image {
        switch name {
        case "Gemini": return Image("GeminiIcon")
        case "Antigravity": return Image("AntigravityIcon")
        case "Copilot": return Image("CopilotIcon")
        case "Claude": return Image("ClaudeIcon")
        default: return Image(systemName: "questionmark.circle")
        }
    }
}

/// Legacy free function — forwards to ProviderIconView.icon(for:).
func providerIcon(for name: String) -> Image {
    ProviderIconView.icon(for: name)
}

// MARK: - Previews

#Preview("Gemini Icon") {
    ProviderIconView(providerName: "Gemini", size: 32)
        .padding()
}

#Preview("Unknown Provider") {
    ProviderIconView(providerName: "Unknown", size: 32)
        .padding()
}

