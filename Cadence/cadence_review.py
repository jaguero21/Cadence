#!/usr/bin/env python3
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
)
from reportlab.lib.enums import TA_LEFT, TA_CENTER
import datetime

OUTPUT = "/Volumes/APFS2/SwiftPorjects/Cadence/Cadence-Code-Review.pdf"

# ── Colours ──────────────────────────────────────────────────────────────────
ACCENT      = colors.HexColor("#5B5EA6")   # indigo
HIGH_RED    = colors.HexColor("#D7263D")
MED_ORANGE  = colors.HexColor("#E07B39")
LOW_BLUE    = colors.HexColor("#4A90D9")
BG_LIGHT    = colors.HexColor("#F4F4F8")
BG_TABLE    = colors.HexColor("#ECECF4")
TEXT_DARK   = colors.HexColor("#1A1A2E")
TEXT_MUTED  = colors.HexColor("#6B6B8A")
DIVIDER     = colors.HexColor("#CACAE0")
CODE_BG     = colors.HexColor("#EEEEF8")

# ── Styles ───────────────────────────────────────────────────────────────────
base = getSampleStyleSheet()

def S(name, **kw):
    return ParagraphStyle(name, **kw)

title_style = S("Title",
    fontName="Helvetica-Bold", fontSize=22, textColor=ACCENT,
    spaceAfter=4, alignment=TA_LEFT)

subtitle_style = S("Subtitle",
    fontName="Helvetica", fontSize=11, textColor=TEXT_MUTED,
    spaceAfter=2)

meta_style = S("Meta",
    fontName="Helvetica", fontSize=9, textColor=TEXT_MUTED,
    spaceAfter=14)

h2_style = S("H2",
    fontName="Helvetica-Bold", fontSize=14, textColor=ACCENT,
    spaceBefore=18, spaceAfter=6)

h3_style = S("H3",
    fontName="Helvetica-Bold", fontSize=11, textColor=TEXT_DARK,
    spaceBefore=12, spaceAfter=4)

body_style = S("Body",
    fontName="Helvetica", fontSize=10, textColor=TEXT_DARK,
    leading=15, spaceAfter=4)

code_style = S("Code",
    fontName="Courier", fontSize=9, textColor=colors.HexColor("#2E2E5E"),
    backColor=CODE_BG, leading=13, leftIndent=8, rightIndent=8,
    spaceBefore=4, spaceAfter=4)

bullet_style = S("Bullet",
    fontName="Helvetica", fontSize=10, textColor=TEXT_DARK,
    leading=15, leftIndent=14, spaceAfter=3)

label_high = S("LH", fontName="Helvetica-Bold", fontSize=9,
    textColor=colors.white, alignment=TA_CENTER)
label_med  = S("LM", fontName="Helvetica-Bold", fontSize=9,
    textColor=colors.white, alignment=TA_CENTER)
label_low  = S("LL", fontName="Helvetica-Bold", fontSize=9,
    textColor=colors.white, alignment=TA_CENTER)

# ── Helpers ──────────────────────────────────────────────────────────────────
def p(text, style=None):
    return Paragraph(text, style or body_style)

def sp(h=6):
    return Spacer(1, h)

def hr():
    return HRFlowable(width="100%", thickness=0.5, color=DIVIDER, spaceAfter=6)

def badge(text, colour):
    tbl = Table([[Paragraph(text, S("b", fontName="Helvetica-Bold", fontSize=8,
                                    textColor=colors.white, alignment=TA_CENTER))]],
                colWidths=[1.4*cm], rowHeights=[0.45*cm])
    tbl.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), colour),
        ("ROUNDEDCORNERS", [3]),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ]))
    return tbl

