# Cadence — Xcode Setup Guide

Complete these five steps before building to a device or submitting to the App Store.

---

## 1. Set Your Development Team

**Why:** Xcode requires a signing identity to install the app on a physical device.

1. Open `Cadence.xcodeproj` in Xcode
2. In the Project Navigator, click the **Cadence** project (top of the file tree, blue icon)
3. Select the **Cadence** target under TARGETS
4. Open the **Signing & Capabilities** tab
5. Under **Signing**, set **Team** to your Apple Developer account
   - If none appear, go to **Xcode → Settings → Accounts** and sign in with your Apple ID
   - A free Apple ID works for device testing; a paid developer account ($99/yr) is required for App Store submission
6. Xcode will auto-generate a provisioning profile — the "Signing Certificate" field should show your name and turn green

---

## 2. Add the HealthKit Capability

**Why:** HealthKit access requires an explicit entitlement in addition to the `Info.plist` usage descriptions (already included).

1. With the **Cadence** target selected, stay on the **Signing & Capabilities** tab
2. Click **+ Capability** (top-left of the tab)
3. Search for **HealthKit** and double-click it to add
4. In the new HealthKit section that appears, check **Health Records** only if you intend to read clinical records — leave it unchecked for now
5. Confirm `Cadence.entitlements` appears in the Project Navigator (Xcode creates it automatically)
6. Verify the two `Info.plist` keys are present (they are — already added):
   - `NSHealthShareUsageDescription`
   - `NSHealthUpdateUsageDescription`

---

## 3. Add StoreKit Product IDs and a Testing Config

**Why:** The `StoreService` references two product identifiers that must match what you register in App Store Connect (or a local StoreKit config for testing).

### Step A — Update the product IDs in code

Open [Cadence/Shared/Constants.swift](Cadence/Shared/Constants.swift) and set your actual bundle-prefixed IDs:

```swift
enum StoreKitID {
    static let proOneTime = "com.cadence.app.pro.lifetime"   // ← your real ID
    static let proMonthly = "com.cadence.app.pro.monthly"    // ← your real ID
}
```

### Step B — Create a local StoreKit configuration file for testing

1. In Xcode, go to **File → New → File**
2. Filter for **StoreKit Configuration File**, click Next
3. Name it `Cadence.storekit`, save it inside the `Cadence/` folder
4. Click **+** in the StoreKit editor to add products:
   - **Non-Consumable** → ID: `com.cadence.app.pro.lifetime`, Reference Name: `Pro Lifetime`, Price: $9.99
   - **Auto-Renewable Subscription** → ID: `com.cadence.app.pro.monthly`, Reference Name: `Pro Monthly`, Price: $2.99/mo
5. Attach the config to your scheme: **Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → Cadence.storekit**

### Step C — Register in App Store Connect (before release)

1. Log in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Create a new app with bundle ID `com.cadence.app`
3. Go to **In-App Purchases** and create the same two products with matching IDs

---

## 4. Add an Accent Color in Assets

**Why:** `CadenceColor.accent` references an asset named `"AccentColor"` — without it the app compiles but tint falls back to system blue.

1. In the Project Navigator, look for `Assets.xcassets` — if it's missing:
   - **File → New → File → Asset Catalog**, name it `Assets`, save inside `Cadence/`
   - In the target's **Build Settings**, set `ASSETCATALOG_COMPILER_APPICON_NAME` = `AppIcon` and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` = `AccentColor`
2. Open `Assets.xcassets`
3. Click **+** at the bottom → **New Color Set**
4. Rename it `AccentColor`
5. Click the color swatch in the **Any Appearance** slot and pick your brand color
   - Suggested: a calm teal or indigo — something that reads well on white and dark backgrounds
6. Add a **Dark Appearance** variant if you want a different shade in dark mode

> **Tip:** Also add an `AppIcon` image set here before App Store submission. Xcode 15+ can generate all required sizes from a single 1024×1024 PNG.

---

## 5. Build and Run

**Why:** Confirms signing, capabilities, and assets are wired up correctly before writing more code.

### Simulator (no account required)

1. Choose an iPhone 15 or later simulator from the device picker (top-center toolbar)
2. Press **⌘R** — the app should build and launch
3. Walk through the daily log flow and confirm SwiftData persistence works (close the app, reopen, log reappears)

### Physical device

1. Connect your iPhone via USB
2. Trust the Mac on the device if prompted
3. Select your device from the picker
4. Press **⌘R** — Xcode installs the app
5. On first launch, go to **Settings → General → VPN & Device Management** on the iPhone and trust your developer certificate

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
| "No signing certificate" | Sign in to Xcode → Settings → Accounts, then re-select your team |
| `HKHealthStore` crash on simulator | HealthKit is not available in the Simulator — guard calls with `HealthKitService.shared.isAvailable` (already done) |
| StoreKit products not loading | Confirm the StoreKit config is attached to the Run scheme (Step 3B) |
| `AccentColor` shows system blue | Asset name must be exactly `AccentColor` — case-sensitive |
| SwiftData migration error | Delete the app from the simulator/device to reset the store during development |
