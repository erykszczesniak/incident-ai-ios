import SwiftUI
import WatchConnectivity

struct WatchIncident: Identifiable, Codable {
    var id: String
    var title: String
    var service: String
    var severity: String
    var status: String
}

@MainActor @Observable final class WatchModel: NSObject, WCSessionDelegate {
    var incidents: [WatchIncident] = []
    var total = 0
    var message: String?
    var pending: String?
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "incidentSnapshot"),
           let items = try? JSONDecoder().decode([WatchIncident].self, from: data)
        {
            incidents = items
            total = UserDefaults.standard.integer(forKey: "activeTotal")
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        accept(session.receivedApplicationContext)
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }

    private nonisolated func accept(_ context: [String: Any]) {
        guard let items = context["incidents"] as? [[String: String]], let data = try? JSONEncoder().encode(items) else { return }
        let total = context["total"] as? Int ?? items.count
        Task { @MainActor in
            self.total = total
            UserDefaults.standard.set(total, forKey: "activeTotal")
            self.incidents = (try? JSONDecoder().decode([WatchIncident].self, from: data)) ?? []
            UserDefaults.standard.set(data, forKey: "incidentSnapshot")
        }
    }

    func acknowledge(_ item: WatchIncident) {
        guard WCSession.default.isReachable else { message = "Open Incident AI on your iPhone, then retry."; return }
        pending = item.id
        WCSession.default.sendMessage(["acknowledge": item.id]) { result in
            let error = result["error"] as? String
            Task { @MainActor in self.pending = nil; self.message = error ?? "Incident acknowledged." }
        } errorHandler: { _ in Task { @MainActor in self.pending = nil; self.message = "Connection lost. Open the iPhone app and retry." } }
    }
}

@main struct IncidentAIWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Text("\(model.total) active incidents").font(.headline).foregroundStyle(.cyan)
                    if model.incidents.isEmpty {
                        Text("No synced incidents. Open Incident AI on your iPhone to refresh.").font(.footnote)
                    }
                    ForEach(model.incidents) { incident in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(incident.severity + " · " + incident.service).font(.caption2).foregroundStyle(.cyan)
                            Text(incident.title).font(.headline)
                            Text(incident.status).font(.caption)
                            if incident
                                .status ==
                                "Open"
                            {
                                Button(model.pending == incident.id ? "Sending…" : "Acknowledge") { model.acknowledge(incident) }
                                    .disabled(model.pending != nil)
                            }
                        }
                    }
                    if let message = model.message {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                }.navigationTitle("Incident AI")
            }
        }
    }
}
