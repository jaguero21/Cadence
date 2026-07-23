# Cadence GitHub Pages landing site — design

## Context

Cadence has no public web presence yet. CarpeCarb (this developer's other
shipped app) already has one at `jaguero21.github.io/CarpeCarb/`: a
single-file-per-page static site living in `docs/` on `main`, served by
legacy GitHub Pages build (`source.branch: main`, `source.path: /docs`,
confirmed via `gh api repos/jaguero21/CarpeCarb/pages`). This design ports
that same mechanism and visual pattern to Cadence, with content and identity
specific to Cadence rather than a copy-paste.

Cadence's repo (`jaguero21/Cadence`) is currently private
(`gh api repos/jaguero21/Cadence` → `"private": true`); GitHub Pages needs a
public repo on a free plan. Per the user, the repo will be made public
before this launches — that flip is a manual step outside this change, not
something this work performs.

All factual claims below (free vs. Pro feature list, palette hex values,
absence of any backend) were verified against the current codebase, not
assumed:
- Pro gating: `Cadence/Features/Settings/ProPaywallView.swift` (the 3-item
  `features` array) plus `grep -rl isPro` across
  `SymptomPickerView`/`InsightsView`/`ExportView`/`SymptomLibraryView`.
- No backend: `Cadence/Services/StoreService.swift` uses StoreKit 2's own
  `VerificationResult` checking only — no network call, no server receipt
  validation. A repo-wide import scan turned up zero third-party SDKs
  (TipKit/CoreData/ImageIO/Observation are the only non-Apple-obvious ones,
  and all are first-party Apple frameworks).
- Palette: hex values read directly from
  `Cadence/Assets.xcassets/{AccentColor,SleepPurple}.colorset/Contents.json`.
- App icon: `Cadence/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
  (1024×1024, same raw-PNG-served-directly approach CarpeCarb uses).
- Mascot: `Cadence/Assets.xcassets/mascot-welcoming.imageset/mascot-welcoming.png`,
  the same waving capybara pose already used for in-app empty states.

## Non-goals

- No CSS framework, build step, or JS bundler — plain HTML + inlined
  `<style>` per file, matching CarpeCarb exactly (each page is a single
  self-contained file).
- No blog, changelog, or screenshots/App-Store-preview gallery — out of
  scope for this pass.
- No dollar amounts for Pro pricing (not finalized yet — described
  qualitatively as "one-time purchase or monthly subscription").
- No fabricated claims: no free-trial mention (the app doesn't offer one,
  unlike CarpeCarb), no invented account system, no invented third-party
  services.

## File structure

```
docs/
  index.html            Landing page
  privacy-policy.html
  eula.html               Terms of Use
  contact.html
  app_icon.png             Copied from Cadence/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
  mascot.png                Copied from mascot-welcoming.imageset/mascot-welcoming.png
