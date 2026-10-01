# Cadence

A native SwiftUI + SwiftData iOS app for daily symptom, mood, and energy
tracking — built for people managing a chronic condition who need to spot
patterns and bring something concrete to a doctor's appointment.

A log takes about 2 minutes, HealthKit fills in what it can, and an on-device
pattern engine (no ML, no server) surfaces correlations like "your headaches
follow poor sleep" or "symptoms rise before this flare." Everything exports
to a doctor-ready PDF or a spreadsheet.

## Features

- **Daily Log** — mood, energy, sleep, pain, brain fog, anxiety, symptoms,
  contextual factors, free-form + voice notes, photo attachments
- **Weekly Review** — guided reflection prompts, Intentions for Tomorrow
- **Custom Trackers** — user-defined metrics beyond the built-in set
- **Flares** — multi-day symptom episode tracking with precursor detection
  (stress, sleep, wrist temperature, respiratory rate, daylight)
- **Medications** — course tracking, symptom-effect correlation, daily
  reminder notifications with an idempotent reconcile sweep
- **Pattern Insights** — on-device, deterministic, confidence-scored
  (Wilson lower bound) correlation detection; every card is explainable
- **HealthKit** — two-way sync (mapped symptoms, State of Mind mood),
  background delivery, always optional/supplementary — never gates a
  core feature or overwrites a user-entered value
- **Export** — a doctor-ready PDF report (trend charts, symptom frequency,
  pattern flags; personal notes optional) and CSV, previewed in-app before
  sharing
- **iCloud sync** — CloudKit-mirrored SwiftData store, plus a JSON
  backup/restore that merges rather than overwrites
- **Apple Watch** — wrist quick-log (mood + energy) over WatchConnectivity
- **Widgets** — Home Screen, Lock Screen, StandBy, and a Control Center
  quick check-in button
- **Siri / Shortcuts** — App Intents for a spoken check-in
- **iPad** — adaptive layout, all four orientations, Stage Manager support
- **Localization** — English and Spanish
- **Accessibility** — full VoiceOver labeling on every custom control,
  Reduce Motion support throughout

## Tech stack

- SwiftUI, SwiftData (iOS 17+)
- CloudKit (`NSPersistentCloudKitContainer` via SwiftData), with automatic
  fallback to local-only or in-memory storage
- HealthKit, with background delivery
- WidgetKit — Home Screen, Lock Screen/StandBy accessory families, Control
  Center (iOS 18+)
- WatchConnectivity (watchOS 26.2+)
- App Intents (Siri Shortcuts)
- PDFKit, Swift Charts
- StoreKit 2 — freemium, a lifetime purchase or monthly subscription unlock
  Pro features; receipt state is never trusted from the client alone
- Swift Testing for unit tests; XCTest/XCUIApplication for the UI smoke test

## Project structure

```
Cadence/
  App/            App entry point, root ContentView, App Intents
  Features/       One folder per tab/screen (Dashboard, DailyLog,
                   WeeklyReview, Insights, History, Export, Settings)
  Models/         SwiftData @Model classes + their Sendable snapshots
  Services/       HealthKit, Notifications, PatternEngine, Backup,
                   CloudSync — concrete singletons behind protocols
  Shared/         Cross-cutting extensions, reusable components, constants
CadenceWidget/                Home Screen + Lock Screen/StandBy widget
CadenceWidget Watch App/      watchOS quick-log app
CadenceTests/                 Swift Testing unit tests
CadenceUITests/               XCUIApplication smoke test
```

See [CLAUDE.md](CLAUDE.md) for the full architecture writeup — data flow,
the app↔widget↔watch bridges, CloudKit constraints, and the conventions
behind each of the above.

## Requirements

- Xcode 27 (Swift 6 language mode, iOS 27 SDK). The app deploys to iOS 17+;
  the widget extension and Watch app target 26.4 / 26.2
- An Apple Developer account for HealthKit, CloudKit, and push entitlements
  (a free account covers on-device testing; a paid account is required for
  CloudKit and App Store submission)

## Setup

See [SETUP.md](SETUP.md) for signing, the HealthKit capability, StoreKit
product configuration, and an accent-color asset — needed before the first
build to a device.

```sh
open Cadence.xcodeproj
```

Then build the `Cadence` scheme (⌘R). The Simulator works for most flows;
HealthKit and WatchConnectivity need a physical device (or a paired
device+watch simulator) to verify end to end.

## Testing

```sh
xcodebuild test -scheme Cadence
```

or ⌘U in Xcode, using the `Cadence.xctestplan` test plan. GitHub Actions
(`.github/workflows/ci.yml`) runs the same command on every push.

## Status

In active development.

## License

Copyright © 2026 James Aguero.

Cadence's source code is free software: you can redistribute it and/or modify
it under the terms of the **GNU General Public License, version 3** (see
[`LICENSE`](LICENSE)). It is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.

**The name, icon and artwork are not covered.** The GPL licenses the code.
The "Cadence" name, the app icon, the capybara mascot illustrations and other
brand artwork remain © James Aguero, all rights reserved. A fork must use its
own name and artwork.

**The App Store build.** As the copyright holder, the author distributes the
official Cadence app through Apple's App Store under Apple's terms. That
permission belongs to the copyright holder; it is not a grant under the GPL.

## Contributing

Issues and pull requests are welcome. By submitting a contribution, you agree
that it is licensed under GPL-3.0. You also grant James Aguero a perpetual,
irrevocable, worldwide, royalty-free right to distribute it under other terms,
including as part of the App Store build. Without that grant, contributed code
could not ship in the official app.
