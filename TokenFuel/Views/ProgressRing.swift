import SwiftUI

// MARK: - Progress Ring

/// A small circular progress ring for menu bar and dropdown display.
struct ProgressRing: View {
    let percentage: Double
    var size: CGFloat = 14
    var lineWidth: CGFloat = 2.5

    private var fraction: CGFloat { CGFloat(percentage / 100.0) }

    private var ringColor: Color {
        if percentage > 50 { return .green }
        if percentage > 20 { return .yellow }
        return .red
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: lineWidth)

            // Filled ring
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Menu Bar Progress Label

/// Combined progress ring + percentage text for menu bar display.
struct MenuBarProgressLabel: View {
    let percentage: Double
    let icon: Image

    var body: some View {
        HStack(spacing: 4) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
            ProgressRing(percentage: percentage, size: 12, lineWidth: 2)
            Text("\(Int(percentage))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Previews

#Preview("75% Progress") {
    ProgressRing(percentage: 75)
        .padding()
}

#Preview("25% Warning") {
    ProgressRing(percentage: 25)
        .padding()
}

#Preview("5% Critical") {
    ProgressRing(percentage: 5)
        .padding()
}

#Preview("Menu Bar Label") {
    MenuBarProgressLabel(
        percentage: 62,
        icon: Image(systemName: "sparkle")
    )
    .padding()
}
