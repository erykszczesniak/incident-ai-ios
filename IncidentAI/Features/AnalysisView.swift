import IncidentCore
import SwiftUI

struct AnalysisView: View {
    let id: UUID
    let api: any IncidentAPI
    @State private var state: LoadState<Analysis?> = .idle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OperationNotice(message: "AI is assistive. Validate the evidence and approve changes with your incident team.")
                switch state {
                case .idle, .loading: LoadingView(title: "Reviewing the available signals")
                case let .failed(message): RecoveryView(message: message) { Task { await load(generate: true) } }
                case let .loaded(analysis):
                    if let analysis {
                        analysisContent(analysis)
                    } else {
                        ContentUnavailableView(
                            "Connect the signals",
                            systemImage: "sparkle.magnifyingglass",
                            description: Text("Generate a structured summary, probable cause and remediation suggestions from this incident's context.")
                        )
                        Button("Analyze incident") { Task { await load(generate: true) } }.buttonStyle(PrimaryButton())
                    }
                }
            }.padding(20)
        }.commandBackground().navigationTitle("AI analysis").navigationBarTitleDisplayMode(.inline).task { await load(generate: false) }
    }

    @ViewBuilder private func analysisContent(_ analysis: Analysis) -> some View {
        Panel {
            HStack {
                Label("Probable cause", systemImage: "sparkle").font(.headline).foregroundStyle(Palette.accent)
                Spacer()
                Text("\(Int(analysis.confidence * 100))%").font(.system(.headline, design: .rounded))
            }
            Text(analysis.probableCause).font(.title3.weight(.medium)).lineSpacing(4)
            Text("Model confidence is not a calibrated probability.").font(.caption).foregroundStyle(Palette.muted)
            if analysis.provider == "demo" || analysis
                .isFallback
            {
                OperationNotice(message: analysis
                    .isFallback ? "Fallback analysis: the AI provider was unavailable." : "Demo analysis based on synthetic incident data.")
            }
        }
        Panel { SectionTitle(title: "Signal summary"); Text(analysis.summary).font(.subheadline).lineSpacing(5) }
        Panel {
            SectionTitle(title: "Supporting evidence")
            ForEach(Array(analysis.evidence.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "text.magnifyingglass").font(.subheadline).fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        Panel {
            SectionTitle(title: "Suggested response", subtitle: "Review before taking action")
            ForEach(Array(analysis.remediationSteps.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(Palette.accent)
                        .frame(width: 25, height: 25).background(
                            Palette.accent.opacity(0.12),
                            in: Circle()
                        )
                    Text(item).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !analysis.caveats
            .isEmpty
        {
            Panel { SectionTitle(title: "Limits and uncertainty"); ForEach(Array(analysis.caveats.enumerated()), id: \.offset) { _, caveat in
                Text(caveat).font(.footnote).foregroundStyle(Palette.muted)
            } }
        }
        Text("Generated \(analysis.createdAt.formatted()) using \(analysis.provider)").font(.caption).foregroundStyle(Palette.muted)
        Button("Regenerate analysis") { Task { await load(generate: true) } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
    }

    private func load(generate: Bool) async {
        state = .loading
        do {
            state = try await .loaded(api.analysis(id: id, generate: generate))
        } catch APIError.notFound where !generate {
            state = .loaded(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
