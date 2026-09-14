import Foundation

public enum Severity: String, Codable, CaseIterable, Sendable {
    case critical, high, medium, low
    public var label: String {
        rawValue.capitalized
    }

    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

public enum IncidentStatus: String, Codable, CaseIterable, Sendable {
    case open, acknowledged, investigating, resolved
    public var label: String {
        rawValue.capitalized
    }
}

public struct Incident: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var service: String
    public var severity: Severity
    public var status: IncidentStatus
    public var description: String
    public var createdAt: Date
    public var updatedAt: Date
    public var acknowledgedAt: Date?
    public var resolvedAt: Date?
    public var reference: String {
        "INC-" + id.uuidString.prefix(6).uppercased()
    }

    public var elapsedMinutes: Int {
        max(0, Int((resolvedAt ?? Date()).timeIntervalSince(createdAt) / 60))
    }
}

public struct IncidentPage: Codable, Sendable {
    public var items: [Incident]
    public var total: Int
    public var limit: Int
    public var offset: Int
}

public struct IncidentAlert: Codable, Identifiable, Sendable {
    public var id: UUID
    public var incidentId: UUID
    public var source: String
    public var externalId: String
    public var title: String
    public var service: String
    public var severity: Severity
    public var description: String
    public var receivedAt: Date
}

public struct LogEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var incidentId: UUID
    public var timestamp: Date
    public var level: String
    public var message: String
}

public struct TimelineEvent: Codable, Identifiable, Sendable {
    public var id: UUID
    public var incidentId: UUID
    public var kind: String
    public var message: String
    public var createdAt: Date
}

public struct Analysis: Codable, Identifiable, Sendable {
    public var id: UUID
    public var incidentId: UUID
    public var summary: String
    public var probableCause: String
    public var confidence: Double
    public var evidence: [String]
    public var remediationSteps: [String]
    public var caveats: [String]
    public var provider: String
    public var isFallback: Bool
    public var createdAt: Date
}

public struct Postmortem: Codable, Identifiable, Sendable {
    public var id: UUID
    public var incidentId: UUID
    public var markdown: String
    public var version: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var jiraIssueKey: String?
    public var jiraIssueUrl: String?
    public var confluenceUrl: String?
}

public struct ExportResult: Codable, Sendable {
    public var destination: String
    public var externalId: String
    public var url: String
    public var isDemo: Bool
}

public struct SeverityCount: Codable, Identifiable, Sendable {
    public var severity: Severity
    public var count: Int
    public var id: String {
        severity.rawValue
    }
}

public struct DailyCount: Codable, Identifiable, Sendable {
    public var date: String
    public var count: Int
    public var id: String {
        date
    }
}

public struct ServiceCount: Codable, Identifiable, Sendable {
    public var service: String
    public var count: Int
    public var id: String {
        service
    }
}

public struct Dashboard: Codable, Sendable {
    public var totalIncidents: Int
    public var activeIncidents: Int
    public var resolvedIncidents: Int
    public var mttrMinutes: Double?
    public var acknowledgementMinutes: Double?
    public var slaCompliancePercent: Double?
    public var slaTargetMinutes: Double
    public var bySeverity: [SeverityCount]
    public var dailyCounts: [DailyCount]
    public var services: [ServiceCount]
}

public struct SearchMatch: Codable, Identifiable, Sendable {
    public var incident: Incident
    public var score: Double
    public var id: UUID {
        incident.id
    }
}

public struct SearchResult: Codable, Sendable {
    public var items: [SearchMatch]
    public var mode: String
}

public enum APIError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL, unauthorized, notFound, invalidResponse, transport(String), server(String), invalidInput(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Use an HTTPS server URL, or HTTP for a local development server."
        case .unauthorized: "Your API key was rejected. Check your connection settings."
        case .notFound: "This item is not available yet. Refresh or generate it first."
        case .invalidResponse: "The server returned an unexpected response. Try again."
        case let .transport(message): "Connection failed: \(message)"
        case let .server(message), let .invalidInput(message): message
        }
    }
}

public enum LoadState<Value> {
    case idle, loading, loaded(Value), failed(String)
    public var value: Value? {
        if case let .loaded(value) = self {
            value
        } else {
            nil
        }
    }
}

public enum IncidentDeepLink {
    public static func incidentID(from url: URL) -> UUID? {
        guard url.scheme == "incidentai", url.host == "incident" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
