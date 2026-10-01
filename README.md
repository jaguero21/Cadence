# Cadence

[![CI](https://github.com/jaguero21/Cadence/actions/workflows/ci.yml/badge.svg)](https://github.com/jaguero21/Cadence/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-iOS%2017%2B%20%C2%B7%20iPadOS%20%C2%B7%20watchOS-lightgrey)

A private, on-device iOS app for daily symptom, mood, energy and sleep
tracking. It's built for people managing a chronic condition who want to
spot patterns and bring something concrete to a doctor's appointment.

A check-in takes about 2 minutes, and Apple Health fills in what it can. An
on-device pattern engine (deterministic, no server) surfaces correlations such
as "your headaches follow poor sleep" or "symptoms rise before a flare."
Everything exports to a doctor-ready PDF or a spreadsheet.

**Website:** <https://jaguero21.github.io/Cadence/> ·
[Privacy Policy](https://jaguero21.github.io/Cadence/privacy-policy.html) ·
[Terms of Use](https://jaguero21.github.io/Cadence/eula.html)

## Features

### Free
- **Daily Log**: mood, energy, sleep, pain, brain fog, anxiety, symptoms with
  severity, triggers, daily basics, reflections, voice notes and photos.
  Fill in a missed day or edit any past day from History.
- **Personalized onboarding**: pick the symptoms you track and a reminder
  time, connect Apple Health (optional), and go straight into the first log.
- **Smart reminders**: a daily check-in nudge at your chosen time that skips
  days you've already logged, plus weekly-review and medication reminders.
- **Weekly Review**: guided prompts and Intentions for Tomorrow, with an
  on-device **Week Reflection** summary on iOS 26+ (Apple Foundation Models).
  It never summarizes self-harm language and shows support resources instead.
- **Trends**: 7- and 30-day charts that plot only values you actually entered.
- **Custom trackers, medications and flares**, including flare precursor
  detection (stress, sleep, wrist temperature, respiratory rate).
- **Apple Health**: two-way sync (mapped symptoms, State of Mind mood) that is
  always optional and never overwrites what you typed.
- **Spreadsheet (CSV) export** and a JSON backup/restore that merges rather
  than overwrites.
- **Apple Watch** quick log, **widgets** (Home Screen, Lock Screen, StandBy,
  Control Center) and a **Siri** check-in.
- **iPad**: adaptive layout, all orientations, Stage Manager.
- **English and Spanish**, full VoiceOver support, Dynamic Type and Reduce
  Motion throughout.

### Cadence Pro (lifetime purchase or monthly subscription)
- **Pattern insights**: correlations between sleep, mood, stress, symptoms,
  triggers, medications and Health data, each rated *emerging*, *moderate* or
  *strong* and explained in plain language.
- **Pattern alerts**: a notification when a new pattern appears, plus a
  history of every pattern.
- **90-day trends.**
- **Doctor-ready PDF report**: clinical sections first (patterns, charts,
  averages, symptoms, medications, flares), personal notes only when you
  include them. Covers any date range or "since last appointment," on US
  Letter or A4.

## Privacy by design

- **No servers, accounts, analytics or third-party SDKs.**
- Your entries live on your device and in your own private iCloud database
  (CloudKit), which only you can read.
- **Health data stays local.** Values read from Apple Health live in a
  separate, local-only store that is never synced to iCloud (App Review
  Guideline 5.1.3).
- Purchases are verified on device with StoreKit 2's signed transactions.
- Exports are written with complete file protection and cleared on the
  next launch.

## Tech stack

- Swift 6, SwiftUI, SwiftData (iOS 17+)
- CloudKit mirroring via SwiftData, with automatic fallback to local-only or
  in-memory storage; a second, local-only store for Health data
- HealthKit with background delivery and two-way sync
- Foundation Models (on-device Week Reflection, iOS 26+)
- WidgetKit (Home Screen, accessory families, Control Center), App Intents
  (Siri / Shortcuts), WatchConnectivity
- Swift Charts and PDFKit for reports
- StoreKit 2: a lifetime purchase or monthly subscription, verified on device
  from signed transactions, with free-trial wording read from StoreKit at
  runtime
- Swift Testing for unit tests; XCTest for UI tests

## Project structure

```
Cadence/
  App/            App entry point, root ContentView, App Intents
  Features/       One folder per area: Onboarding, Dashboard, DailyLog,
                  WeeklyReview, Insights, History, Export, Settings
  Models/         SwiftData @Model classes and their Sendable snapshots
  Services/       HealthKit, Notifications, PatternEngine, Store, Backup,
                  CloudSync, Week Reflection
  Shared/         Cross-cutting extensions, reusable components, constants
CadenceWidget/                Widgets, Control Center control, quick-log intent
CadenceWidget Watch App/      watchOS quick-log app
CadenceTests/                 Swift Testing unit tests
CadenceUITests/               UI smoke test and opt-in App Store screenshot capture
docs/                         The GitHub Pages website
```



## Requirements

- **Xcode 27** (Swift 6 language mode, iOS 27 SDK). The app deploys to iOS
  17+; the widget extension and Watch app target 26.4 / 26.2.
- An Apple Developer account for HealthKit, CloudKit and push entitlements. A
  free account covers on-device testing; a paid account is required for
  CloudKit and App Store submission.

## Setup

See [SETUP.md](SETUP.md) for signing, capabilities, StoreKit products and the
other developer-specific steps needed before the first build to a device.

```sh
open Cadence.xcodeproj
```

Build the `Cadence` scheme (⌘R). The Simulator covers most flows; HealthKit
and Watch connectivity need a physical device (or a paired device and watch
simulator) to verify end to end. To test purchases locally, select
`Cadence/CarpeCadence.storekit` under **Edit Scheme → Run → Options →
StoreKit Configuration**.

## Testing

```sh
xcodebuild test -scheme Cadence -testPlan Cadence
```

or ⌘U in Xcode. There are ~350 unit tests plus a UI smoke test that walks
onboarding into a first completed log. CI (`.github/workflows/ci.yml`) runs on
every push and fails on any test failure, a drop below the minimum test count,
or **any compiler warning** in the app, widget or watch targets.

App Store screenshots come from an opt-in UI test:

```sh
TEST_RUNNER_CADENCE_SCREENSHOTS=1 xcodebuild test -scheme Cadence -testPlan Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:CadenceUITests/ScreenshotTests -resultBundlePath Screens.xcresult
xcrun xcresulttool export attachments --path Screens.xcresult --output-path Screens
```

## Status

Version 1.0 has been submitted to the App Store, and development is ongoing.

## License

Copyright © 2026 the Cadence authors.

Cadence's source code is free software: you can redistribute it and/or modify
it under the terms of the **GNU General Public License, version 3** (see
[`LICENSE`](LICENSE)). It is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.

**The name, icon and artwork are not covered.** The GPL licenses the code.
The "Cadence" name, the app icon, the capybara mascot illustrations and other
brand artwork remain © the Cadence authors, all rights reserved. A fork must
use its own name and artwork.

**The App Store build.** As the copyright holders, the Cadence authors
distribute the official Cadence app through Apple's App Store under Apple's
terms. That permission belongs to the copyright holders; it is not a grant
under the GPL.

## Contributing

Issues and pull requests are welcome. By submitting a contribution, you agree
that it is licensed under GPL-3.0. You also grant the Cadence authors a
perpetual, irrevocable, worldwide, royalty-free right to distribute it under
other terms, including as part of the App Store build. Without that grant, contributed code
could not ship in the official app.
