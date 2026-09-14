import IncidentCore
import SwiftUI

enum Palette {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.115)
    static let panel = Color(red: 0.075, green: 0.115, blue: 0.175)
    static let panelRaised = Color(red: 0.11, green: 0.155, blue: 0.225)
    static let accent = Color(red: 0.42, green: 0.70, blue: 1)
    static let muted = Color(red: 0.63, green: 0.70, blue: 0.80)
    static let good = Color(red: 0.40, green: 0.84, blue: 0.73)
}

extension Severity {
    var color: Color {
        switch self {
        case .critical: Color(red: 1, green: 0.43, blue: 0.42)
        case .high: Color(red: 1, green: 0.69, blue: 0.35)
        case .medium: Color(red: 0.95, green: 0.83, blue: 0.43)
        case .low: Palette.accent
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Label(severity.label, systemImage: severity == .critical ? "exclamationmark.circle.fill" : "circle.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(severity.color)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(severity.color.opacity(0.12), in: Capsule())
    }
}

struct Panel<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct LoadingView: View {
    var title = "Connecting to your workspace"
    var body: some View {
        VStack(spacing: 20) { ProgressView().tint(Palette.accent); Text(title).font(.subheadline).foregroundStyle(Palette.muted) }
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct RecoveryView: View {
    let message: String
    var retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Unable to load", systemImage: "wifi.exclamationmark")
        } description: { Text(message) } actions: { Button("Try again", action: retry).buttonStyle(.borderedProminent) }
    }
}

struct OperationNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(Palette.accent)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(Palette.background).background(Palette.accent.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func commandBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}
