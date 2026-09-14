import Foundation
import MetricKit
import OSLog

protocol CrashReporting: Sendable {
    func recordCrashCount(_ count: Int)
}

struct LocalCrashReporter: CrashReporting {
    private let logger = Logger(subsystem: "com.erykszczesniak.IncidentAI", category: "diagnostics")
    func recordCrashCount(_ count: Int) {
        logger.error("System-reported crashes: \(count, privacy: .public)")
    }
}

@MainActor final class DiagnosticMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticMonitor()
    private var started = false
    private let reporter: any CrashReporting = LocalCrashReporter()
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let count = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        Task { @MainActor in self.reporter.recordCrashCount(count) }
    }
}
