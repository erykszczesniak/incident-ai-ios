import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var demo = true
    @State private var url = ""
    @State private var key = ""
    @State private var message: String?
    @State private var testing = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Incident AI", systemImage: "waveform.path.ecg").font(.title2.weight(.bold))
                    Text("Clarity for your on-call response.").foregroundStyle(Palette.muted)
                }
                Section("Workspace") {
                    Toggle("Demo workspace", isOn: $demo)
                    Text(demo ? "Explore a complete incident response with synthetic data. Exports are simulated and create no external content." :
                        "Connect to your Incident AI backend. Your API key is stored in this device's Keychain.").font(.footnote).foregroundStyle(Palette.muted)
                    if !demo {
                        TextField("Server URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Use HTTPS for remote servers. Local development: http://127.0.0.1:8000").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Button("Save connection") {
                        do {
                            try app.configure(demo: demo, url: url, key: key); message = demo ? "Demo workspace is ready." : "Connection saved. Test it below."
                        } catch { message = error.localizedDescription }
                    }
                    Button(testing ? "Testing…" : "Test saved connection") {
                        Task {
                            testing = true; defer { testing = false }; do { _ = try await app.api.dashboard(); message = "Connection successful." } catch {
                                message = error.localizedDescription
                            }
                        }
                    }.disabled(testing)
                }
                Section("On-call notifications") {
                    Button("Enable incident notifications") { Task { await enableNotifications() } }
                    Text("New incidents can open directly from a notification. APNs requires a signed build and a configured backend.").font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                Section("Privacy") {
                    Label("API keys stay in Keychain", systemImage: "key.horizontal")
                    Label("No advertising or tracking SDKs", systemImage: "hand.raised")
                    Text(
                        "Telemetry records event names and error types locally. Incident text and credentials are excluded. Review notes before sharing."
                    )
                    .font(.footnote).foregroundStyle(Palette.muted)
                }
                if let message {
                    Section { Text(message).font(.subheadline) }
                }
                if let notification = app.notificationMessage {
                    Section { Text(notification).font(.footnote) }
                }
                Section {
                    Text("Extended features: Home Screen widget, Live Activities and Apple Watch companion. Widgets refresh from the latest opened workspace.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            }.scrollContentBackground(.hidden).commandBackground().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .onAppear { demo = app.isDemo; url = app.serverURL; key = KeychainStore.read() }
        }
    }

    private func enableNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications(); message = "Notifications enabled. Registering this device…"
            } else {
                message = "Notifications are disabled. Enable them in system Settings."
            }
        } catch { message = error.localizedDescription }
    }
}
