# Cadence GitHub Pages Landing Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Cadence's GitHub Pages landing site (`docs/index.html` + 3 sub-pages) modeled on CarpeCarb's live site structure, with Cadence's own content, palette, and mascot accent.

**Architecture:** Four independent, self-contained static HTML files (inline `<style>`, no build step, no JS framework — one page has a small vanilla-JS mailto helper), plus two copied image assets. Served by GitHub Pages from `main` / `/docs` once the repo is public (a manual step outside this plan).

**Tech Stack:** Plain HTML5 + inline CSS. No dependencies, no package manager, no bundler.

## Global Constraints

- Every page is a single self-contained `.html` file — inline `<style>`, no external CSS/JS files, no build step (matches CarpeCarb's `docs/*.html` exactly).
- No dollar figures anywhere for Cadence Pro pricing — pricing isn't finalized. Describe it as "one-time purchase or monthly subscription."
- No free-trial claim — the app doesn't offer one (unlike CarpeCarb).
- The TestFlight CTA on `index.html` links to the literal placeholder `#testflight-link-here`, immediately preceded by an HTML comment flagging it for replacement. This is the only placeholder link in the site.
- Support/contact email is `carpecarb@icloud.com` throughout (the user's explicit choice — same inbox as CarpeCarb).
- Legal dates: Effective date / Last updated = `July 23, 2026`. Footer copyright = `© 2026 Cadence.`
- GitHub footer link target: `https://github.com/jaguero21/Cadence`.
- Palette: background `#F5F1EB`, ink `#2A2520`/`#3D3530`/`#8A7D74` (unchanged from CarpeCarb), primary accent `#2A9D8F` (teal, from Cadence's real `AccentColor`) with hover `#258A7E`, secondary accent `#8B7EC8` (from Cadence's real `SleepPurple`, used only in the Pro section).
- Making the `jaguero21/Cadence` repo public and enabling GitHub Pages in repo settings are manual follow-up steps for the user — **out of scope for this plan.**

---

### Task 1: Copy image assets into `docs/`

**Files:**
- Create: `docs/app_icon.png` (copy of `Cadence/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`)
- Create: `docs/mascot.png` (copy of `Cadence/Assets.xcassets/mascot-welcoming.imageset/mascot-welcoming.png`)

**Interfaces:**
- Consumes: nothing.
- Produces: `./app_icon.png` (1024×1024, no alpha channel) and `./mascot.png` (transparent background) — every later HTML task references these two paths.

- [ ] **Step 1: Copy the two source images**

```bash
mkdir -p docs
cp "Cadence/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" docs/app_icon.png
cp "Cadence/Assets.xcassets/mascot-welcoming.imageset/mascot-welcoming.png" docs/mascot.png
```

- [ ] **Step 2: Verify dimensions and alpha channel**

Run: `sips -g pixelWidth -g pixelHeight -g hasAlpha docs/app_icon.png docs/mascot.png`

Expected output:
```
/.../docs/app_icon.png
  pixelWidth: 1024
  pixelHeight: 1024
  hasAlpha: no
/.../docs/mascot.png
  pixelWidth: 1024
  pixelHeight: 1024
  hasAlpha: yes
```

(`app_icon.png` has no alpha — correct, App Store icons are opaque. `mascot.png` has alpha — correct, it needs to sit transparently on the cream page background.)

- [ ] **Step 3: Commit**

```bash
git add docs/app_icon.png docs/mascot.png
git commit -m "Add Cadence app icon and mascot assets for the GitHub Pages site"
```

---

### Task 2: Build `docs/index.html`

**Files:**
- Create: `docs/index.html`

**Interfaces:**
- Consumes: `./app_icon.png`, `./mascot.png` (Task 1).
- Produces: `docs/index.html`, linked as `./index.html` by every sub-page's footer nav.

- [ ] **Step 1: Write the file**

Create `docs/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Cadence — Daily Symptom Tracking for iOS</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #F5F1EB;
      color: #2A2520;
      line-height: 1.7;
    }

    /* ── Hero ── */
    .hero {
      max-width: 720px;
      margin: 0 auto;
      padding: 64px 24px 48px;
      text-align: center;
    }

    .hero-logo {
      width: 96px;
      height: 96px;
      border-radius: 22px;
      margin: 0 auto 24px;
      display: block;
      box-shadow: 0 8px 24px rgba(42,37,32,0.15);
    }

    .hero h1 {
      font-size: 42px;
      font-weight: 800;
      color: #2A2520;
      letter-spacing: -0.5px;
      margin-bottom: 12px;
    }

    .hero p {
      font-size: 18px;
      color: #8A7D74;
      max-width: 480px;
      margin: 0 auto 28px;
    }

    .cta-btn {
      display: inline-block;
      background: #2A9D8F;
      color: #ffffff;
      font-size: 16px;
      font-weight: 600;
      padding: 14px 32px;
      border-radius: 12px;
      text-decoration: none;
      transition: background 0.15s;
    }

    .cta-btn:hover { background: #258A7E; text-decoration: none; }

    .badge {
      display: inline-block;
      background: #2A9D8F;
      color: #fff;
      font-size: 13px;
      font-weight: 600;
      padding: 6px 16px;
      border-radius: 999px;
      margin: 20px 4px 4px;
    }

    .badge-outline {
      display: inline-block;
      background: transparent;
      color: #2A9D8F;
      border: 1.5px solid #2A9D8F;
      font-size: 13px;
      font-weight: 600;
      padding: 5px 14px;
      border-radius: 999px;
      margin: 20px 4px 4px;
    }

    /* ── Sections ── */
    main {
      max-width: 720px;
      margin: 0 auto;
      padding: 0 16px 64px;
    }

    section {
      background: #ffffff;
      border-radius: 16px;
      padding: 28px 32px;
      margin-bottom: 16px;
      box-shadow: 0 2px 8px rgba(42,37,32,0.06);
    }

    h2 {
      font-size: 20px;
      font-weight: 700;
      color: #2A2520;
      margin-bottom: 16px;
      display: flex;
      align-items: center;
      gap: 10px;
    }

    h2 .icon {
      width: 32px;
      height: 32px;
      background: rgba(42,157,143,0.15);
      border-radius: 8px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 17px;
      flex-shrink: 0;
    }

    h2 .icon.accent-purple { background: rgba(139,126,200,0.18); }

    p { color: #3D3530; font-size: 15px; margin-bottom: 12px; }
    p:last-child { margin-bottom: 0; }

    ul {
      padding-left: 20px;
      margin-bottom: 12px;
    }

    ul:last-child { margin-bottom: 0; }

    li {
      color: #3D3530;
      font-size: 15px;
      margin-bottom: 8px;
    }

    li strong { color: #2A2520; }

    .step-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
      margin-top: 4px;
    }

    .step-card {
      background: #FDFAF6;
      border: 1.5px solid rgba(42,37,32,0.08);
      border-radius: 12px;
      padding: 16px;
    }

    .step-num {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 1px;
      color: #2A9D8F;
      text-transform: uppercase;
      margin-bottom: 4px;
    }

    .step-title {
      font-size: 14px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 4px;
    }

    .step-desc {
      font-size: 13px;
      color: #8A7D74;
      line-height: 1.5;
    }

    .highlight {
      background: rgba(42,157,143,0.1);
      border-left: 3px solid #2A9D8F;
      border-radius: 0 8px 8px 0;
      padding: 12px 16px;
      margin-top: 12px;
      font-size: 14px;
      color: #3D3530;
    }

    .highlight.accent-purple {
      background: rgba(139,126,200,0.12);
      border-left-color: #8B7EC8;
    }

    a { color: #2A9D8F; text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* ── Pro features ── */
    .feature-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    .feature-card {
      background: #FDFAF6;
      border: 1.5px solid rgba(42,37,32,0.08);
      border-radius: 10px;
      padding: 14px;
      display: flex;
      align-items: flex-start;
      gap: 10px;
    }

    .feature-icon { font-size: 20px; flex-shrink: 0; margin-top: 1px; }

    .feature-title {
      font-size: 13px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 2px;
    }

    .feature-desc {
      font-size: 12px;
      color: #8A7D74;
      line-height: 1.45;
    }

    /* ── Support / mascot ── */
    .support-row {
      display: flex;
      align-items: center;
      gap: 20px;
    }

    .mascot {
      width: 88px;
      height: auto;
      flex-shrink: 0;
    }

    /* ── Footer ── */
    footer {
      max-width: 720px;
      margin: 0 auto;
      padding: 24px 16px 48px;
      text-align: center;
      font-size: 13px;
      color: #8A7D74;
      border-top: 1px solid rgba(42,37,32,0.1);
    }

    footer a { color: #2A9D8F; }

    footer .links {
      margin-top: 10px;
      display: flex;
      justify-content: center;
      gap: 8px;
      flex-wrap: wrap;
    }

    footer .links a {
      font-weight: 500;
    }

    footer .sep { color: rgba(42,37,32,0.2); }

    @media (max-width: 520px) {
      .hero h1 { font-size: 30px; }
      .step-grid { grid-template-columns: 1fr; }
      .feature-grid { grid-template-columns: 1fr; }
      .support-row { flex-direction: column; text-align: center; }
      section { padding: 20px 18px; }
    }
  </style>
</head>
<body>

<!-- Hero -->
<div class="hero">
  <img src="./app_icon.png" alt="Cadence app icon" class="hero-logo" />
  <h1>Cadence</h1>
  <p>On-device symptom tracking that finds the patterns — and turns them into a doctor-ready report.</p>
  <!-- TODO: replace with the real public TestFlight link before publishing -->
  <a href="#testflight-link-here" class="cta-btn">Join the TestFlight Beta</a>
  <div>
    <span class="badge">Free to Download</span>
    <span class="badge-outline">iOS 17+</span>
  </div>
</div>

<main>

  <!-- How it works -->
  <section>
    <h2><span class="icon">⚡</span> How It Works</h2>
    <div class="step-grid">
      <div class="step-card">
        <div class="step-num">Step 1</div>
        <div class="step-title">Log in under 90 seconds</div>
        <div class="step-desc">Mood, energy, sleep, symptoms, and whatever else stood out today — quick sliders and taps, not a form.</div>
      </div>
      <div class="step-card">
        <div class="step-num">Step 2</div>
        <div class="step-title">HealthKit fills in what it can</div>
        <div class="step-desc">Sleep, wrist temperature, workouts, and more prefill automatically — always optional, never overwriting what you typed.</div>
      </div>
      <div class="step-card">
        <div class="step-num">Step 3</div>
        <div class="step-title">Patterns surface on their own</div>
        <div class="step-desc">An on-device engine compares your days and flags real correlations — confidence-scored and explainable.</div>
      </div>
      <div class="step-card">
        <div class="step-num">Step 4</div>
        <div class="step-title">Bring it to your next appointment</div>
        <div class="step-desc">Export a doctor-ready PDF or a spreadsheet, scoped to any date range.</div>
      </div>
    </div>
  </section>

  <!-- Free features -->
  <section>
    <h2><span class="icon">🆓</span> Everything Free Gets You</h2>
    <p>Cadence's core tracking is free — no trial, no time limit.</p>
    <ul>
      <li><strong>Daily Log</strong> — mood, energy, sleep, pain, symptoms, and contextual factors in under 90 seconds</li>
      <li><strong>Weekly Review</strong> — guided reflection prompts and Intentions for Tomorrow</li>
      <li><strong>Custom Trackers</strong> — track any metric that matters to you, beyond the built-in set</li>
      <li><strong>Flares</strong> — multi-day symptom episode tracking with early-warning precursor detection</li>
      <li><strong>Medications</strong> — course tracking, symptom-effect correlation, and reminder notifications</li>
      <li><strong>HealthKit Sync</strong> — two-way sync for symptoms and mood, always optional</li>
      <li><strong>iCloud Sync &amp; Backup</strong> — CloudKit sync plus a JSON backup/restore that merges, never overwrites</li>
      <li><strong>Widgets</strong> — Home Screen, Lock Screen, StandBy, and a Control Center check-in button</li>
      <li><strong>Apple Watch</strong> — wrist quick-log for mood and energy</li>
      <li><strong>Siri Shortcuts</strong> — log a check-in hands-free</li>
      <li><strong>CSV Export</strong> — take your data anywhere</li>
      <li><strong>Symptom Library</strong> — toggle from ~34 built-in symptoms to match what you're tracking</li>
    </ul>
  </section>

  <!-- Pro -->
  <section>
    <h2><span class="icon accent-purple">⭐</span> Cadence Pro</h2>
    <p>Free covers day-to-day tracking. Pro unlocks the deeper analysis once you've got enough history to make it meaningful.</p>
    <div class="feature-grid" style="margin-top: 16px;">
      <div class="feature-card">
        <div class="feature-icon">🧠</div>
        <div>
          <div class="feature-title">Pattern Insights</div>
          <div class="feature-desc">Correlation detection across sleep, mood, stress, and symptoms — confidence-scored, always explainable.</div>
        </div>
      </div>
      <div class="feature-card">
        <div class="feature-icon">📄</div>
        <div>
          <div class="feature-title">PDF Export</div>
          <div class="feature-desc">Doctor-ready and personal reports, previewed before you share them.</div>
        </div>
      </div>
      <div class="feature-card">
        <div class="feature-icon">📈</div>
        <div>
          <div class="feature-title">90-Day Trends</div>
          <div class="feature-desc">Full trend history across every metric you track, not just 30 days.</div>
        </div>
      </div>
      <div class="feature-card">
        <div class="feature-icon">✍️</div>
        <div>
          <div class="feature-title">Custom Symptoms</div>
          <div class="feature-desc">Add your own free-text symptoms beyond the built-in library.</div>
        </div>
      </div>
    </div>
    <div class="highlight accent-purple">
      <strong>One-time purchase or monthly subscription</strong> — current pricing is shown in the app before you buy. Manage or cancel anytime via <strong>Settings → Apple ID → Subscriptions</strong>.
    </div>
  </section>

  <!-- Privacy -->
  <section>
    <h2><span class="icon">🔒</span> Privacy &amp; Security</h2>
    <ul>
      <li><strong>No servers, period</strong> — Cadence has no backend of any kind. Purchases are verified on-device by Apple's StoreKit; there's no server to send a receipt to.</li>
      <li><strong>HealthKit stays optional</strong> — reads and writes are always supplementary. No feature is ever gated on Health access, and nothing you type is overwritten by HealthKit data.</li>
      <li><strong>On-device pattern engine</strong> — insights are deterministic correlation detection that runs entirely on your phone. No ML, no cloud processing, no black box.</li>
      <li><strong>Your data, your iCloud</strong> — sync goes through your own private iCloud account. We never see it.</li>
    </ul>
    <p style="margin-top:12px;">Read our full <a href="./privacy-policy.html">Privacy Policy</a> for details.</p>
  </section>

  <!-- Apple ecosystem -->
  <section>
    <h2><span class="icon">🍎</span> Built for the Apple Ecosystem</h2>
    <ul>
      <li><strong>Siri &amp; Shortcuts</strong> — "Hey Siri, log my check-in" from anywhere</li>
      <li><strong>Widgets</strong> — glanceable streak and today's status on your Home Screen, Lock Screen, and StandBy</li>
      <li><strong>Apple Watch</strong> — a wrist quick-log for mood and energy</li>
      <li><strong>HealthKit</strong> — two-way sync for symptoms and mood</li>
      <li><strong>iPad</strong> — full support for all four orientations, including Stage Manager</li>
    </ul>
  </section>

  <!-- Support -->
  <section>
    <h2><span class="icon">✉️</span> Support</h2>
    <div class="support-row">
      <img src="./mascot.png" alt="Cadence's mascot, a waving capybara" class="mascot" />
      <div>
        <p>Have a question, found a bug, or want to request a feature? We'd love to hear from you.</p>
        <p><a href="./contact.html">Contact us</a> — we aim to respond within 5 business days.</p>
      </div>
    </div>
  </section>

</main>

<footer>
  <p>© 2026 Cadence. All rights reserved.</p>
  <div class="links">
    <a href="./privacy-policy.html">Privacy Policy</a>
    <span class="sep">·</span>
    <a href="./eula.html">Terms of Use</a>
    <span class="sep">·</span>
    <a href="./contact.html">Contact</a>
    <span class="sep">·</span>
    <a href="https://github.com/jaguero21/Cadence">GitHub</a>
  </div>
</footer>

</body>
</html>
```

- [ ] **Step 2: Check tag balance**

Run:
```bash
python3 -c "
import sys
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            print(f'MISMATCH: expected close for {self.stack[-1] if self.stack else None!r}, got </{tag}>')
            sys.exit(1)
        self.stack.pop()

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    html = f.read()
c = Checker()
c.feed(html)
if c.stack:
    print(f'UNCLOSED TAGS: {c.stack}')
    sys.exit(1)
print('OK: tags balanced')
" docs/index.html
```

Expected output: `OK: tags balanced`

- [ ] **Step 3: Check relative links/assets resolve (some are expected missing until later tasks)**

Run:
```bash
grep -oE '(href|src)="\./[^"]*"' docs/index.html | sed -E 's/^(href|src)="\.\///; s/"$//' | sort -u | while read -r f; do
  if [[ -f "docs/$f" ]]; then echo "OK      $f"; else echo "MISSING $f"; fi
done
```

Expected output:
```
MISSING contact.html
MISSING eula.html
OK      app_icon.png
OK      mascot.png
MISSING privacy-policy.html
```
(`contact.html`, `eula.html`, `privacy-policy.html` don't exist yet — that's expected here and gets resolved by Tasks 3–5. `app_icon.png`/`mascot.png` must show `OK`.)

- [ ] **Step 4: Commit**

```bash
git add docs/index.html
git commit -m "Add Cadence landing page"
```

---

### Task 3: Build `docs/privacy-policy.html`

**Files:**
- Create: `docs/privacy-policy.html`

**Interfaces:**
- Consumes: `./app_icon.png` (Task 1), `./index.html` (Task 2).
- Produces: `docs/privacy-policy.html`, linked as `./privacy-policy.html` from `index.html`, `eula.html`, and `contact.html`.

- [ ] **Step 1: Write the file**

Create `docs/privacy-policy.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Privacy Policy — Cadence</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #F5F1EB;
      color: #2A2520;
      line-height: 1.7;
      padding: 0 16px 64px;
    }

    header {
      max-width: 720px;
      margin: 0 auto;
      padding: 48px 0 32px;
      border-bottom: 1px solid rgba(42,37,32,0.12);
    }

    .logo {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }

    .logo-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      overflow: hidden;
      flex-shrink: 0;
    }

    .logo-icon img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .logo-name {
      font-size: 22px;
      font-weight: 600;
      color: #2A2520;
      letter-spacing: 0.2px;
    }

    h1 {
      font-size: 32px;
      font-weight: 700;
      color: #2A2520;
      margin-bottom: 8px;
    }

    .meta {
      font-size: 14px;
      color: #8A7D74;
    }

    main {
      max-width: 720px;
      margin: 40px auto 0;
    }

    section {
      background: #ffffff;
      border-radius: 16px;
      padding: 28px 32px;
      margin-bottom: 16px;
      box-shadow: 0 2px 8px rgba(42,37,32,0.06);
    }

    h2 {
      font-size: 18px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    h2 .icon {
      width: 28px;
      height: 28px;
      background: rgba(42,157,143,0.15);
      border-radius: 7px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 15px;
      flex-shrink: 0;
    }

    p { margin-bottom: 12px; color: #3D3530; font-size: 15px; }
    p:last-child { margin-bottom: 0; }

    ul {
      padding-left: 20px;
      margin-bottom: 12px;
    }

    ul:last-child { margin-bottom: 0; }

    li {
      color: #3D3530;
      font-size: 15px;
      margin-bottom: 6px;
    }

    a { color: #2A9D8F; text-decoration: none; }
    a:hover { text-decoration: underline; }

    .highlight {
      background: rgba(42,157,143,0.1);
      border-left: 3px solid #2A9D8F;
      border-radius: 0 8px 8px 0;
      padding: 12px 16px;
      margin-bottom: 12px;
      font-size: 15px;
      color: #3D3530;
    }

    .highlight:last-child { margin-bottom: 0; }

    footer {
      max-width: 720px;
      margin: 32px auto 0;
      text-align: center;
      font-size: 13px;
      color: #8A7D74;
    }
  </style>
</head>
<body>

<header>
  <div class="logo">
    <div class="logo-icon"><img src="./app_icon.png" alt="Cadence" /></div>
    <span class="logo-name">Cadence</span>
  </div>
  <h1>Privacy Policy</h1>
  <p class="meta">Effective date: July 23, 2026 &nbsp;·&nbsp; Last updated: July 23, 2026</p>
</header>

<main>

  <section>
    <h2><span class="icon">👋</span> Overview</h2>
    <p>Cadence ("we", "our", or "the app") is a personal symptom, mood, and energy tracking tool for iOS. We are committed to protecting your privacy. This policy explains what information the app handles and the choices available to you.</p>
    <div class="highlight">
      <strong>Short version:</strong> Cadence has no backend servers. There's no account, no analytics, and no third-party SDKs anywhere in the app. Your log entries are stored on your device and, if you enable iCloud sync, in your own private iCloud account — we never see them.
    </div>
  </section>

  <section>
    <h2><span class="icon">📋</span> Information We Collect</h2>

    <p><strong>Information you provide</strong></p>
    <ul>
      <li>Daily log entries — mood, energy, sleep, pain, symptoms, contextual factors, and free-form notes</li>
      <li>Photos and voice notes you choose to attach to a log entry</li>
      <li>Weekly review reflections and Intentions for Tomorrow</li>
      <li>Medications, custom trackers, and flare episodes you add</li>
    </ul>

    <p><strong>Information we do NOT collect</strong></p>
    <ul>
      <li>Name, email address, or any account credentials — Cadence has no account system</li>
      <li>Analytics or usage tracking of any kind</li>
      <li>Device identifiers (IDFA, IDFV)</li>
      <li>Precise or approximate location</li>
      <li>Crash reports or analytics beyond what Apple provides to all developers</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">🍎</span> Apple HealthKit</h2>
    <p>With your explicit permission, Cadence can read from and write to Apple HealthKit — prefilling objective data like sleep, wrist temperature, and workouts, and mirroring the symptoms and mood you log.</p>
    <ul>
      <li>HealthKit access is always optional — no feature in Cadence is ever gated behind it</li>
      <li>Data you enter yourself is never overwritten by a HealthKit-sourced value</li>
      <li>HealthKit data is stored on your device and in your personal iCloud Health account — Cadence's own servers never see it, because Cadence has no servers</li>
      <li>We do not share HealthKit data with third parties, advertisers, or analytics services</li>
      <li>You can revoke HealthKit permission at any time in <strong>Settings → Privacy &amp; Security → Health → Cadence</strong></li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">☁️</span> iCloud Sync</h2>
    <p>If iCloud is available, your logs, weekly reviews, medications, trackers, and flares are mirrored to your personal iCloud account via Apple's CloudKit. This data is:</p>
    <ul>
      <li>Accessible only to you, through your own Apple ID</li>
      <li>Used solely to sync your data across your own devices</li>
      <li>Never read, analyzed, or transmitted to us for any other purpose — there is no "us" to send it to, since Cadence has no backend</li>
    </ul>
    <p>You can also back up your data to a JSON file from <strong>Settings → Backup</strong>, independent of iCloud. Restoring a backup merges it with what's already on the device — it never overwrites existing entries.</p>
  </section>

  <section>
    <h2><span class="icon">📎</span> Attachments</h2>
    <p>Photos and voice notes you attach to a log entry are stored locally on your device, outside the main data store. They are not included in the JSON backup/restore feature and are not part of Cadence's iCloud sync — they stay on the device you recorded them on.</p>
  </section>

  <section>
    <h2><span class="icon">💳</span> In-App Purchases</h2>
    <p>Cadence Pro — a one-time purchase or a monthly subscription — is processed entirely by Apple through the App Store. Cadence checks your purchase using StoreKit 2's own on-device, cryptographically signed transaction records. We do not receive, see, or store your payment information, and there is no server-side receipt check, because Cadence has no server.</p>
  </section>

  <section>
    <h2><span class="icon">🔗</span> Third-Party Services</h2>
    <p>None. Cadence is built entirely on Apple's own frameworks — HealthKit, CloudKit, StoreKit, WidgetKit, WatchConnectivity, and App Intents — and does not integrate any third-party analytics, advertising, or backend service. Apple's handling of the data described above is governed by <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener">Apple's own Privacy Policy</a>.</p>
  </section>

  <section>
    <h2><span class="icon">👶</span> Children's Privacy</h2>
    <p>Cadence is not directed at children under the age of 13. We do not knowingly design the app to collect personal information from children. Because all data is stored locally on-device (and, optionally, in the user's own private iCloud account), a parent or guardian can remove any child's data at any time simply by deleting the app.</p>
  </section>

  <section>
    <h2><span class="icon">🌍</span> Data Retention &amp; Deletion</h2>
    <p>All log data is stored locally on your device and is deleted when you delete the app. If you use iCloud Sync, your data also lives in your own private iCloud account, and deleting the app on all your devices removes it from there too.</p>
    <p>Because Cadence has no backend, there is no copy of your data anywhere for us to delete on your behalf — deleting the app is deleting your data.</p>
  </section>

  <section>
    <h2><span class="icon">🔄</span> Changes to This Policy</h2>
    <p>We may update this Privacy Policy from time to time. When we do, we will update the "Last updated" date at the top of this page. Continued use of the app after changes constitutes your acceptance of the revised policy.</p>
  </section>

  <section>
    <h2><span class="icon">✉️</span> Contact Us</h2>
    <p>If you have questions or concerns about this Privacy Policy or your data, please contact us:</p>
    <p><strong>Cadence Support</strong><br>
    <a href="mailto:carpecarb@icloud.com">carpecarb@icloud.com</a></p>
  </section>

</main>

<footer>
  <p>© 2026 Cadence. All rights reserved.</p>
  <p style="margin-top:6px;">
    <a href="./index.html">Home</a>
    &nbsp;·&nbsp;
    <a href="./eula.html">Terms of Use</a>
    &nbsp;·&nbsp;
    <a href="./contact.html">Contact</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/jaguero21/Cadence">GitHub</a>
  </p>
</footer>

</body>
</html>
```

- [ ] **Step 2: Check tag balance**

Run (same checker script as Task 2, Step 2, pointed at the new file):
```bash
python3 -c "
import sys
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            print(f'MISMATCH: expected close for {self.stack[-1] if self.stack else None!r}, got </{tag}>')
            sys.exit(1)
        self.stack.pop()

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    html = f.read()
c = Checker()
c.feed(html)
if c.stack:
    print(f'UNCLOSED TAGS: {c.stack}')
    sys.exit(1)
print('OK: tags balanced')
" docs/privacy-policy.html
```

Expected output: `OK: tags balanced`

- [ ] **Step 3: Check relative links/assets resolve**

Run:
```bash
grep -oE '(href|src)="\./[^"]*"' docs/privacy-policy.html | sed -E 's/^(href|src)="\.\///; s/"$//' | sort -u | while read -r f; do
  if [[ -f "docs/$f" ]]; then echo "OK      $f"; else echo "MISSING $f"; fi
done
```

Expected output:
```
MISSING contact.html
MISSING eula.html
OK      app_icon.png
OK      index.html
```
(`contact.html`/`eula.html` don't exist yet — resolved by Tasks 4–5.)

- [ ] **Step 4: Commit**

```bash
git add docs/privacy-policy.html
git commit -m "Add Cadence privacy policy page"
```

---

### Task 4: Build `docs/eula.html`

**Files:**
- Create: `docs/eula.html`

**Interfaces:**
- Consumes: `./app_icon.png` (Task 1), `./index.html` (Task 2), `./privacy-policy.html` (Task 3).
- Produces: `docs/eula.html`, linked as `./eula.html` from `index.html` and `privacy-policy.html`.

- [ ] **Step 1: Write the file**

Create `docs/eula.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>End User License Agreement — Cadence</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #F5F1EB;
      color: #2A2520;
      line-height: 1.7;
      padding: 0 16px 64px;
    }

    header {
      max-width: 720px;
      margin: 0 auto;
      padding: 48px 0 32px;
      border-bottom: 1px solid rgba(42,37,32,0.12);
    }

    .logo {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }

    .logo-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      overflow: hidden;
      flex-shrink: 0;
    }

    .logo-icon img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .logo-name {
      font-size: 22px;
      font-weight: 600;
      color: #2A2520;
      letter-spacing: 0.2px;
    }

    h1 {
      font-size: 32px;
      font-weight: 700;
      color: #2A2520;
      margin-bottom: 8px;
    }

    .meta {
      font-size: 14px;
      color: #8A7D74;
    }

    main {
      max-width: 720px;
      margin: 40px auto 0;
    }

    section {
      background: #ffffff;
      border-radius: 16px;
      padding: 28px 32px;
      margin-bottom: 16px;
      box-shadow: 0 2px 8px rgba(42,37,32,0.06);
    }

    h2 {
      font-size: 18px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    h2 .icon {
      width: 28px;
      height: 28px;
      background: rgba(42,157,143,0.15);
      border-radius: 7px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 15px;
      flex-shrink: 0;
    }

    p { margin-bottom: 12px; color: #3D3530; font-size: 15px; }
    p:last-child { margin-bottom: 0; }

    ul {
      padding-left: 20px;
      margin-bottom: 12px;
    }

    ul:last-child { margin-bottom: 0; }

    li {
      color: #3D3530;
      font-size: 15px;
      margin-bottom: 6px;
    }

    a { color: #2A9D8F; text-decoration: none; }
    a:hover { text-decoration: underline; }

    .highlight {
      background: rgba(42,157,143,0.1);
      border-left: 3px solid #2A9D8F;
      border-radius: 0 8px 8px 0;
      padding: 12px 16px;
      margin-bottom: 12px;
      font-size: 15px;
      color: #3D3530;
    }

    .highlight:last-child { margin-bottom: 0; }

    footer {
      max-width: 720px;
      margin: 32px auto 0;
      text-align: center;
      font-size: 13px;
      color: #8A7D74;
    }
  </style>
</head>
<body>

<header>
  <div class="logo">
    <div class="logo-icon"><img src="./app_icon.png" alt="Cadence" /></div>
    <span class="logo-name">Cadence</span>
  </div>
  <h1>End User License Agreement</h1>
  <p class="meta">Effective date: July 23, 2026 &nbsp;·&nbsp; Last updated: July 23, 2026</p>
</header>

<main>

  <section>
    <h2><span class="icon">👋</span> Agreement to Terms</h2>
    <p>This End User License Agreement ("EULA") is a legal agreement between you ("User" or "you") and Cadence ("we", "us", or "our") governing your use of the Cadence iOS application and any associated services (collectively, the "App").</p>
    <div class="highlight">
      <strong>By downloading, installing, or using Cadence, you agree to be bound by this EULA.</strong> If you do not agree to these terms, do not download or use the App. Your continued use of the App following any updates to this EULA constitutes acceptance of the revised terms.
    </div>
  </section>

  <section>
    <h2><span class="icon">📄</span> License Grant</h2>
    <p>Subject to your compliance with this EULA, we grant you a limited, non-exclusive, non-transferable, revocable license to download and use the App on any Apple-branded device that you own or control, solely for your personal, non-commercial purposes.</p>
    <p>This license does not include the right to:</p>
    <ul>
      <li>Sublicense, sell, resell, transfer, or otherwise make the App available to any third party</li>
      <li>Modify, translate, adapt, or create derivative works based on the App</li>
      <li>Reverse engineer, disassemble, decompile, or otherwise attempt to derive the source code of the App</li>
      <li>Remove, alter, or obscure any proprietary notices in the App</li>
      <li>Use the App for any commercial purpose or for any public display</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">💳</span> Subscriptions &amp; In-App Purchases</h2>
    <p>Cadence offers an optional upgrade ("Cadence Pro") — available as a one-time lifetime purchase or a monthly subscription — that unlocks Pattern Insights, PDF export, 90-day trend history, and custom free-text symptoms beyond the free tier. The following terms apply:</p>
    <ul>
      <li><strong>Lifetime Purchase:</strong> A one-time payment charged to your Apple ID at confirmation of purchase. It does not expire and does not renew.</li>
      <li><strong>Monthly Subscription:</strong> Billed through your Apple ID via the App Store; automatically renews unless auto-renewal is turned off at least 24 hours before the end of the current billing period.</li>
      <li><strong>Renewal Pricing:</strong> Your account is charged for renewal within 24 hours prior to the end of the current period at the same price as the original subscription unless pricing has changed.</li>
      <li><strong>Managing Subscriptions:</strong> You can manage or cancel your subscription at any time through your Apple ID account settings. Cancellation takes effect at the end of the current billing period — you retain Pro access until then.</li>
      <li><strong>No Refunds:</strong> All purchases are final. We do not offer refunds except as required by applicable law. For refund requests, contact Apple Support directly.</li>
      <li><strong>Price Changes:</strong> We reserve the right to change pricing. We will provide reasonable notice of any changes.</li>
    </ul>
    <p>Current pricing for both options is displayed within the App at the time of purchase.</p>
  </section>

  <section>
    <h2><span class="icon">🍎</span> Apple App Store Terms</h2>
    <p>The App is distributed through the Apple App Store. Your use of the App is also subject to the <a href="https://www.apple.com/legal/internet-services/itunes/terms/en.html" target="_blank" rel="noopener">Apple Media Services Terms and Conditions</a>. In the event of any conflict between this EULA and the Apple Media Services Terms and Conditions, the Apple Media Services Terms and Conditions shall govern with respect to the App Store distribution.</p>
    <p>You acknowledge that:</p>
    <ul>
      <li>This EULA is concluded between you and Cadence only, and not with Apple Inc.</li>
      <li>Apple is not responsible for the App or its content.</li>
      <li>Apple has no obligation whatsoever to furnish any maintenance or support services with respect to the App.</li>
      <li>Apple is not responsible for addressing any claims by you or any third party relating to the App.</li>
      <li>Apple and Apple's subsidiaries are third-party beneficiaries of this EULA and have the right to enforce it against you.</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">🔒</span> Privacy</h2>
    <p>Your use of the App is also governed by our <a href="./privacy-policy.html">Privacy Policy</a>, which is incorporated into this EULA by reference. By using the App, you consent to the collection and use of your information as described in our Privacy Policy.</p>
  </section>

  <section>
    <h2><span class="icon">🏥</span> Health Disclaimer</h2>
    <p>Cadence is designed as a general wellness and self-tracking tool. It is <strong>not</strong> a medical device and is not intended to diagnose, treat, cure, or prevent any disease or health condition.</p>
    <ul>
      <li>Pattern Insights are statistical correlations computed from your own logged data, offered for your own awareness and to support conversations with your doctor — they are not a diagnosis and do not constitute medical advice.</li>
      <li>Always consult a qualified healthcare professional before making decisions about your health, medications, or treatment.</li>
      <li>Do not rely solely on Cadence for medical decisions, and do not use it as a substitute for professional medical judgment.</li>
      <li>HealthKit-derived data (sleep, workouts, and similar metrics) reflects what Apple Health reports and is not independently verified by Cadence for medical accuracy.</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">🚫</span> Prohibited Uses</h2>
    <p>You agree not to use the App to:</p>
    <ul>
      <li>Violate any applicable law or regulation</li>
      <li>Attempt to gain unauthorized access to any portion of the App or its related systems</li>
      <li>Transmit any viruses, malware, or other malicious code</li>
      <li>Interfere with or disrupt the integrity or performance of the App</li>
      <li>Circumvent, disable, or otherwise interfere with security-related features of the App</li>
      <li>Use automated means (bots, scrapers, etc.) to access the App</li>
      <li>Attempt to reverse engineer or extract any proprietary implementation details of the App</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">⚠️</span> Disclaimer of Warranties</h2>
    <p>THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NON-INFRINGEMENT.</p>
    <p>We do not warrant that:</p>
    <ul>
      <li>The App will meet your specific requirements</li>
      <li>The App will be uninterrupted, timely, secure, or error-free</li>
      <li>Pattern Insights or any other computation performed by the App will be accurate, complete, or medically reliable</li>
      <li>Any errors in the App will be corrected</li>
    </ul>
  </section>

  <section>
    <h2><span class="icon">🛡️</span> Limitation of Liability</h2>
    <p>TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL CADENCE, ITS OFFICERS, DIRECTORS, EMPLOYEES, OR AGENTS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF OR RELATED TO YOUR USE OF THE APP, INCLUDING BUT NOT LIMITED TO:</p>
    <ul>
      <li>Loss of data or personal information</li>
      <li>Health outcomes based on insights, reports, or data provided by the App</li>
      <li>Interruption or cessation of service</li>
      <li>Bugs, viruses, or other harmful components</li>
    </ul>
    <p>OUR TOTAL LIABILITY TO YOU FOR ALL CLAIMS ARISING FROM YOUR USE OF THE APP SHALL NOT EXCEED THE AMOUNT YOU PAID FOR THE APP OR CADENCE PRO IN THE TWELVE (12) MONTHS PRECEDING THE CLAIM.</p>
  </section>

  <section>
    <h2><span class="icon">🔄</span> Updates &amp; Changes</h2>
    <p>We may update the App from time to time to add features, fix bugs, or address security issues. Updates may be delivered automatically through the App Store. Continued use of the App after an update constitutes acceptance of any changes.</p>
    <p>We reserve the right to modify, suspend, or discontinue the App (or any part of it) at any time, with or without notice. We will not be liable to you or any third party for any modification, suspension, or discontinuance of the App.</p>
  </section>

  <section>
    <h2><span class="icon">❌</span> Termination</h2>
    <p>This EULA is effective until terminated. Your rights under this EULA will terminate automatically and without notice if you fail to comply with any of its terms. Upon termination:</p>
    <ul>
      <li>All rights granted to you under this EULA will immediately cease</li>
      <li>You must stop using the App and delete all copies from your devices</li>
      <li>Active subscription billing will continue through Apple until you cancel via your Apple ID settings</li>
    </ul>
    <p>Sections of this EULA that by their nature should survive termination shall survive, including but not limited to Disclaimer of Warranties, Limitation of Liability, and Governing Law.</p>
  </section>

  <section>
    <h2><span class="icon">⚖️</span> Governing Law</h2>
    <p>This EULA shall be governed by and construed in accordance with the laws of the State of California, United States, without regard to its conflict of law provisions. Any disputes arising under or in connection with this EULA shall be subject to the exclusive jurisdiction of the courts located in California.</p>
  </section>

  <section>
    <h2><span class="icon">✉️</span> Contact Us</h2>
    <p>If you have questions about this EULA or need support, please contact us:</p>
    <p><strong>Cadence Support</strong><br>
    <a href="mailto:carpecarb@icloud.com">carpecarb@icloud.com</a></p>
    <p>We aim to respond to all inquiries within 5 business days.</p>
  </section>

</main>

<footer>
  <p>© 2026 Cadence. All rights reserved.</p>
  <p style="margin-top:6px;">
    <a href="./index.html">Home</a>
    &nbsp;·&nbsp;
    <a href="./privacy-policy.html">Privacy Policy</a>
    &nbsp;·&nbsp;
    <a href="./contact.html">Contact</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/jaguero21/Cadence">GitHub</a>
  </p>
</footer>

</body>
</html>
```

- [ ] **Step 2: Check tag balance**

Run (same checker script, pointed at the new file):
```bash
python3 -c "
import sys
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            print(f'MISMATCH: expected close for {self.stack[-1] if self.stack else None!r}, got </{tag}>')
            sys.exit(1)
        self.stack.pop()

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    html = f.read()
c = Checker()
c.feed(html)
if c.stack:
    print(f'UNCLOSED TAGS: {c.stack}')
    sys.exit(1)
print('OK: tags balanced')
" docs/eula.html
```

Expected output: `OK: tags balanced`

- [ ] **Step 3: Check relative links/assets resolve**

Run:
```bash
grep -oE '(href|src)="\./[^"]*"' docs/eula.html | sed -E 's/^(href|src)="\.\///; s/"$//' | sort -u | while read -r f; do
  if [[ -f "docs/$f" ]]; then echo "OK      $f"; else echo "MISSING $f"; fi
done
```

Expected output:
```
MISSING contact.html
OK      app_icon.png
OK      index.html
OK      privacy-policy.html
```
(`contact.html` doesn't exist yet — resolved by Task 5.)

- [ ] **Step 4: Commit**

```bash
git add docs/eula.html
git commit -m "Add Cadence EULA / Terms of Use page"
```

---

### Task 5: Build `docs/contact.html`

**Files:**
- Create: `docs/contact.html`

**Interfaces:**
- Consumes: `./app_icon.png` (Task 1), `./index.html` (Task 2), `./privacy-policy.html` (Task 3), `./eula.html` (Task 4).
- Produces: `docs/contact.html`, linked as `./contact.html` from every other page.

- [ ] **Step 1: Write the file**

Create `docs/contact.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Contact — Cadence</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #F5F1EB;
      color: #2A2520;
      line-height: 1.7;
      padding: 0 16px 64px;
    }

    header {
      max-width: 720px;
      margin: 0 auto;
      padding: 48px 0 32px;
      border-bottom: 1px solid rgba(42,37,32,0.12);
    }

    .logo {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }

    .logo-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      overflow: hidden;
      flex-shrink: 0;
    }

    .logo-icon img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .logo-name {
      font-size: 22px;
      font-weight: 600;
      color: #2A2520;
      letter-spacing: 0.2px;
    }

    h1 {
      font-size: 32px;
      font-weight: 700;
      color: #2A2520;
      margin-bottom: 8px;
    }

    .meta {
      font-size: 15px;
      color: #8A7D74;
    }

    main {
      max-width: 720px;
      margin: 40px auto 0;
    }

    section {
      background: #ffffff;
      border-radius: 16px;
      padding: 28px 32px;
      margin-bottom: 16px;
      box-shadow: 0 2px 8px rgba(42,37,32,0.06);
    }

    h2 {
      font-size: 18px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    h2 .icon {
      width: 28px;
      height: 28px;
      background: rgba(42,157,143,0.15);
      border-radius: 7px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 15px;
      flex-shrink: 0;
    }

    p { margin-bottom: 12px; color: #3D3530; font-size: 15px; }
    p:last-child { margin-bottom: 0; }

    a { color: #2A9D8F; text-decoration: none; }
    a:hover { text-decoration: underline; }

    label {
      display: block;
      font-size: 14px;
      font-weight: 600;
      color: #2A2520;
      margin-bottom: 6px;
      margin-top: 16px;
    }

    label:first-of-type { margin-top: 0; }

    select,
    input[type="text"],
    input[type="email"],
    textarea {
      width: 100%;
      padding: 12px 14px;
      border: 1.5px solid rgba(42,37,32,0.15);
      border-radius: 10px;
      font-size: 15px;
      font-family: inherit;
      color: #2A2520;
      background: #FDFAF6;
      transition: border-color 0.15s;
      appearance: none;
      -webkit-appearance: none;
    }

    select {
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%238A7D74' stroke-width='1.5' fill='none' stroke-linecap='round'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 14px center;
      padding-right: 36px;
      cursor: pointer;
    }

    select:focus,
    input[type="text"]:focus,
    input[type="email"]:focus,
    textarea:focus {
      outline: none;
      border-color: #2A9D8F;
      box-shadow: 0 0 0 3px rgba(42,157,143,0.15);
    }

    textarea {
      resize: vertical;
      min-height: 140px;
    }

    .submit-btn {
      display: inline-block;
      margin-top: 20px;
      padding: 14px 32px;
      background: #2A9D8F;
      color: #ffffff;
      font-size: 16px;
      font-weight: 600;
      font-family: inherit;
      border: none;
      border-radius: 12px;
      cursor: pointer;
      transition: background 0.15s, transform 0.1s;
      width: 100%;
    }

    .submit-btn:hover { background: #258A7E; }
    .submit-btn:active { transform: scale(0.98); }

    .note {
      font-size: 13px;
      color: #8A7D74;
      margin-top: 12px;
      text-align: center;
    }

    .highlight {
      background: rgba(42,157,143,0.1);
      border-left: 3px solid #2A9D8F;
      border-radius: 0 8px 8px 0;
      padding: 12px 16px;
      margin-bottom: 12px;
      font-size: 15px;
      color: #3D3530;
    }

    .topics {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      margin-top: 4px;
    }

    .topic-card {
      background: #FDFAF6;
      border: 1.5px solid rgba(42,37,32,0.1);
      border-radius: 10px;
      padding: 14px 16px;
      font-size: 14px;
      color: #3D3530;
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .topic-card .t-icon { font-size: 18px; }

    footer {
      max-width: 720px;
      margin: 32px auto 0;
      text-align: center;
      font-size: 13px;
      color: #8A7D74;
    }

    @media (max-width: 520px) {
      .topics { grid-template-columns: 1fr; }
      section { padding: 20px 18px; }
    }
  </style>
</head>
<body>

<header>
  <div class="logo">
    <div class="logo-icon"><img src="./app_icon.png" alt="Cadence" /></div>
    <span class="logo-name">Cadence</span>
  </div>
  <h1>Contact Us</h1>
  <p class="meta">We'd love to hear from you. We aim to respond within 5 business days.</p>
</header>

<main>

  <section>
    <h2><span class="icon">💬</span> What can we help with?</h2>
    <div class="topics">
      <div class="topic-card"><span class="t-icon">🐛</span> Bug reports</div>
      <div class="topic-card"><span class="t-icon">💡</span> Feature requests</div>
      <div class="topic-card"><span class="t-icon">💳</span> Subscription &amp; billing</div>
      <div class="topic-card"><span class="t-icon">🔒</span> Privacy questions</div>
      <div class="topic-card"><span class="t-icon">🗑️</span> Data deletion</div>
      <div class="topic-card"><span class="t-icon">✉️</span> General feedback</div>
    </div>
  </section>

  <section>
    <h2><span class="icon">✉️</span> Send a Message</h2>
    <div class="highlight">
      Tapping "Open in Mail" will open your email app with a pre-filled message. No information is submitted through this website.
    </div>

    <form id="contactForm">
      <label for="topic">Topic</label>
      <select id="topic" name="topic">
        <option value="General question">General question</option>
        <option value="Bug report">Bug report</option>
        <option value="Feature request">Feature request</option>
        <option value="Subscription / billing">Subscription / billing</option>
        <option value="Privacy question">Privacy question</option>
        <option value="Data deletion request">Data deletion request</option>
        <option value="Other">Other</option>
      </select>

      <label for="name">Your name <span style="font-weight:400;color:#8A7D74">(optional)</span></label>
      <input type="text" id="name" name="name" placeholder="Jane Smith" autocomplete="name" />

      <label for="email">Your email <span style="font-weight:400;color:#8A7D74">(so we can reply)</span></label>
      <input type="email" id="email" name="email" placeholder="you@example.com" autocomplete="email" />

      <label for="message">Message</label>
      <textarea id="message" name="message" placeholder="Describe your question, feedback, or concern…"></textarea>

      <button type="button" class="submit-btn" onclick="openMail()">Open in Mail</button>
      <p class="note">This opens your default mail app with the message pre-filled.</p>
    </form>
  </section>

  <section>
    <h2><span class="icon">📬</span> Direct Email</h2>
    <p>Prefer to write your own email? Reach us directly at:</p>
    <p><strong><a href="mailto:carpecarb@icloud.com">carpecarb@icloud.com</a></strong></p>
    <p>For subscription cancellations or billing issues, you can also manage your subscription directly through <strong>Settings → Apple ID → Subscriptions</strong> on your iPhone.</p>
  </section>

</main>

<footer>
  <p>© 2026 Cadence. All rights reserved.</p>
  <p style="margin-top:8px;">
    <a href="./index.html">Home</a>
    &nbsp;·&nbsp;
    <a href="./privacy-policy.html">Privacy Policy</a>
    &nbsp;·&nbsp;
    <a href="./eula.html">Terms of Use</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/jaguero21/Cadence">GitHub</a>
  </p>
</footer>

<script>
  function openMail() {
    var topic = document.getElementById('topic').value;
    var name = document.getElementById('name').value.trim();
    var replyTo = document.getElementById('email').value.trim();
    var message = document.getElementById('message').value.trim();

    if (!message) {
      alert('Please enter a message before continuing.');
      document.getElementById('message').focus();
      return;
    }

    if (replyTo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(replyTo)) {
      alert('Please enter a valid email address so we can reply.');
      document.getElementById('email').focus();
      return;
    }

    var subject = encodeURIComponent('Cadence: ' + topic);

    var body = '';
    if (name) body += 'Name: ' + name + '\n';
    if (replyTo) body += 'Reply-to: ' + replyTo + '\n';
    body += '\n' + message;

    window.location.href = 'mailto:carpecarb@icloud.com?subject=' + subject + '&body=' + encodeURIComponent(body);
  }
</script>

</body>
</html>
```

- [ ] **Step 2: Check tag balance**

Run (same checker script, pointed at the new file):
```bash
python3 -c "
import sys
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

class Checker(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            print(f'MISMATCH: expected close for {self.stack[-1] if self.stack else None!r}, got </{tag}>')
            sys.exit(1)
        self.stack.pop()

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    html = f.read()
c = Checker()
c.feed(html)
if c.stack:
    print(f'UNCLOSED TAGS: {c.stack}')
    sys.exit(1)
print('OK: tags balanced')
" docs/contact.html
```

Expected output: `OK: tags balanced`

- [ ] **Step 3: Check relative links/assets resolve — this page's own links should all be clean since it's built last**

Run:
```bash
grep -oE '(href|src)="\./[^"]*"' docs/contact.html | sed -E 's/^(href|src)="\.\///; s/"$//' | sort -u | while read -r f; do
  if [[ -f "docs/$f" ]]; then echo "OK      $f"; else echo "MISSING $f"; fi
done
```

Expected output:
```
OK      app_icon.png
OK      eula.html
OK      index.html
OK      privacy-policy.html
```

- [ ] **Step 4: Commit**

```bash
git add docs/contact.html
git commit -m "Add Cadence contact page"
```

---

### Task 6: Cross-page verification and visual QA

**Files:** none created — verification only, using the four files from Tasks 2–5 and the two assets from Task 1.

**Interfaces:**
- Consumes: all files produced by Tasks 1–5.
- Produces: confirmation that the site is internally consistent and renders correctly — the final gate before this is ready for the user to publish.

- [ ] **Step 1: Full cross-page link/asset check — every relative link across all four pages must now resolve**

Run:
```bash
for page in docs/index.html docs/privacy-policy.html docs/eula.html docs/contact.html; do
  echo "=== $page ==="
  grep -oE '(href|src)="\./[^"]*"' "$page" | sed -E 's/^(href|src)="\.\///; s/"$//' | sort -u | while read -r f; do
    if [[ -f "docs/$f" ]]; then echo "OK      $f"; else echo "MISSING $f"; fi
  done
done
```

Expected output: every line reads `OK` — zero `MISSING` lines across all four sections. If any `MISSING` line appears, stop and fix the broken link/path before continuing (do not proceed to Step 2 with a broken link).

- [ ] **Step 2: Confirm the TestFlight placeholder is exactly where expected, and only there**

Run:
```bash
grep -rn "testflight-link-here" docs/
```

Expected output: exactly one match, in `docs/index.html`, on the `<a href="#testflight-link-here" ...>` line (plus the preceding HTML comment on its own line). If it appears anywhere else, or the anchor text differs, fix it.

- [ ] **Step 3: Visual QA — open each page and screenshot it**

Run:
```bash
open docs/index.html
```

Wait ~2 seconds for the browser to render, then run:
```bash
screencapture -x /private/tmp/claude-501/-Volumes-APFS2-SwiftPorjects-Cadence/d3dda738-3ef9-4143-b455-06f1dda0061d/scratchpad/qa-index.png
```

Read the resulting screenshot and visually confirm:
- Hero shows the teal/gold wave app icon, "Cadence" heading, tagline, a teal "Join the TestFlight Beta" button, and two badges
- All 6 card sections render with visible icon chips and correct teal (not sage green) accents
- The Pro section's star icon chip and highlight box are purple, not teal
- The Support section shows the capybara mascot next to the contact text, sitting cleanly on the cream background (no white box behind it)
- Footer shows the 4 legal/GitHub links

Repeat Step 3 for the other three pages — open, wait, screenshot to a distinct filename (`qa-privacy.png`, `qa-eula.png`, `qa-contact.png`) in the same scratchpad directory, and Read each to confirm: the header/logo chrome renders correctly, teal accents replace sage green throughout, and (for `contact.html` specifically) the select dropdown arrow and form field focus ring are visible and teal.

If any visual issue is found, fix it in the relevant file from Tasks 2–5, re-run that task's Step 2/3 checks, take a fresh screenshot to confirm the fix, and commit the fix with a message describing what was wrong (e.g. `git commit -m "Fix mascot alignment in Cadence landing page Support section"`).

- [ ] **Step 4: Report status to the user**

No further commit needed if Steps 1–3 pass clean (everything was already committed per-task in Tasks 1–5). Summarize for the user: the site is complete and internally consistent; the two remaining manual steps before it's live are (1) making `jaguero21/Cadence` public, and (2) enabling GitHub Pages in repo Settings → Pages (source: `main` / `/docs`) — and swapping the `#testflight-link-here` placeholder for the real TestFlight link.

---

## Self-Review

**Spec coverage:** All 7 index.html sections (Hero, How It Works, Everything Free, Cadence Pro, Privacy & Security, Apple Ecosystem, Support), all `privacy-policy.html` sections (11), all `eula.html` sections (13), and `contact.html`'s form/topics/direct-email sections from the spec are each written out in full in Tasks 2–5. The two image assets and their verification are in Task 1. The palette substitution table (teal primary, purple Pro accent, unchanged cream/ink) is applied consistently across every task's CSS. The "own identity" mascot placement (Support section, index.html only) is in Task 2. All spec "Open items" (TestFlight placeholder, repo visibility, enabling Pages) are captured in Global Constraints and Task 6 Step 4 as explicit out-of-scope manual steps.

**Placeholder scan:** The only intentional placeholder is `#testflight-link-here`, which the spec calls for explicitly and Task 6 Step 2 verifies is present exactly once. No other TBD/TODO markers exist in any task.

**Type/naming consistency:** File names (`app_icon.png`, `mascot.png`, `index.html`, `privacy-policy.html`, `eula.html`, `contact.html`) and their relative link forms (`./app_icon.png`, etc.) are identical across every task that references them — checked by re-reading each task's link list against the producing task's filename. Hex colors (`#2A9D8F` / `#258A7E` / `#8B7EC8` / `#F5F1EB` / `#2A2520` / `#3D3530` / `#8A7D74`) are used identically in every CSS block across all four files.
