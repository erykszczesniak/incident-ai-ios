import IncidentCore
import SwiftUI

@main struct IncidentAIApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environment(app).preferredColorScheme(.dark).tint(Palette.accent)
                .task { pushDelegate.app = app; WatchBridge.shared.connect(app: app); DiagnosticMonitor.shared.start() }
                .onOpenURL { url in
                    if let id = IncidentDeepLink.incidentID(from: url) {
                        app.selectedIncidentID = id
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTab = 0
    var body: some View {
        @Bindable var app = app
        TabView(selection: $selectedTab) {
            Tab("Incidents", systemImage: "waveform.path.ecg", value: 0) { IncidentsView(api: app.api).id(app.revision) }
            Tab("Insights", systemImage: "chart.xyaxis.line", value: 1) { DashboardView(api: app.api).id(app.revision) }
            Tab("Settings", systemImage: "slider.horizontal.3", value: 2) { SettingsView() }
        }
        .sheet(item: Binding(get: { app.selectedIncidentID.map(IncidentRoute.init) }, set: { app.selectedIncidentID = $0?.id })) { route in
            NavigationStack {
                IncidentDetailView(id: route.id, api: app.api)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { app.selectedIncidentID = nil } } }
            }
        }
    }
}

private struct IncidentRoute: Identifiable { let id: UUID }
