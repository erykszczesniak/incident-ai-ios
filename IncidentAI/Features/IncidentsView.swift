import IncidentCore
import SwiftUI

struct IncidentsView: View {
    @Environment(AppModel.self) private var app
    @State private var model: IncidentListModel
    @State private var search = ""
    @State private var showResolved = false
    let api: any IncidentAPI
    init(api: any IncidentAPI) {
        self.api = api; _model = State(initialValue: IncidentListModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    masthead
                    switch model.state {
                    case .idle, .loading: LoadingView(title: "Gathering incident signals")
                    case let .failed(message): RecoveryView(message: message) { Task { await reload() } }
                    case let .loaded(incidents):
                        if incidents.isEmpty {
                            ContentUnavailableView(
                                search.isEmpty ? "All quiet here" : "No matching incidents",
                                systemImage: "checkmark.shield",
                                description: Text(search
                                    .isEmpty ? "New alerts will appear here. Pull down to refresh." : "Try another service or incident title.")
                            )
                        } else {
                            incidentList(incidents)
                        }
                    }
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
            }
            .commandBackground().navigationTitle("Incident AI").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Palette.good).accessibilityLabel("Incident command")
                }
            }
            .searchable(text: $search, prompt: "Search incidents or services")
            .refreshable { await reload() }
            .task(id: "\(showResolved)-\(search)") {
                if !search.isEmpty {
                    try? await Task.sleep(for: .milliseconds(280))
                }
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Circle().fill(Palette.good).frame(width: 7, height: 7)
                Text(app.isDemo ? "Demo workspace" : "Live workspace").font(.subheadline).foregroundStyle(Palette.muted)
                Spacer()
                Text(Date(), format: .dateTime.month(.abbreviated).day()).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Text("Stay ahead\nof the incident.").font(.system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.total)").font(.system(size: 44, weight: .medium, design: .rounded)).contentTransition(.numericText())
                    Text(showResolved ? "total incidents" : "active incidents").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Label("On-call ready", systemImage: "checkmark.shield.fill").font(.subheadline.weight(.medium)).foregroundStyle(Palette.good)
                    Text("Context. Clarity. Recovery.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            Picker("Incident scope", selection: $showResolved) { Text("Active").tag(false); Text("All incidents").tag(true) }.pickerStyle(.segmented)
        }
    }

    private func incidentList(_ incidents: [Incident]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Needs attention").font(.headline); Spacer(); Text("Severity first").font(.caption).foregroundStyle(Palette.muted) }
            ForEach(incidents) { incident in
                NavigationLink { IncidentDetailView(id: incident.id, api: api) } label: { IncidentRow(incident: incident) }.buttonStyle(.plain)
            }
            if let message = model.paginationError {
                OperationNotice(message: message)
            }
            if incidents.count < model.total {
                Button(model.isLoadingMore ? "Loading…" : "Load more incidents") { Task { await model.loadMore() } }.frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func reload() async {
        await model.load(status: showResolved ? nil : "active", search: search)
        if search.isEmpty, !showResolved, let incidents = model.state.value {
            SnapshotStore.save(incidents, total: model.total); WatchBridge.shared.publish(incidents, total: model.total)
        }
    }
}

struct IncidentRow: View {
    let incident: Incident
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(incident.severity.color).frame(width: 3).padding(.vertical, 23)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SeverityBadge(severity: incident.severity); Spacer(); Text("\(incident.elapsedMinutes)m").font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.muted); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
                }
                Text(incident.title).font(.headline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Label(incident.service, systemImage: "server.rack").font(.caption).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(incident.status.label).font(.caption.weight(.medium))
                }.foregroundStyle(Palette.muted)
            }.padding(18)
        }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens incident detail")
    }
}