def issue_block(num, title, priority, location, body_paras, fix_lines=None):
    priority_colours = {"High": HIGH_RED, "Medium": MED_ORANGE, "Low": LOW_BLUE}
    pc = priority_colours.get(priority, LOW_BLUE)

    header_data = [[
        p(f"<b>#{num}</b>", S("ih", fontName="Helvetica-Bold", fontSize=10,
                               textColor=ACCENT)),
        p(f"<b>{title}</b>", S("it", fontName="Helvetica-Bold", fontSize=10,
                                textColor=TEXT_DARK)),
        badge(priority, pc),
    ]]
    header = Table(header_data, colWidths=[0.8*cm, 11.8*cm, 1.6*cm])
    header.setStyle(TableStyle([
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("BACKGROUND", (0,0), (-1,-1), BG_LIGHT),
        ("TOPPADDING",    (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
        ("LEFTPADDING",   (0,0), (-1,-1), 8),
        ("RIGHTPADDING",  (0,0), (-1,-1), 8),
    ]))

    elems = [header]
    if location:
        elems.append(p(f'<font color="#6B6B8A" size="8">{location}</font>'))
    for bp in body_paras:
        elems.append(bp)
    if fix_lines:
        elems.append(p('<font color="#2E2E5E" size="9"><b>Suggested fix:</b></font>'))
        for line in fix_lines:
            elems.append(Paragraph(line, code_style))
    elems.append(sp(8))
    return elems

# ── Document ─────────────────────────────────────────────────────────────────
doc = SimpleDocTemplate(
    OUTPUT,
    pagesize=A4,
    leftMargin=2.2*cm, rightMargin=2.2*cm,
    topMargin=2.2*cm,  bottomMargin=2.2*cm,
)

story = []

# ── Cover / Header ───────────────────────────────────────────────────────────
story.append(p("Cadence", title_style))
story.append(p("iOS App — Code Review", subtitle_style))
story.append(p(f"Reviewed {datetime.date.today().strftime('%B %d, %Y')}  ·  29 Swift files  ·  SwiftUI + SwiftData", meta_style))
story.append(hr())
story.append(sp(4))

# ── Overview ─────────────────────────────────────────────────────────────────
story.append(p("Overview", h2_style))
story.append(p(
    "Cadence is a well-structured health journaling app. The architecture is clean — "
    "MVVM with a clear boundary between Models, Services, and Features, consistent "
    "<b>@MainActor</b> usage, and a sensible SwiftData schema. The issues below are "
    "correctness bugs and design gaps, not style problems. High-priority items involve "
    "silent failures and broken notification logic; lower-priority items are "
    "code-quality improvements."
))
story.append(sp(6))

# ── Summary Table ─────────────────────────────────────────────────────────────
story.append(p("Summary", h2_style))

summary_data = [
    [p("<b>#</b>", S("sh", fontName="Helvetica-Bold", fontSize=9, textColor=colors.white)),
     p("<b>Issue</b>", S("sh", fontName="Helvetica-Bold", fontSize=9, textColor=colors.white)),
     p("<b>Priority</b>", S("sh", fontName="Helvetica-Bold", fontSize=9, textColor=colors.white))],
    ["1", "Streak notification never fires when today is incomplete", "High"],
    ["2", "stressFatiguePattern checks wrong log index (off-by-one)", "High"],
    ["3", "Silent save failures give false success feedback",          "High"],
    ["4", "analyze() stub is dead code — misleading",                  "Medium"],
    ["5", "Streak-at-risk notification fires wrong day after 9 PM",   "Medium"],
    ["6", "Default sleepHours = 7.0 skews sleep correlation",         "Medium"],
    ["7", "InsightCard.id is var instead of let",                      "Low"],
    ["8", "Hardcoded magic confidence scores (0.85, 0.78)",            "Low"],
    ["9", "Force unwraps in calendar math",                            "Low"],
    ["10","Synchronous pattern computation on @MainActor",             "Low"],
    ["11","PDF export overwrites previous file (fixed filename)",       "Low"],
]

priority_map = {"High": HIGH_RED, "Medium": MED_ORANGE, "Low": LOW_BLUE}
table_style = [
    ("BACKGROUND", (0,0), (-1,0), ACCENT),
    ("BACKGROUND", (0,1), (-1,-1), colors.white),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, BG_LIGHT]),
    ("FONTNAME",  (0,0), (-1,0),  "Helvetica-Bold"),
    ("FONTSIZE",  (0,0), (-1,-1), 9),
    ("TEXTCOLOR", (0,1), (-1,-1), TEXT_DARK),
    ("GRID",      (0,0), (-1,-1), 0.3, DIVIDER),
    ("TOPPADDING",    (0,0), (-1,-1), 5),
    ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ("LEFTPADDING",   (0,0), (-1,-1), 7),
    ("VALIGN",    (0,0), (-1,-1), "MIDDLE"),
]

