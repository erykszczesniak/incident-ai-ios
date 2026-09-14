import Foundation

public actor MockAPIClient: IncidentAPI {
    private var storage: [Incident]
    private var events: [UUID: [TimelineEvent]] = [:]
    private var analyses: [UUID: Analysis] = [:]
    private var postmortems: [UUID: Postmortem] = [:]

    public init(now: Date = Date()) {
        storage = DemoData.incidents(now: now)
        for incident in storage {
            events[incident.id] = [
                TimelineEvent(
                    id: UUID(),
                    incidentId: incident.id,
                    kind: "alert",
                    message: "Grafana detected elevated error rate on \(incident.service).",
                    createdAt: incident.createdAt
                ),
                TimelineEvent(
                    id: UUID(),
                    incidentId: incident.id,
                    kind: "context",
                    message: "Collected service health signals and 128 recent log entries.",
                    createdAt: incident.createdAt.addingTimeInterval(45)
                )
            ]
            if incident.status != .open {
                events[incident.id]?.append(TimelineEvent(
                    id: UUID(),
                    incidentId: incident.id,
                    kind: "status",
                    message: "On-call engineer acknowledged the incident.",
                    createdAt: incident.createdAt.addingTimeInterval(120)
                ))
            }
        }
    }

    public func incidents(status: String? = "active", search: String = "", offset: Int = 0) async throws -> IncidentPage {
        let items = storage.filter { incident in
            (status == nil || (status == "active" ? incident.status != .resolved : incident.status.rawValue == status)) &&
                (search.isEmpty || "\(incident.title) \(incident.service)".localizedCaseInsensitiveContains(search))
        }.sorted { $0.severity.rank == $1.severity.rank ? $0.createdAt > $1.createdAt : $0.severity.rank < $1.severity.rank }
        return IncidentPage(items: Array(items.dropFirst(max(0, offset)).prefix(50)), total: items.count, limit: 50, offset: offset)
    }

    public func incident(id: UUID) async throws -> Incident {
        try find(id)
    }

    public func updateIncident(id: UUID, status: IncidentStatus) async throws -> Incident {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
        storage[index].status = status
        storage[index].updatedAt = Date()
        if status == .acknowledged {
            storage[index].acknowledgedAt = Date()
        }
        storage[index].resolvedAt = status == .resolved ? Date() : nil
        _ = try await addEvent(id: id, message: "Status changed to \(status.rawValue).")
        return storage[index]
    }

    public func alerts(id: UUID) async throws -> [IncidentAlert] {
        let item = try find(id)
        return [IncidentAlert(
            id: UUID(),
            incidentId: id,
            source: "grafana",
            externalId: "grafana-\(id)",
            title: item.title,
            service: item.service,
            severity: item.severity,
            description: item.description,
            receivedAt: item.createdAt
        )]
    }

    public func logs(id: UUID) async throws -> [LogEntry] {
        let item = try find(id)
        return [
            ("INFO", "deploy completed version=2.8.1 region=eu-west-1"),
            ("WARN", "connection_pool utilization=98% active=196 max=200"),
            ("ERROR", "checkout.request failed: database connection timeout after 5000ms"),
            ("ERROR", "upstream response 503 request_id=8c2f latency_ms=5012"),
            ("WARN", "retry budget exhausted downstream=orders-db"),
            ("INFO", "health probe completed queue_depth=84 secret=[REDACTED]")
        ].enumerated().map { index, value in
            LogEntry(id: UUID(), incidentId: id, timestamp: item.createdAt.addingTimeInterval(Double(index * 17)), level: value.0, message: value.1)
        }
    }

    public func timeline(id: UUID) async throws -> [TimelineEvent] {
        _ = try find(id); return events[id] ?? []
    }

    public func addEvent(id: UUID, message: String) async throws -> TimelineEvent {
        _ = try find(id)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.invalidInput("Write a timeline note first.") }
        let event = TimelineEvent(id: UUID(), incidentId: id, kind: "manual", message: trimmed, createdAt: Date())
        events[id, default: []].append(event)
        return event
    }

    public func analysis(id: UUID, generate: Bool) async throws -> Analysis {
        let item = try find(id)
        if !generate, let value = analyses[id] {
            return value
        }
        if !generate {
            throw APIError.notFound
        }
        let value = Analysis(
            id: UUID(),
            incidentId: id,
            summary: "Elevated 5xx responses on \(item.service) coincide with database connection saturation after the latest deployment. Requests are timing out while waiting for available connections.",
            probableCause: "A connection lifecycle regression in version 2.8.1 may be exhausting the database pool.",
            confidence: 0.84,
            evidence: [
                "Pool utilization reached 98% before the error spike.",
                "First timeout appeared 45 seconds after deployment.",
                "Database CPU and storage latency remained within baseline."
            ],
            remediationSteps: [
                "Compare connection release paths in 2.8.1 with the previous release.",
                "Validate the rollback plan and obtain incident commander approval.",
                "If approved, roll back to 2.8.0 and watch error rate and pool utilization.",
                "Confirm recovery for 10 minutes before resolving the incident."
            ],
            caveats: [
                "Demo analysis uses synthetic signals. Confirm every suggestion against your environment.",
                "Correlation with a deployment does not establish causation."
            ],
            provider: "demo",
            isFallback: false,
            createdAt: Date()
        )
        analyses[id] = value
        _ = try await addEvent(id: id, message: "Assistive analysis generated. Engineer review required.")
        return value
    }

    public func postmortem(id: UUID, generate: Bool) async throws -> Postmortem {
        let item = try find(id)
        if !generate, let value = postmortems[id] {
            return value
        }
        if !generate {
            throw APIError.notFound
        }
        let markdown = """
        # Postmortem: \(item.title)

        > Working draft. Validate the evidence and review with the incident team.

        ## Summary
        \(item.description)

        ## Impact
        \(item.service) experienced elevated errors. Customer impact and affected request count require confirmation.

        ## Probable cause
        \(analyses[id]?.probableCause ?? "Analysis pending. Capture evidence before drawing conclusions.")

        ## Timeline
        \((events[id] ?? []).map { "- \($0.createdAt.formatted(date: .omitted, time: .shortened)): \($0.message)" }.joined(separator: "\n"))

        ## What went well
        - Alerting detected the symptom and paged the on-call engineer.

        ## Follow-up actions
        - [ ] Confirm root cause and supporting evidence. Owner: TBD
        - [ ] Add a regression test for connection lifecycle. Owner: TBD
        - [ ] Review deployment guardrails. Owner: TBD
        """
        let value = Postmortem(
            id: postmortems[id]?.id ?? UUID(),
            incidentId: id,
            markdown: markdown,
            version: (postmortems[id]?.version ?? 0) + 1,
            createdAt: postmortems[id]?.createdAt ?? Date(),
            updatedAt: Date()
        )
        postmortems[id] = value
        _ = try await addEvent(id: id, message: "Postmortem draft generated for review.")
        return value
    }

    public func savePostmortem(id: UUID, markdown: String) async throws -> Postmortem {
        guard var value = postmortems[id] else { throw APIError.notFound }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidInput("The postmortem cannot be empty.") }
        value.markdown = markdown
        value.version += 1
        value.updatedAt = Date()
        postmortems[id] = value
        return value
    }

    public func export(id: UUID, destination: String) async throws -> ExportResult {
        guard postmortems[id] != nil else { throw APIError.notFound }
        guard ["jira", "confluence"].contains(destination) else { throw APIError.invalidInput("Unsupported destination.") }
        _ = try await addEvent(id: id, message: "Simulated \(destination.capitalized) export completed. No external content was created.")
        return ExportResult(destination: destination, externalId: "DEMO-1042", url: "https://example.com/demo/DEMO-1042", isDemo: true)
    }

    public func dashboard() async throws -> Dashboard {
        let resolved = storage.filter { $0.status == .resolved }
        let mean = resolved.isEmpty ? 0 : resolved.map { Double($0.elapsedMinutes) }.reduce(0, +) / Double(resolved.count)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let daily = (0 ..< 14).map { day in
            let date = Calendar.current.date(byAdding: .day, value: day - 13, to: Date()) ?? Date()
            let count = storage.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }.count
            return DailyCount(date: formatter.string(from: date), count: count)
        }
        return Dashboard(
            totalIncidents: storage.count,
            activeIncidents: storage.count - resolved.count,
            resolvedIncidents: resolved.count,
            mttrMinutes: mean,
            acknowledgementMinutes: 2.4,
            slaCompliancePercent: 96.8,
            slaTargetMinutes: 60,
            bySeverity: Severity.allCases.map { severity in SeverityCount(severity: severity, count: storage.filter { $0.severity == severity }.count) },
            dailyCounts: daily,
            services: Dictionary(grouping: storage, by: \.service).map { ServiceCount(service: $0.key, count: $0.value.count) }
                .sorted { $0.service < $1.service }
        )
    }

    public func search(query: String) async throws -> SearchResult {
        let page = try await incidents(status: nil, search: query, offset: 0)
        return SearchResult(items: page.items.map { SearchMatch(incident: $0, score: 0.85) }, mode: "lexical")
    }

    public func registerDevice(token _: String) async throws {}
    private func find(_ id: UUID) throws -> Incident {
        guard let incident = storage.first(where: { $0.id == id }) else { throw APIError.notFound }
        return incident
    }
}

