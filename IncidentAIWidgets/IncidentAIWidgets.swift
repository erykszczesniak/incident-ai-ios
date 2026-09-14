import ActivityKit
import SwiftUI
import WidgetKit

struct IncidentEntry: TimelineEntry {
    let date: Date
    let count: Int
    let title: String
    let incidentID: String
    let updated: Date?
}

struct IncidentProvider: TimelineProvider {
    func placeholder(in _: Context) -> IncidentEntry {
        .init(date: .now, count: 3, title: "Checkout error rate above 5%", incidentID: "", updated: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping (IncidentEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<IncidentEntry>) -> Void) {
        completion(Timeline(
            entries: [read()],
            policy: .after(.now.addingTimeInterval(900))
        ))
    }

    private func read() -> IncidentEntry {
        let defaults = UserDefaults(suiteName: "group.com.erykszczesniak.IncidentAI")
        return .init(
            date: .now,
            count: defaults?.integer(forKey: "activeCount") ?? 0,
            title: defaults?.string(forKey: "topTitle") ?? "Open Incident AI to sync",
            incidentID: defaults?.string(forKey: "topID") ?? "",
            updated: defaults?.object(forKey: "updatedAt") as? Date
        )
    }
}

struct OnCallWidget: Widget {
    let kind = "OnCallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IncidentProvider()) { entry in
            VStack(alignment: .leading, spacing: 9) {
                Label("Incident AI", systemImage: "waveform.path.ecg").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                Text("\(entry.count) active").font(.title2.weight(.bold))
                Text(entry.title).font(.caption).lineLimit(2)
                if let updated = entry
                    .updated
                {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                }
            }.containerBackground(Color(red: 0.035, green: 0.065, blue: 0.115), for: .widget)
                .widgetURL(URL(string: "incidentai://incident/\(entry.incidentID)"))
        }.configurationDisplayName("On-call glance").description("Your latest open incident snapshot.").supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct IncidentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IncidentActivityAttributes.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Label(context.state.status, systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(.cyan)
                    Text(context.attributes.title).font(.headline).lineLimit(2)
                    Text(context.attributes.service).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.attributes.startedAt, style: .timer).font(.title3.monospacedDigit()).foregroundStyle(.cyan)
            }.padding().activityBackgroundTint(Color(red: 0.035, green: 0.065, blue: 0.115))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.service, systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.startedAt, style: .timer).monospacedDigit().foregroundStyle(.cyan) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.attributes.title).font(.headline) }
            } compactLeading: { Image(systemName: "waveform.path.ecg").foregroundStyle(.cyan) }
                compactTrailing: { Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 56) }
                minimal: { Image(systemName: "waveform.path.ecg").foregroundStyle(.cyan) }
                .widgetURL(URL(string: "incidentai://incident/\(context.attributes.incidentID)"))
        }
    }
}

@main struct IncidentWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnCallWidget(); IncidentLiveActivity()
    }
}
