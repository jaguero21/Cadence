# Cadence — Xcode Setup Guide

Most of this project's capabilities (HealthKit, CloudKit, App Groups, assets)
are already configured in the checked-in project and entitlements — cloning
the repo and opening it in Xcode gets you most of the way there. The steps
below cover what's still developer-specific: your own signing team, and (if
you want CloudKit sync or in-app purchases to actually work end to end under
your own Apple Developer account) your own container/App Group/products.

---

## 1. Set Your Development Team

**Why:** Xcode requires a signing identity to install the app on a physical
device. The team ID checked into the project (`4NWCR79S38`) is the original
developer's — you can't reuse it.

1. Open `Cadence.xcodeproj` in Xcode
2. In the Project Navigator, click the **Cadence** project (top of the file
   tree, blue icon)
3. Repeat for each target under TARGETS — **Cadence**, **CadenceWidgetExtension**,
   **CadenceWidget Watch App**, and **CadenceTests**:
   - Open the **Signing & Capabilities** tab
   - Under **Signing**, set **Team** to your Apple Developer account
     - If none appear, go to **Xcode → Settings → Accounts** and sign in
       with your Apple ID
     - A free Apple ID works for on-device testing without CloudKit/StoreKit;
       a paid developer account ($99/yr) is required for CloudKit, push,
       and App Store submission
4. Xcode will auto-generate provisioning profiles — each target's "Signing
   Certificate" field should show your name and turn green

---

## 2. HealthKit — already configured

**Why:** HealthKit access requires an explicit entitlement in addition to
`Info.plist` usage descriptions. Both are already in place:

- `Cadence/Cadence.entitlements` already declares
  `com.apple.developer.healthkit` and
  `com.apple.developer.healthkit.background-delivery`
- `Cadence/App/Info.plist` already has `NSHealthShareUsageDescription` and
  `NSHealthUpdateUsageDescription`

Nothing to do here unless Xcode strips the capability during re-signing —
if so, re-add it via **Signing & Capabilities → + Capability → HealthKit**
on the **Cadence** target and confirm the entitlements file is unchanged.

---

## 3. CloudKit sync and App Groups — need your own identifiers

**Why:** `Cadence.entitlements` requests the iCloud container
`iCloud.com.carpecadence.app` and CloudKit service, and both the app and
`CadenceWidgetExtension.entitlements` share the App Group
`group.com.carpecadence.app` (the app↔widget bridge — see
[CLAUDE.md](CLAUDE.md)'s Widget section). These identifiers are registered
under the original developer's account; you can't provision against them.

1. In **Signing & Capabilities**, if iCloud/App Groups show a provisioning
   error, either:
   - Ask to be added as a team member on the existing developer account
     (identifiers stay as-is), **or**
   - Change the container/group identifiers to ones registered under your
     own account (update `Cadence.entitlements` and
     `CadenceWidgetExtension.entitlements`, and the corresponding strings in
     `WidgetData.appGroup` and `CadenceApp.swift`'s CloudKit container config)
2. This is **not launch-blocking either way**: `sharedModelContainer` (see
   `CadenceApp.swift`) falls back from CloudKit-mirrored storage to a
   local-only store, then in-memory, so the app still runs without a working
   iCloud entitlement — sync just won't happen.

---

## 4. StoreKit Product IDs and a Testing Config

**Why:** `StoreService` references two product identifiers that must match
what's registered in App Store Connect (or a local StoreKit config for
testing).

### Step A — Confirm the product IDs in code

[Cadence/Shared/Constants.swift](Cadence/Shared/Constants.swift) already
defines the real IDs — only change these if you're shipping under a
different bundle prefix:

```swift
enum StoreKitID {
    static let proOneTime = "com.carpecadence.pro.lifetime"
    static let proMonthly = "com.carpecadence.pro.monthly"
}
```

### Step B — Local StoreKit config

A local config already exists at `Cadence/CarpeCadence.storekit`, with
product IDs matching `StoreKitID` above — it just isn't attached to the
`Cadence` scheme by default. To use it:

1. **Product → Scheme → Edit Scheme → Run → Options → StoreKit
   Configuration → CarpeCadence.storekit**

### Step C — Register in App Store Connect (before release)

1. Log in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Create a new app with bundle ID `com.carpecadence.app`
3. Go to **In-App Purchases** and create the same two products with
   matching IDs (`com.carpecadence.pro.lifetime`, `com.carpecadence.pro.monthly`)

---

## 5. App icon and accent color — already configured

**Why:** `CadenceColor.accent` and the App Store icon both reference assets
in `Cadence/Assets.xcassets`, which already has an `AccentColor` color set
and a filled-in `AppIcon` — nothing to add before your first build.

To adjust the palette, edit the existing color sets (`AccentColor`,
`MoodBlue`, `EnergyOrange`, `SleepPurple`, `StressRed`, `SuccessGreen` —
see CLAUDE.md's Styling convention) rather than adding new ones inline in
view code.

---

## 6. Build and Run

**Why:** Confirms signing and capabilities are wired up correctly before
writing more code.

### Simulator (no paid account required)

1. Choose an iPhone 15 or later simulator from the device picker (top-center
   toolbar)
2. Press **⌘R** — the app should build and launch
3. Walk through the daily log flow and confirm SwiftData persistence works
   (close the app, reopen, log reappears)
4. HealthKit and the paired-watch quick-log flow can't be exercised in the
   Simulator alone — HealthKit needs a device, and WatchConnectivity needs a
   paired iPhone + Watch simulator (or two real devices)

### Physical device

1. Connect your iPhone via USB
2. Trust the Mac on the device if prompted
3. Select your device from the picker
4. Press **⌘R** — Xcode installs the app
5. On first launch, go to **Settings → General → VPN & Device Management**
   on the iPhone and trust your developer certificate

### Smoke-test checklist

- [ ] App launches without crash
- [ ] Tab bar shows all 5 tabs (Today, Log, Review, Insights, History)
- [ ] Tapping **Today's Log** opens the card-by-card input flow
- [ ] Completing a log saves it and shows it in the History calendar
- [ ] HealthKit permission sheet appears on first launch (device only)
- [ ] Settings tab loads without crash

---

## Troubleshooting

| Issue | Fix |
|---|---|
| "No signing certificate" | Sign in to Xcode → Settings → Accounts, then re-select your team on every target (app, widget extension, watch app, tests) |
| `HKHealthStore` crash on simulator | HealthKit is not available in the Simulator — guard calls with `HealthKitService.shared.isAvailable` (already done) |
| CloudKit/App Group provisioning errors | You need your own iCloud container / App Group, or team access to the existing one — see Step 3 |
| StoreKit products not loading | Confirm the StoreKit config is attached to the Run scheme, and that its product IDs match `StoreKitID` (Step 4B) |
| SwiftData migration error | Delete the app from the simulator/device to reset the store during development |
