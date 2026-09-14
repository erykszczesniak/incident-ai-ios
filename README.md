# Incident AI for iOS

A native incident command workspace for on-call engineers. SwiftUI, Swift Concurrency and Charts keep the response focused on context, evidence and recovery.

The app launches into a working demo workspace. It also connects to the separate [Incident AI backend](https://github.com/erykszczesniak/incident-ai-backend).

## Run

Requirements: Xcode 16 or later, iOS 18 or later, Swift 6, XcodeGen. This checkout was built and tested with Xcode 26.6 and iOS Simulator 26.5.

```sh
brew install xcodegen swiftlint swiftformat
xcodegen generate
open IncidentAI.xcodeproj
```

Select the `IncidentAI` scheme and an iPhone simulator, then Run. No account, API credentials or signing team is needed for the simulator demo.

To connect to the local backend:

1. Clone and start the [backend](https://github.com/erykszczesniak/incident-ai-backend) using its README or Docker Compose.
2. Open Settings in the app and disable Demo workspace.
3. Enter `http://127.0.0.1:8000` and the demo API key `incident-ai-demo-key`.
4. Save the connection, then test it. Return to Incidents.

The iPhone simulator shares the Mac's loopback network. A physical iPhone requires an HTTPS server accessible from the phone. Production API keys belong in the device Keychain, never in source files. The client rejects remote plaintext HTTP URLs.

For debug simulator automation, `INCIDENT_AI_LIVE_URL` and `INCIDENT_AI_API_KEY` environment variables override launch configuration without persisting credentials. These overrides are compiled out of Release builds.

## Included functionality

- Active/all incident list with search, pagination, pull-to-refresh, severity ordering and explicit recovery states.
- Incident detail, source alerts, redacted logs, acknowledgement, investigation and resolution.
- Structured assistive analysis: summary, probable cause, evidence, suggested response, confidence caveat and fallback/demo labels.
- Incident timeline with manual notes.
- Generated, editable Markdown postmortems, versioned saves, share sheet and explicit Jira/Confluence export. The app labels simulated exports and does not present a demo URL as a real external issue.
- Thirty-day SLA, acknowledgement, recovery time, severity and service metrics with Charts. Missing measurements display “No data”.
- APNs registration with notification deep links. API keys stay in Keychain; logs include operational names and error types rather than incident content.
- MetricKit crash diagnostics behind a `CrashReporting` interface. Only local crash counts are recorded; there is no external tracking or crash upload service.

## Architecture

`Sources/IncidentCore` is a standalone Swift package containing Codable/Sendable contract models, the `IncidentAPI` protocol, live URLSession actor, mutable demo actor, deep-link validation and the observable list model. The app composes one API implementation in `AppModel` and injects it into feature models/views.

`IncidentAI/Features` contains the SwiftUI screens and detail view model. `DesignSystem` defines the navy incident console palette, severity badges, panels and loading/retry presentations. Native semantic fonts, text selection, VoiceOver labels and scrollable layouts support accessibility and larger text. `Core` handles Keychain, local telemetry, diagnostics, push registration, WatchConnectivity and widget snapshots.

The network boundary uses snake-case decoding, UTC timestamps with or without fractional seconds, canonical lowercase UUID paths, typed server errors and correlation IDs. The app sends no automatic mutations on HTTP failure. Retrying analysis is an explicit engineer action. Postmortem export requires an in-app review confirmation.

The mock actor keeps workflow changes in memory for the current launch, including status, timeline, generated analysis and edited postmortems. It never sends requests to external integrations. Demo snapshots reset after restarting or reselecting the demo workspace.

The shared [API contract](docs/API-CONTRACT.md) is included in this repository.

## Extended Apple surfaces

### WidgetKit and Live Activities

The `IncidentAIWidgets` extension is embedded in the default iOS build. It includes an on-call snapshot widget and a timer-based incident Live Activity. Add the widget from the system widget gallery. In incident detail, choose Follow on Lock Screen. Resolving an incident ends its activity.

Widgets use the app group `group.com.erykszczesniak.IncidentAI` and refresh from the most recently opened active incident list. They are cached snapshots, not an independent background monitor. Live Activity timers use the original incident timestamp; they are not aggregate MTTR. Server-side activity push updates are not implemented.

### Apple Watch

`IncidentAIWatch` is a real watchOS target and scheme. It receives active incident snapshots from the iPhone using WatchConnectivity, caches them, and sends acknowledgement actions to the phone. The iPhone must be reachable to acknowledge. It never copies API credentials to the watch.

The default Xcode project keeps watch embedding optional so an absent watchOS runtime does not block the iOS app. To embed the watch companion after installing the watchOS platform in Xcode Settings > Components:

```sh
xcodegen generate --spec project-with-watch.yml
```

Use the `IncidentAI` scheme with a paired iPhone/watch simulator or signed devices. Restore the default project with `xcodegen generate`. The watch target was compiled against the installed watchOS SDK. Watch UI, pairing and acknowledgement delivery were not run because no watchOS runtime is installed in this environment.

### Real APNs setup

Set a development team for all targets in Xcode and enable Push Notifications plus the matching App Group. Configure the backend APNs key, team ID, key ID and bundle ID `com.erykszczesniak.IncidentAI`. Enable incident notifications in app Settings. Debug registers sandbox tokens; Release registers production tokens. The notification payload must include a top-level `incident_id` UUID. Deep links also accept `incidentai://incident/<uuid>`.

Real APNs delivery requires Apple signing credentials and an APNs-enabled installation. It was not tested here. Notification authorization is requested only from the Settings action.

## Quality checks

```sh
swift test
swiftlint lint --strict --no-cache
swiftformat . --lint --cache ignore
xcodegen generate
xcodebuild -project IncidentAI.xcodeproj -scheme IncidentAI \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project IncidentAI.xcodeproj -scheme IncidentAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO test
```

The opt-in contract test uses the running local demo backend, reads its seeded incidents, and generates analysis/postmortem drafts on the first incident:

```sh
INCIDENT_AI_TEST_SERVER=http://127.0.0.1:8000 swift test
```

Use `INCIDENT_AI_TEST_KEY` when the demo API key differs. Never target a production workspace with this mutation-enabled test.

Watch compile without requiring a simulator runtime:

```sh
xcodebuild -project IncidentAI.xcodeproj -target IncidentAIWatch -sdk watchos \
  -configuration Debug SYMROOT=$PWD/build-watch/Products \
  OBJROOT=$PWD/build-watch/Intermediates CODE_SIGNING_ALLOWED=NO build
```

Local verification: 14 Swift package tests including the real backend contract, 2 native XCTest cases, iOS app/widget build, watchOS target compile, strict SwiftLint and SwiftFormat checks passed. GitHub Actions CI is configured but has not been executed on a remote repository.

Screenshots from the running simulator are in `docs/screenshots`. `incidents.png` shows the demo workspace; `live-incident.png` shows a real incident served by the local backend.
