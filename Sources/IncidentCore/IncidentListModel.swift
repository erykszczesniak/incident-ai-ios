import Foundation
import Observation

@MainActor @Observable
public final class IncidentListModel {
    public private(set) var state: LoadState<[Incident]> = .idle
    public private(set) var total = 0
    public private(set) var isLoadingMore = false
    public private(set) var paginationError: String?
    private let api: any IncidentAPI
    private var generation = 0
    private var filter: String? = "active"
    private var query = ""

    public init(api: any IncidentAPI) {
        self.api = api
    }

    public func load(status: String? = "active", search: String = "") async {
        generation += 1
        let requestGeneration = generation
        filter = status
        query = search
        state = .loading
        do {
            let page = try await api.incidents(status: status, search: search, offset: 0)
            guard generation == requestGeneration else { return }
            total = page.total
            state = .loaded(sorted(page.items))
        } catch {
            guard generation == requestGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, let current = state.value, current.count < total else { return }
        isLoadingMore = true
        paginationError = nil
        defer { isLoadingMore = false }
        let requestGeneration = generation
        do {
            let page = try await api.incidents(status: filter, search: query, offset: current.count)
            guard generation == requestGeneration else { return }
            state = .loaded(sorted(current + page.items.filter { item in !current.contains(where: { $0.id == item.id }) }))
        } catch {
            paginationError = error.localizedDescription
        }
    }

    private func sorted(_ incidents: [Incident]) -> [Incident] {
        incidents.sorted { left, right in
            left.severity.rank == right.severity.rank ? left.createdAt > right.createdAt : left.severity.rank < right.severity.rank
        }
    }
}
