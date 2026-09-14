import IncidentCore
import SwiftUI

struct PostmortemView: View {
    let id: UUID
    let api: any IncidentAPI
    @State private var state: LoadState<Postmortem?> = .idle
    @State private var draft = ""
    @State private var editing = false
    @State private var busy = false
    @State private var message: String?
    @State private var exportResult: ExportResult?
    @State private var destination: String?
    @State private var confirmExport = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OperationNotice(message: "A blameless working draft. Review impact, root cause and follow-up owners before sharing.")
                switch state {
                case .idle, .loading: LoadingView(title: "Preparing the incident record")
                case let .failed(error): RecoveryView(message: error) { Task { await load(generate: false) } }
                case let .loaded(postmortem):
                    if let postmortem {
                        content(postmortem)
                    } else {
                        ContentUnavailableView(
                            "Make the response reusable",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Build an editable postmortem from the incident, timeline and analysis.")
                        )
                        Button("Generate postmortem") { Task { await load(generate: true) } }.buttonStyle(PrimaryButton())
                    }
                }
                if let message {
                    OperationNotice(message: message)
                }
                if let result = exportResult, !result.isDemo, let url = URL(string: result.url), url.scheme == "https" {
                    Link("Open \(result.destination.capitalized) export", destination: url).buttonStyle(.bordered)
                }
            }.padding(20)
        }.commandBackground().navigationTitle("Postmortem").navigationBarTitleDisplayMode(.inline).task { await load(generate: false) }
            .confirmationDialog("Export reviewed postmortem?", isPresented: $confirmExport, titleVisibility: .visible) {
                Button("Export to \((destination ?? "jira").capitalized)") { Task { await export() } }
            } message: { Text("The saved version will be sent to your configured destination. Check the draft for sensitive content first.") }
    }

    @ViewBuilder private func content(_ postmortem: Postmortem) -> some View {
        HStack {
            Label("Version \(postmortem.version)", systemImage: "doc.badge.clock").font(.caption).foregroundStyle(Palette.muted)
            Spacer()
            Button(editing ? "Cancel editing" : "Edit draft") { draft = postmortem.markdown; editing.toggle() }.font(.subheadline)
        }
        if editing {
            TextEditor(text: $draft).font(.system(.subheadline, design: .monospaced)).scrollContentBackground(.hidden).frame(minHeight: 420).padding(12)
                .background(
                    Palette.panel,
                    in: RoundedRectangle(cornerRadius: 16)
                ).accessibilityLabel("Postmortem Markdown draft")
            Button(busy ? "Saving…" : "Save changes") { Task { await save() } }.buttonStyle(PrimaryButton())
                .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
            Panel { Text(LocalizedStringKey(postmortem.markdown)).font(.subheadline).lineSpacing(6).textSelection(.enabled).frame(
                maxWidth: .infinity,
                alignment: .leading
            ) }
            HStack {
                Button { destination = "jira"; confirmExport = true } label: { Label("Jira", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton())
                Button { destination = "confluence"; confirmExport = true } label: { Label("Confluence", systemImage: "doc.on.doc") }
                    .buttonStyle(PrimaryButton())
            }.disabled(busy)
            if busy {
                ProgressView("Export in progress")
            }
            ShareLink(item: postmortem.markdown) { Label("Share Markdown", systemImage: "square.and.arrow.up") }.font(.subheadline).frame(maxWidth: .infinity)
        }
    }

    private func load(generate: Bool) async {
        state = .loading
        do {
            let value = try await api.postmortem(id: id, generate: generate); draft = value.markdown; state = .loaded(value)
        } catch APIError.notFound where !generate {
            state = .loaded(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            state = try await .loaded(api.savePostmortem(id: id, markdown: draft)); editing = false; message = "Changes saved."
        } catch { message = error.localizedDescription }
    }

    private func export() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            let result = try await api.export(id: id, destination: destination ?? "jira")
            exportResult = result
            message = result.isDemo ? "Demo export completed. No external issue or page was created." : "Exported to \(result.destination.capitalized): \(result.externalId)."
        } catch { message = error.localizedDescription }
    }
}

private struct MarkdownDocument: View {
    let markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("# ") {
                    Text(String(line.dropFirst(2))).font(.title2.weight(.bold)).padding(.bottom, 4)
                } else if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3))).font(.headline).padding(.top, 10)
                } else if line.hasPrefix("> ") {
                    Text(String(line.dropFirst(2))).font(.footnote).foregroundStyle(Palette.muted)
                } else if !line.isEmpty {
                    Text((try? AttributedString(markdown: line)) ?? AttributedString(line)).font(.subheadline).lineSpacing(4)
                }
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