```

Publishing: once the repo is public, GitHub Pages is enabled the same way as
CarpeCarb — Settings → Pages → Source: Deploy from branch, `main` / `/docs`.
(This design covers only the files; enabling Pages in repo settings is a
manual follow-up step for the user, same as making the repo public.)

## Visual identity

Structural pattern is copied from CarpeCarb: centered hero, white rounded
card `<section>`s with an icon+H2 header, `step-grid`/`feature-grid` 2-column
card layouts, warm footer with legal links, `-apple-system` font stack,
720px max-width content column, same responsive breakpoint (520px) collapsing
grids to 1 column. This is the "modeled after" half of the brief.

Identity elements that make it unmistakably Cadence's own, not CarpeCarb's:

| Token | CarpeCarb | Cadence |
|---|---|---|
| Primary accent | `#8FA088` (sage green) | `#2A9D8F` (teal — Cadence's actual `AccentColor`) |
| Secondary accent (Pro section) | — | `#8B7EC8` (Cadence's `SleepPurple`) |
| Background | `#F5F1EB` | `#F5F1EB` (kept — warm neutral cream, both apps share the developer's "warm, personal palette" default) |
| Ink colors | `#2A2520` / `#3D3530` / `#8A7D74` | same warm-charcoal family, unchanged |
| Hero visual | square app icon only | square app icon **+ a real CTA button** ("Join the TestFlight Beta") beneath the tagline — CarpeCarb has no CTA button because App Store search is the CTA; Cadence has no listing yet, so the beta link has to be the explicit action |
| Distinct accent | — | capybara mascot (`mascot-welcoming.png`) appears once, near the closing Support section — a warm illustrative touch pulled straight from the app's real empty-state art, not a generic stock graphic |

Colors are pulled from the same named color sets the SwiftUI app itself
uses, so a visitor who later opens the app sees a consistent palette, not
just a similar layout.

## index.html — sections

1. **Hero** — app icon, "Cadence", tagline ("Spot the patterns in how you
   feel — daily symptom tracking with on-device insights and a doctor-ready
   report"), badge row (`Free to Download`, `iOS 17+`), CTA button "Join the
   TestFlight Beta" linking to a placeholder `#testflight-link-here` (clearly
   commented in the HTML so it's easy to find and swap before publishing).
2. **How It Works** (4-card step-grid, mirrors CarpeCarb's pattern) — log in
   under 90 seconds → HealthKit fills in what it can → on-device pattern
   engine finds correlations → bring a doctor-ready report to your next
   appointment.
3. **Everything Free Gets You** — bulleted list: Daily Log, Weekly Review,
   Custom Trackers, Flares, Medications + reminders, two-way HealthKit sync,
   iCloud sync + JSON backup/restore, Widgets (Home/Lock/StandBy/Control
   Center), Apple Watch quick-log, Siri Shortcuts, CSV export, symptom
   library. (Every item here is confirmed free — not Pro-gated — in the
   current code.)
4. **Cadence Pro** (feature-grid, mirrors CarpeCarb's premium-features
   pattern) — Pattern Insights (correlation detection across sleep, mood,
   stress, symptoms), PDF Export (doctor-ready + personal reports), 90-Day
   Trends, custom free-text symptoms. Highlight box: "One-time purchase or
   monthly subscription — see current pricing in the app." No dollar
   figures, no free-trial claim.
5. **Privacy & Security** — leads with "Cadence has no servers" (verified —
   StoreKit 2 does its own on-device transaction verification, zero
   third-party SDKs anywhere in the codebase); HealthKit is always optional
   and never gates a feature; the pattern engine runs entirely on-device
   (no ML, no cloud); your data lives on your device and your own private
   iCloud. Links to the full Privacy Policy.
6. **Built for the Apple Ecosystem** — Siri App Intents, widgets across
   Home Screen/Lock Screen/StandBy/Control Center, Apple Watch quick-log,
   HealthKit two-way sync, full iPad support.
7. **Support** — contact link (`mailto:carpecarb@icloud.com`, same address
   the user chose to reuse from CarpeCarb), mascot image placed here as the
   closing warm touch.

Footer: © 2026 Cadence · Privacy Policy · Terms of Use · Contact · GitHub
link (to `github.com/jaguero21/Cadence`, valid once public).

## privacy-policy.html

Same section shape as CarpeCarb's page, content rewritten for what Cadence
actually does (materially simpler, since there's no backend at all):

- **Overview** — short-version highlight box: no account, no servers, all
  data stays on-device or in your own private iCloud.
- **Information We Collect** — user-provided only (log entries, symptoms,
  notes, photo/voice attachments, medications, custom trackers, weekly
  reviews). No "collected automatically" section content beyond what
  Apple's own OS provides to every app — explicitly states there's no
  anonymous UID, no analytics, no device identifiers, no crash reporting
  service, because none of that exists in this app (unlike CarpeCarb's
  Firebase anonymous auth).
- **Apple HealthKit** — optional, two-way (mapped symptoms + State of Mind
  mood only, per `HealthKitService`), never gates a feature, revocable
  anytime in Settings.
- **iCloud Sync** — CloudKit-mirrored SwiftData store, private to the
  user's own Apple ID; JSON backup/restore is available to all users (not
  Pro-gated) and merges rather than overwrites.
- **Attachments** — photo/voice-note binaries are stored locally on-device
  only (`AttachmentStore`, Documents directory) and are explicitly *not*
  included in JSON backup/restore or synced off-device by the app.
- **In-App Purchases** — processed entirely by Apple; purchase state is
  verified on-device via StoreKit 2's cryptographically signed transactions;
  Cadence has no server that ever sees a receipt.
- **Third-Party Services** — none. (This section exists mainly to state
  its own emptiness plainly, in contrast to CarpeCarb's Firebase/Perplexity
  section.)
- **Children's Privacy**, **Data Retention & Deletion**, **Changes to This
  Policy**, **Contact Us** — same boilerplate shape as CarpeCarb's, reworded
  for Cadence.

## eula.html (Terms of Use)

Same required section set as CarpeCarb's EULA: Agreement to Terms, License
Grant, Subscriptions & In-App Purchases, Apple App Store Terms, Privacy,
Health Disclaimer, Prohibited Uses, Disclaimer of Warranties, Limitation of
Liability, Updates & Changes, Termination, Governing Law, Contact Us.

The **Health Disclaimer** section is where Cadence's content most diverges
from CarpeCarb's "Health & Nutrition Disclaimer" — it carries the same
"awareness, not diagnosis" framing that's already threaded through the
in-app Insights tab and doctor PDF ("not medical advice" disclaimer next to
every pattern card, per `CLAUDE.md`), stated explicitly: Cadence surfaces
statistical correlations for the user's own awareness and to support
conversations with their doctor; it does not diagnose, treat, or provide
medical advice, and is not a substitute for professional medical judgment.

## contact.html

Same mailto-prefill pattern as CarpeCarb's (a form that builds a
`mailto:` link client-side via a small inline `<script>` — no server, no
webhook, nothing to host). Topic options adapted to Cadence: Bug report,
Feature request, Subscription & billing, Privacy question, Data deletion
request, General feedback. Same `carpecarb@icloud.com` destination address
and 5-business-day response-time framing.

## Open items (not blockers for writing the pages, but need the user's input before publishing)

- **TestFlight link** — placeholder `#testflight-link-here` throughout;
  swap in the real link before publishing.
- **Repo visibility** — user will make `jaguero21/Cadence` public before
  launch; this change doesn't touch repo settings.
- **Enabling GitHub Pages** — a manual repo-settings step after the repo is
  public; not part of this change.