public enum DemoData {
    public static let primaryID = UUID(uuidString: "A24F8100-6F08-4B76-B9EB-AB8DDACAF002")!
    public static func incidents(now: Date = Date()) -> [Incident] {
        [
            Incident(
                id: primaryID,
                title: "Checkout error rate above 5%",
                service: "checkout-api",
                severity: .critical,
                status: .investigating,
                description: "The checkout service is returning elevated 503 responses in eu-west-1. Error budget burn is 14.2x baseline following the latest deployment.",
                createdAt: now.addingTimeInterval(-1080),
                updatedAt: now,
                acknowledgedAt: now.addingTimeInterval(-960)
            ),
            Incident(
                id: UUID(uuidString: "B73E9200-6F08-4B76-B9EB-AB8DDACAF003")!,
                title: "Payment queue latency rising",
                service: "payments-worker",
                severity: .high,
                status: .open,
                description: "P95 job latency exceeded 30 seconds. Queue depth is growing and payment confirmations are delayed.",
                createdAt: now.addingTimeInterval(-420),
                updatedAt: now
            ),
            Incident(
                id: UUID(uuidString: "C82A3100-6F08-4B76-B9EB-AB8DDACAF004")!,
                title: "Search replica out of sync",
                service: "search-indexer",
                severity: .medium,
                status: .acknowledged,
                description: "Replica lag exceeded 90 seconds. Search results may temporarily omit recent catalog changes.",
                createdAt: now.addingTimeInterval(-2520),
                updatedAt: now,
                acknowledgedAt: now.addingTimeInterval(-2400)
            ),
            Incident(
                id: UUID(uuidString: "D11F4200-6F08-4B76-B9EB-AB8DDACAF005")!,
                title: "Edge cache hit ratio recovered",
                service: "edge-proxy",
                severity: .low,
                status: .resolved,
                description: "A cache key mismatch was corrected and hit ratio returned to normal.",
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-84900),
                acknowledgedAt: now.addingTimeInterval(-86280),
                resolvedAt: now.addingTimeInterval(-84900)
            )
        ]
    }
}