plain_rows = []
for i, row in enumerate(summary_data):
    if i == 0:
        plain_rows.append(row)
    else:
        num, desc, pri = row
        pc = priority_map.get(pri, LOW_BLUE)
        plain_rows.append([
            Paragraph(num,  S("tc", fontName="Helvetica", fontSize=9, textColor=TEXT_MUTED)),
            Paragraph(desc, S("td", fontName="Helvetica", fontSize=9, textColor=TEXT_DARK)),
            Paragraph(f"<b>{pri}</b>", S("tp", fontName="Helvetica-Bold", fontSize=9, textColor=pc)),
        ])

tbl = Table(plain_rows, colWidths=[0.7*cm, 12.0*cm, 1.8*cm])
tbl.setStyle(TableStyle(table_style))
story.append(tbl)
story.append(sp(14))

# ── Detailed Findings ────────────────────────────────────────────────────────
story.append(p("Detailed Findings", h2_style))
story.append(hr())

# --- Bugs ---
story.append(p("Bugs", h3_style))

story += issue_block(
    1, "Streak notification never fires when today is incomplete",
    "High",
    "Features/Dashboard/DashboardViewModel.swift — computeStreak(), refresh()",
    [p("computeStreak filters only <b>complete</b> logs, then checks if each date equals "
       "<b>startOfDay(now)</b>. If today's log is incomplete, the first matching date is "
       "yesterday — which doesn't equal <i>check</i>, so the loop breaks immediately and "
       "returns streak = 0. The guard <code>if streak &gt; 0 &amp;&amp; todayLog?.isComplete != true</code> "
       "in refresh() is therefore never true, so scheduleStreakAtRisk() never fires. "
       "The entire streak-at-risk notification flow is silently broken.")],
    fix_lines=[
        "var check = Calendar.current.startOfDay(for: .now)",
        "if todayLog?.isComplete != true {",
        "    check = Calendar.current.date(byAdding: .day, value: -1, to: check)!",
        "}",
    ]
)

story += issue_block(
    2, "stressFatiguePattern checks the wrong log index",
    "High",
    "Services/PatternEngine.swift — stressFatiguePattern(), line 72",
    [p("When stress breaks at index <b>i</b>, <code>logs[i]</code> is the first normal-stress "
       "day. The detector then checks <code>logs[i + 1]</code> for fatigue — that is "
       "<i>two days after the streak ends</i>, not the recovery day itself. "
       "The check should be on <code>logs[i]</code>.")],
    fix_lines=[
        "// wrong:",
        "let nextSymptoms = logs[i + 1].symptoms.map { $0.name.lowercased() }",
        "// correct:",
        "let nextSymptoms = logs[i].symptoms.map { $0.name.lowercased() }",
    ]
)

story += issue_block(
    3, "Silent save failures give false positive feedback",
    "High",
    "Features/DailyLog/DailyLogViewModel.swift:29  ·  Features/WeeklyReview/WeeklyReviewViewModel.swift:47",
    [p("Both use <code>try? context.save()</code>. If the save fails the user receives "
       "a haptic success response and sees the 'Log complete!' screen, while their data "
       "was silently discarded. At minimum propagate the error to the caller; ideally "
       "present an alert so the user knows their entry was not saved.")],
)

story += issue_block(
    4, "PatternEngine.analyze() is a stub — misleading dead code",
    "Medium",
    "Services/PatternEngine.swift:26-29  ·  Features/DailyLog/DailyLogViewModel.swift:33",
    [p("analyze() is called after every log save but its body is empty. The comment "
       "'In production: persist computed insights to SwiftData' implies future work, "
       "but in its current form it accepts a ModelContext it never uses and implies "
       "side effects that don't happen. Either implement persistence or remove the "
       "method and the call-site in DailyLogViewModel.save().")],
)

