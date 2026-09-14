import ActivityKit
import IncidentCore
import UIKit
import UserNotifications
import WatchConnectivity
import WidgetKit

@MainActor final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var app: AppModel?
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            guard let app else { return }
            do {
                try await app.api.registerDevice(token: token); app.notificationMessage = app
                    .isDemo ? "Demo mode: token registration was simulated." : "This device is registered for incident notifications."
            } catch { app.notificationMessage = error.localizedDescription; app.telemetry.failure(error, operation: "register_push") }
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        app?.notificationMessage = "Push registration is unavailable. Use a signed build with the APNs entitlement."
        app?.telemetry.failure(error, operation: "register_push")
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.content.userInfo["incident_id"] as? String
        if let identifier, let id = UUID(uuidString: identifier) {
            await MainActor.run { self.app?.selectedIncidentID = id }
        }
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [
            .banner,
            .sound,
            .badge
        ]
    }
}

enum SnapshotStore {
    static func save(_ incidents: [Incident], total: Int) {
        guard let defaults = UserDefaults(suiteName: "group.com.erykszczesniak.IncidentAI") else { return }
        let active = incidents.filter { $0.status != .resolved }
        defaults.set(total, forKey: "activeCount")
        defaults.set(active.first?.title ?? "All systems quiet", forKey: "topTitle")
        defaults.set(active.first?.id.uuidString ?? "", forKey: "topID")
        defaults.set(Date(), forKey: "updatedAt")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum LiveActivityManager {
    static func start(_ incident: Incident) -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "Live Activities are disabled in system Settings." }
        guard !Activity<IncidentActivityAttributes>.activities.contains(where: { $0.attributes.incidentID == incident.id.uuidString })
        else { return "This incident is already on your Lock Screen." }
        do {
            let attributes = IncidentActivityAttributes(
                incidentID: incident.id.uuidString,
                title: incident.title,
                service: incident.service,
                startedAt: incident.createdAt
            )
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: IncidentActivityAttributes.ContentState(status: incident.status.label), staleDate: nil),
                pushType: nil
            )
            return "Following this incident on your Lock Screen."
        } catch { return "Could not start Live Activity: \(error.localizedDescription)" }
    }

    static func end(id: UUID) async {
        for activity in Activity<IncidentActivityAttributes>.activities where activity.attributes.incidentID == id.uuidString {
            await activity.end(ActivityContent(state: .init(status: "Resolved"), staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}

@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private weak var app: AppModel?
    func connect(app: AppModel) {
        self.app = app
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ incidents: [Incident], total: Int) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired else { return }
        let items = incidents.filter { $0.status != .resolved }.map { [
            "id": $0.id.uuidString,
            "title": $0.title,
            "service": $0.service,
            "severity": $0.severity.label,
            "status": $0.status.label
        ] }
        do {
            try WCSession.default.updateApplicationContext(["incidents": items, "total": total, "updated_at": Date().timeIntervalSince1970])
        } catch { app?.telemetry.failure(error, operation: "watch_sync") }
    }

    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
    nonisolated func sessionDidBecomeInactive(_: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let id = (message["acknowledge"] as? String).flatMap(UUID.init(uuidString:))
        let reply = WatchReply(replyHandler)
        Task { @MainActor in
            guard let id, let app = self.app else { reply.send(["error": "Open Incident AI on your iPhone first."]); return }
            do {
                _ = try await app.api.updateIncident(id: id, status: .acknowledged)
                let page = try await app.api.incidents(status: "active", search: "", offset: 0)
                self.publish(page.items, total: page.total)
                reply.send(["ok": true])
            } catch { reply.send(["error": error.localizedDescription]) }
        }
    }
}

private final class WatchReply: @unchecked Sendable {
    let callback: ([String: Any]) -> Void
    init(_ callback: @escaping ([String: Any]) -> Void) {
        self.callback = callback
    }

    func send(_ value: [String: Any]) {
        callback(value)
    }
}
