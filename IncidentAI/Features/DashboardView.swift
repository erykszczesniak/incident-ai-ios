import Charts
import IncidentCore
import SwiftUI

struct DashboardView: View {
    let api: any IncidentAPI
    @State private var state: LoadState<Dashboard> = .idle
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) { Text("Recovery,\nin perspective.").font(.system(
                        .largeTitle,
                        design: .rounded,
                        weight: .bold
                    )); Text("Your incident response over the last 30 days.").font(.subheadline).foregroundStyle(Palette.muted) }
                    switch state {
                    case .idle, .loading: LoadingView(title: "Measuring response health")
                    case let .failed(message): RecoveryView(message: message) { Task { await load() } }
                    case let .loaded(dashboard):
                        if dashboard.totalIncidents == 0 {
                            ContentUnavailableView(
                                "A clean slate",
                                systemImage: "chart.bar",
                                description: Text("Response metrics will appear after your first incident.")
                            )
                        } else {
                            content(dashboard)
                        }
                    }
                }.padding(22)
            }.commandBackground().navigationTitle("Insights").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
        }
    }

    @ViewBuilder private func content(_ dashboard: Dashboard) -> some View {
        Panel {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SLA compliance").font(.subheadline).foregroundStyle(Palette.muted)
                    Text(dashboard.slaCompliancePercent.map { String(format: "%.1f%%", $0) } ?? "No data").font(.system(
                        .largeTitle,
                        design: .rounded,
                        weight: .semibold
                    )).foregroundStyle(Palette.good)
                }
                Spacer()
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 40)).foregroundStyle(Palette.good.opacity(0.8)).accessibilityHidden(true)
            }
            ProgressView(value: (dashboard.slaCompliancePercent ?? 0) / 100).tint(Palette.good)
            Text("Recovery target: \(dashboard.slaTargetMinutes) minutes").font(.caption).foregroundStyle(Palette.muted)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { metric("Mean recovery", value: minutes(dashboard.mttrMinutes), icon: "timer"); metric(
                "Acknowledgement",
                value: minutes(dashboard.acknowledgementMinutes),
                icon: "hand.raised"
            ) }
            VStack(spacing: 14) { metric("Mean recovery", value: minutes(dashboard.mttrMinutes), icon: "timer"); metric(
                "Acknowledgement",
                value: minutes(dashboard.acknowledgementMinutes),
                icon: "hand.raised"
            ) }
        }
        Panel {
            SectionTitle(title: "Incident volume", subtitle: "Daily incoming incidents")
            Chart(dashboard.dailyCounts) { item in
                BarMark(x: .value("Date", item.date), y: .value("Incidents", item.count)).foregroundStyle(Palette.accent).cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: dashboard.dailyCounts.enumerated().filter { $0.offset % max(1, dashboard.dailyCounts.count / 4) == 0 }
                    .map(\.element.date))
                { value in AxisValueLabel {
                    if let date = value.as(String.self) {
                        Text(String(date.suffix(5))).font(.caption2)
                    }
                } }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 190)
            .accessibilityLabel("Daily incident volume")
        }
        Panel {
            SectionTitle(title: "Severity mix")
            ForEach(dashboard.bySeverity) { item in
                HStack { SeverityBadge(severity: item.severity); Spacer(); Text("\(item.count)").font(.headline.monospacedDigit()) }
            }
        }
        Panel {
            SectionTitle(title: "Services to watch")
            ForEach(dashboard.services) { item in
                HStack { Label(item.service, systemImage: "server.rack").font(.subheadline); Spacer(); Text("\(item.count)").foregroundStyle(Palette.muted) }
            }
        }
        HStack { Label("\(dashboard.activeIncidents) active", systemImage: "waveform.path.ecg"); Spacer(); Label(
            "\(dashboard.resolvedIncidents) resolved",
            systemImage: "checkmark.circle"
        ) }.font(.caption).foregroundStyle(Palette.muted)
    }

    private func metric(_ label: String, value: String, icon: String) -> some View {
        Panel(spacing: 10) { Image(systemName: icon).foregroundStyle(Palette.accent); Text(value).font(.system(
            .title2,
            design: .rounded,
            weight: .semibold
        )); Text(label).font(.caption).foregroundStyle(Palette.muted) }
    }

    private func minutes(_ value: Double?) -> String {
        value.map { String(format: "%.1f min", $0) } ?? "No data"
    }

    private func load() async {
        state = .loading; do { state = try await .loaded(api.dashboard()) } catch { state = .failed(error.localizedDescription) }
    }
}