story += issue_block(
    5, "Streak-at-risk notification fires the wrong day after 9 PM",
    "Medium",
    "Services/NotificationService.swift:60-68",
    [p("UNCalendarNotificationTrigger with past time components automatically fires "
       "on the <b>next</b> matching time. If a user opens the app at 10 PM, the "
       "notification is scheduled for 9 PM the following day — 23 hours late. "
       "Add an early-return guard when the current hour is already past 21:00.")],
    fix_lines=[
        "let hour = Calendar.current.component(.hour, from: .now)",
        "guard hour < 21 else { return }",
    ]
)

story += issue_block(
    6, "Default sleepHours = 7.0 skews sleep correlation analysis",
    "Medium",
    "Models/DailyLog.swift:37  ·  Services/PatternEngine.swift — moodSleepCorrelation()",
    [p("DailyLog initialises sleepHours to 7.0. If a user never touches the sleep slider "
       "the log records 7.0 hours, and moodSleepCorrelation's filter <code>$0.sleepHours &gt; 0</code> "
       "won't exclude those logs. This inflates the population and biases the average. "
       "The didEditMetrics flag already exists — use it to exclude unedited logs from "
       "sleep analysis.")],
    fix_lines=[
        "let pairs = logs.filter { $0.sleepHours > 0 && $0.didEditMetrics }",
    ]
)

# --- Code Quality ---
story.append(p("Code Quality", h3_style))

story += issue_block(
    7, "InsightCard.id is var instead of let",
    "Low",
    "Features/Insights/InsightsViewModel.swift:6",
    [p("Mutable identifiers break Identifiable semantics — SwiftUI diff-ing can "
       "produce unexpected re-renders if an id changes. Change to <code>let id = UUID()</code>.")],
)

story += issue_block(
    8, "Hardcoded magic confidence scores",
    "Low",
    "Services/PatternEngine.swift — energyTrendDecline():107, moodSleepCorrelation():127",
    [p("energyTrendDecline returns <code>confidence: 0.85</code> and moodSleepCorrelation "
       "returns <code>confidence: 0.78</code> unconditionally regardless of the data. "
       "The other two detectors compute confidence from actual occurrence rates. "
       "Either derive the value from the data or remove the field from those cards "
       "so it isn't surfaced as a meaningful number in the UI.")],
)

story += issue_block(
    9, "Force unwraps on Calendar.date(byAdding:)",
    "Low",
    "Features/Dashboard/DashboardViewModel.swift:33  ·  Services/HealthKitService.swift:29-31",
    [p("Calendar.date(byAdding:to:) returns an Optional. Both call sites force-unwrap "
       "with <code>!</code>. While calendar arithmetic rarely fails in practice, "
       "use <code>guard let</code> with a graceful fallback to avoid any edge-case crash.")],
)

story += issue_block(
    10, "Synchronous pattern computation on @MainActor",
    "Low",
    "Services/PatternEngine.swift — allInsights(from:)",
    [p("All four pattern detectors iterate over the full log array synchronously on "
       "the main thread. With moderate data (365+ logs) this is fast, but the approach "
       "won't scale. Consider wrapping computation in Task.detached or moving "
       "PatternEngine to a background actor.")],
)

story += issue_block(
    11, "PDF export overwrites previous file",
    "Low",
    "Features/Export/PDFBuilder.swift:14",
    [p("PDFBuilder writes to a fixed filename in the temp directory "
       "(<code>cadence-doctor-report.pdf</code>). Generating two reports quickly "
       "can overwrite the first before the share sheet reads it. Append a timestamp "
       "or UUID to the filename.")],
    fix_lines=[
        'let stamp = Int(Date.now.timeIntervalSince1970)',
        'let filename = type == .doctor',
        '    ? "cadence-doctor-report-\\(stamp).pdf"',
        '    : "cadence-personal-summary-\\(stamp).pdf"',
    ]
)

# ── Footer ───────────────────────────────────────────────────────────────────
story.append(sp(10))
story.append(hr())
story.append(p(
    f"Generated by Claude Code  ·  {datetime.date.today().strftime('%B %d, %Y')}",
    S("footer", fontName="Helvetica", fontSize=8, textColor=TEXT_MUTED, alignment=TA_CENTER)
))

doc.build(story)
print(f"PDF written to: {OUTPUT}")
