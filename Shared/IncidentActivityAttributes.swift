import ActivityKit
import Foundation

struct IncidentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
    }

    var incidentID: String
    var title: String
    var service: String
    var startedAt: Date
}
