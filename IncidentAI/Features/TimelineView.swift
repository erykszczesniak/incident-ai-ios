import IncidentCore
import SwiftUI

struct TimelineView: View {
    let id: UUID
    let api: any IncidentAPI
    @State private var state: LoadState<[TimelineEvent]> = .idle
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionTitle(title: "The response, in order.", subtitle: "A shared record for the next engineer on call.")
                Panel {
                    TextField("Add an observation or action…", text: $note, axis: .vertical).lineLimit(3 ... 6).accessibilityLabel("Timeline note")
                    HStack {
                        Text("Keep secrets out of notes.").font(.caption)
                            .foregroundStyle(Palette.muted); Spacer(); Button(saving ? "Adding…" : "Add note") { Task { await addNote() } }
                            .disabled(saving || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let error {
                        OperationNotice(message: error)
                    }
                }
                switch state {
                case .idle, .loading: LoadingView(title: "Loading the incident timeline")
                case let .failed(message): RecoveryView(message: message) { Task { await load() } }
                case let .loaded(events):
                    if events.isEmpty {
                        ContentUnavailableView(
                            "Start the record",
                            systemImage: "text.badge.plus",
                            description: Text("Add the first observation for this incident.")
                        )
                    }
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 8) {
                                Image(systemName: event.kind == "manual" ? "pencil.circle.fill" : "circle.inset.filled")
                                    .foregroundStyle(Palette.accent); Rectangle().fill(Palette.panelRaised).frame(
                                        width: 1,
                                        height: 40
                                    )
                            }.frame(width: 24)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(event.kind.capitalized).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent); Spacer(); Text(
                                    event.createdAt,
                                    format: .dateTime.hour().minute().second()
                                ).font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.muted) }
                                Text(event.message).font(.subheadline).textSelection(.enabled)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }.padding(20)
        }.commandBackground().navigationTitle("Timeline").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do { state = try await .loaded(api.timeline(id: id)) } catch { state = .failed(error.localizedDescription) }
    }

    private func addNote() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            _ = try await api.addEvent(id: id, message: note); note = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
}
