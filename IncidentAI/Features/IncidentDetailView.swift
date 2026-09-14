import IncidentCore
import SwiftUI

@MainActor @Observable final class IncidentDetailModel {
    var state: LoadState<Incident> = .idle
    var logs: [LogEntry] = []
    var alerts: [IncidentAlert] = []
    var contextError: String?
    var operationError: String?
    var updating = false
    let id: UUID
    let api: any IncidentAPI
    init(id: UUID, api: any IncidentAPI) {
        self.id = id; self.api = api
    }

    func load() async {
        state = .loading
        do {
            state = try await .loaded(api.incident(id: id))
        } catch { state = .failed(error.localizedDescription); return }
        await loadContext()
    }

    func loadContext() async {
        contextError = nil
        do {
            async let newLogs = api.logs(id: id)
            async let newAlerts = api.alerts(id: id)
            (logs, alerts) = try await (newLogs, newAlerts)
        } catch { contextError = error.localizedDescription }
    }

    @discardableResult func update(_ status: IncidentStatus) async -> Bool {
        updating = true; operationError = nil
        defer { updating = false }
        do {
            state = try await .loaded(api.updateIncident(id: id, status: status))
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }
}

struct IncidentDetailView: View {
    @State private var model: IncidentDetailModel
    @State private var showResolve = false
    @State private var activityMessage: String?
    init(id: UUID, api: any IncidentAPI) {
        _model = State(initialValue: IncidentDetailModel(id: id, api: api))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch model.state {
                case .idle, .loading: LoadingView(title: "Loading incident context")
                case let .failed(message): RecoveryView(message: message) { Task { await model.load() } }
                case let .loaded(incident): content(incident)
                }
            }.padding(20)
        }.commandBackground().navigationTitle("Incident command").navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }.refreshable { await model.load() }
            .confirmationDialog("Resolve this incident?", isPresented: $showResolve, titleVisibility: .visible) {
                Button("Confirm recovery and resolve") { Task {
                    if await model.update(.resolved) {
                        await LiveActivityManager.end(id: model.id)
                    }
                } }
            } message: { Text("Confirm service health and customer impact before closing the incident.") }
    }

    @ViewBuilder private func content(_ incident: Incident) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                SeverityBadge(severity: incident.severity); Spacer(); Text(incident.reference).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            Text(incident.title).font(.system(.title, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            HStack { Label(incident.service, systemImage: "server.rack"); Spacer(); Text(incident.status.label).foregroundStyle(Palette.accent) }
                .font(.subheadline)
            Text(incident.description).font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
        }
        Panel {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.status == .resolved ? "Time to recovery" : "Elapsed time").font(.caption).foregroundStyle(Palette.muted)
                    if let resolvedAt = incident.resolvedAt {
                        Text(Duration.seconds(resolvedAt.timeIntervalSince(incident.createdAt)).formatted(.time(pattern: .hourMinuteSecond))).font(.system(
                            .title2,
                            design: .monospaced,
                            weight: .medium
                        ))
                    } else {
                        Text(incident.createdAt, style: .timer).font(.system(.title2, design: .monospaced, weight: .medium))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) { Text("Detected").font(.caption).foregroundStyle(Palette.muted); Text(
                    incident.createdAt,
                    format: .dateTime.hour().minute()
                ).font(.title3.weight(.medium)) }
            }
            if incident.status != .resolved {
                HStack {
                    if incident.status == .open {
                        Button("Acknowledge") { Task { await model.update(.acknowledged) } }.buttonStyle(PrimaryButton())
                    } else if incident
                        .status == .acknowledged
                    {
                        Button("Investigate") { Task { await model.update(.investigating) } }.buttonStyle(PrimaryButton())
                    }
                    Button("Resolve") { showResolve = true }.buttonStyle(.bordered).controlSize(.large)
                }.disabled(model.updating)
                if model.updating {
                    ProgressView("Updating status")
                }
            }
            if let error = model.operationError {
                OperationNotice(message: error)
            }
        }
        VStack(spacing: 10) {
            NavigationLink { AnalysisView(id: incident.id, api: model.api) } label: { featureRow(
                "AI analysis",
                detail: "Evidence, probable cause and next steps",
                symbol: "sparkle",
                color: Palette.accent
            ) }
            NavigationLink { TimelineView(id: incident.id, api: model.api) } label: { featureRow(
                "Incident timeline",
                detail: "A shared record of the response",
                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                color: Palette.good
            ) }
            NavigationLink { PostmortemView(id: incident.id, api: model.api) } label: { featureRow(
                "Postmortem",
                detail: "Review the draft, then export",
                symbol: "doc.text",
                color: Color.orange
            ) }
        }.buttonStyle(.plain)
        if incident.status != .resolved {
            Button { activityMessage = LiveActivityManager.start(incident) } label: { Label("Follow on Lock Screen", systemImage: "rectangle.inset.filled") }
                .font(.subheadline)
            if let activityMessage {
                OperationNotice(message: activityMessage)
            }
        }
        if let error = model.contextError {
            Panel {
                Text("Context unavailable").font(.headline); Text(error)
                    .font(.subheadline); Button("Reload logs and alerts") { Task { await model.loadContext() } }
            }
        } else {
            Panel {
                SectionTitle(title: "Source signals", subtitle: "\(model.alerts.count) linked alert\(model.alerts.count == 1 ? "" : "s")")
                if model.alerts.isEmpty {
                    Text("No source alerts attached.").foregroundStyle(Palette.muted)
                }
                ForEach(model.alerts) { alert in Label(alert.source.capitalized + ": " + alert.title, systemImage: "bell.badge").font(.subheadline) }
            }
            Panel {
                SectionTitle(title: "Recent logs", subtitle: "Secrets are redacted before analysis")
                if model.logs.isEmpty {
                    Text("No logs attached to this incident yet.").foregroundStyle(Palette.muted)
                }
                ForEach(model.logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(log.level).foregroundStyle(log.level.uppercased() == "ERROR" ? Severity.critical.color : Palette.accent); Spacer(); Text(
                            log.timestamp,
                            format: .dateTime.hour().minute().second()
                        ).foregroundStyle(Palette.muted) }.font(.system(.caption2, design: .monospaced))
                        Text(log.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 5)
                }
            }
        }
    }

    private func featureRow(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color).frame(width: 42, height: 46).background(
                color.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(Palette.muted) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
        }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
