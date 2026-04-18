# StudyNotch 🎓

> A macOS app that lives in your **MacBook notch** — a full-featured study companion with timers, Pomodoro presets, analytics, AI coaching, spaced repetition, tasks, exams, Notion sync, and more.

**Version:** v13 · **Requires:** macOS 13+ · **Architecture:** Apple Silicon + Intel (universal via Swift PM)

---

## Quick Start

```bash
cd StudyNotch
./build.sh
```

First build ~60 s · subsequent builds ~10 s. The script compiles, bundles, signs, kills the old instance, and launches automatically.

> **Accessibility permission** — approve once on first run. The app uses the same binary path (`/Applications/StudyNotch.app`) every build so you never need to re-approve.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⌥T` | Start / Pause timer |
| `⌘⌥F` | Finish session |
| `⌘⌥R` | Reset timer |
| `⌘⌥M` | Log manual session |
| `⌘⌥S` | Open Analytics |
| `⌘⌥D` | Open Today window |
| `⌘⌥P` | Open Study Plan |
| `⌘⌥K` | Open Study Plan → Tasks |
| `⌘⌥C` | Open AI Chat |

---

## The Notch Pill

### Collapsed (idle)
| Element | Behaviour |
|---------|-----------|
| Colored dot | Subject color; pulses while timer runs |
| LED glow | Whole pill glows in subject color during active session; intensity scales with streak length (momentum glow) |
| Stress glow | Red pulse when exam is today or ≥3 tasks overdue; orange for 1–2 overdue |
| Calendar badge | Next Google Calendar event e.g. `📅 Math 14:30` |
| Exam countdown | `● Physics · 3d` when exam ≤ 7 days away |
| Overdue badge | Red `2!` when tasks are overdue |
| XP level | `LV3` when nothing urgent |

### Expanded (hover)
Subject strip · 🎲 dice · ✏️ pin manager · **Pomodoro presets** · timer controls · 📝 quick notes · pending tasks for current subject · Telegram field

### Pomodoro Presets ⏱
Quick-start timed sessions directly from the notch pill:
| Preset | Behaviour |
|--------|-----------|
| **25m** | Classic Pomodoro |
| **45m** | Extended focus |
| **60m** | Full hour deep work |
| **90m** | Ultra-focus block |
| **∞** | Free mode (no time limit) |

When a Pomodoro is active:
- **Progress ring** wraps around the timer dot showing elapsed vs target
- **Countdown** shows remaining time next to the subject label (e.g. `· 12:45 left`)
- **Auto-finish** — when time expires, the Session End screen opens automatically with the subject pre-selected

### Quick Notes 📝
While a session is running, tap the 📝 button in the timer control row to jot a quick note. Notes are:
- Stored in the timer until the session ends
- **Auto-filled** into the Session End notes field
- Cleared on timer reset

### Spin the Wheel 🎲
Fully random subject picker from pinned subjects with roulette animation.

- Uses independent random picks for roll frames and final winner
- Randomized spin length (12–18 flashes) and timing jitter for less predictable motion
- Case-insensitive deduping of candidates
- Avoids immediate repeats when more than one candidate exists

### Pin Manager (✏️)
- **Semester auto-sync** — subjects from your semester database appear automatically
- **Manual add** — add custom notch-only subjects from this popup (auto-pins on add)
- **Color-coded dots** — each subject uses its configured Subject Settings color
- **Delete from notch list** — hides a subject from the notch picker and unpins it
- **Safe delete behavior** — deleting here does not remove semester subjects or session history
- **Pin / Unpin** — controls what appears in the quick-select strip and what dice rolls

---

## Auto-Session Detection

Polls the frontmost app every 5 seconds and shows a non-intrusive banner when it detects studying.

| Trigger | Dwell before popup | Examples |
|---------|-------------------|---------|
| Academic folder in Finder | **5 s** | "Second Term", "Semester 2", "Lectures" |
| PDF viewer opened | **5 s** | Preview, Skim, PDF Expert, Adobe |
| Browser | **20 s** | Chrome, Safari, Firefox, Edge, Brave, Arc |
| Other study apps | **60 s** | VS Code, Word, Terminal, Notion, Obsidian |

**Requires Accessibility permission** for window-title subject matching. Without it, the detector falls back to bundle ID classification + your most-studied subject.

**Add custom folder patterns** — edit `academicFolderPatterns` in `AutoSessionDetector.swift` or at runtime:
```swift
AutoSessionDetector.shared.academicFolderPatterns.append("csen 401")
```

**Snooze** — the banner has a 🕐 button to remind you again in 5 minutes without triggering the full 10-minute cooldown.

---

## Focus Score

Every completed session gets a 0–100 quality score computed from four factors:

| Factor | Detail |
|--------|--------|
| **Duration** | −40 for <10 min · −25 for <20 min · −10 for <30 min · +5 for ≥60 min · +10 for ≥90 min |
| **Distractions** | −12 pts per distraction per 30-min block (rate-normalised); >6 total caps score at 58 |
| **Pause ratio** | −25 for >40% paused · −15 for >25% · −7 for >12% · +5 bonus for completely unbroken ≥25 min |
| **Difficulty** | −4 for difficulty 1 · +4 for difficulty 4 · +8 for difficulty 5 |

| Score | Grade |
|-------|-------|
| 90–100 | 🔥 Excellent |
| 75–89 | ⭐ Great |
| 60–74 | 👍 Good |
| 40–59 | 📈 Fair |
| 0–39 | 💪 Keep Going |

The animated `FocusScoreCard` appears in the Session End screen with a ring animation and plain-English breakdown. The score is computed at runtime from existing stored fields — **no migration needed for past sessions**.

---

## Analytics Window (`⌘⌥S`)

Four top-level tabs: **Today · Progress · Plan · Brain**

The **Today** tab is the default landing page — it opens first when clicking Analytics from the notch pill.

### Today tab
Daily summary: today's study time · sessions logged · subject breakdown · tasks due today · imminent exam countdown.

### Progress tab
- **Overview** — 7-day bar chart, subject donut, hourly heatmap, weekly progress ring (vs 20 h/week goal)
- **Sessions** — full history; edit (✏️), replay (▶), delete (🗑); XP deducted on delete
- **Insights** — distraction patterns: by time of day, when in session, by type, by subject. All charts tappable for exact counts
- **XP & Achievements** — level card (tap → Level Ladder sheet), achievement cards (tap → detail + unlock date), weekly challenge progress bar

### Plan tab
- This Week summary vs weekly goal hours
- Tasks list (overdue → due soon → high priority)
- Exams list with countdown

### Brain tab
- **AI Coach** — Smart Schedule · Weekly Report · Study Style · Course Analysis (Groq Llama 3.3 70B, free)
- **Calendar** — Google Calendar connection and sync status
- **Notes** — all quick notes by subject with image thumbnails

---

## Session End Screen

- Subject **auto-selected** from notch pill choice
- End time correctly reflects **real wall-clock time** (pauses accounted for)
- Quick notes from the session **auto-filled** into notes field
- Difficulty: 1⭐ Hard → 5⭐⭐⭐⭐⭐ Easy
- **Focus Score card** with animated ring + live breakdown (re-animates when you change difficulty)
- Rich text notes field
- Completed task checkboxes
- Save → pushes to Notion sessions database

---

## Session Replay (`▶` in history)

- Visual timeline: green focus · orange pauses · red distraction markers
- **▶ Replay** — animated white playhead scrubs timeline in real time
- Speed: 5× · 10× · 30×
- **Edit** button — rich-text editor for notes and difficulty

---

## Rich Text Notes Editor

| Button | Action |
|--------|--------|
| **B** | Bold |
| *I* | Italic |
| U̲ | Underline |
| 🎨 | Text color picker |
| 🖊 | Highlight (yellow / green / pink / none) |
| 📷 | Insert image from file |
| ✕ | Clear formatting |

`⌘V` pastes images from clipboard. Stored as RTF; plain-text copy kept in sync for search / AI / Notion.

---

## Study Plan (`⌘⌥P`)

**Tabs:** Heatmap · Weekly Plan · Exams · Tasks · Notifications

### Heatmap
GitHub-style 12-week contribution grid. Color intensity = hours studied that day.

### Weekly Plan
Set weekly hour goals per subject. Progress ring shows actual vs target.

### Exams
- Add date, time, location, notes
- Push to Google Calendar with 4 automatic reminders (7d · 3d · 1d · 2h)
- Urgency colors; countdown in pill ≤ 7 days

### Tasks
- Fields: title · type · priority · due date · subject · progress
- **Types**: General · Video (`min`) · Lecture (`pages`) · Assignment · Sheet (`questions`) — Video/Lecture/Sheet show progress counters
- Smart sort: overdue → due soon → high priority
- Completing a task awards XP; overdue tasks show red badge in pill

---

## XP & Gamification

**Triple-protected data**: primary JSON + backup JSON + UserDefaults (`max()` on load — XP can never go backwards).

**8 levels:**
| Level | Title | XP Required |
|-------|-------|-------------|
| 1 | Freshman | 0 |
| 2 | Sophomore | 200 |
| 3 | Junior | 600 |
| 4 | Senior | 1,200 |
| 5 | Honor Student | 2,200 |
| 6 | Dean's List | 3,800 |
| 7 | Graduate | 6,000 |
| 8 | Professor | 9,000 |

- Deleting a session **deducts** its XP
- Tap level card → Level Ladder sheet
- Tap achievement → detail sheet (unlock date, XP reward, requirement)
- Weekly Challenge with animated progress bar

---

## Streak System

- Current streak — consecutive days with ≥1 session
- Longest streak ever
- 12-week GitHub-style contribution grid
- **Streak Freeze** — protect 1 day per week (1 freeze budget per week)
- Momentum glow on the pill scales with streak (max glow at 10-day streak)

---

## Share Card

Generate a 1080×1080 or 9:16 PNG card showing today's / this week's / streak stats and subject breakdown.
Three palettes: **Dark · Neon · Clean**. Export to Desktop or copy to clipboard.

---

## Spaced Repetition

Runs on every launch. SM-2 algorithm adapts intervals to your difficulty ratings.

| Avg difficulty | Intervals (days) |
|----------------|-----------------|
| Hard ⭐ (1–2) | 1 → 2 → 4 → 7 → 14 |
| Medium ⭐⭐⭐ (3) | 1 → 3 → 7 → 14 → 30 |
| Easy ⭐⭐⭐⭐⭐ (4–5) | 2 → 5 → 10 → 21 → 60 |

Overdue subjects fire a macOS notification at 10 AM.
Review status visible in **Subject Dashboard → Review tab**.

---

## Subject Dashboard

Click the colored avatar on any session row in the history.

**Tabs:** Overview · Sessions · Tasks · Review · Distractions

- **Review** — urgency card, recommended interval, Start Review Session button
- **Distractions** — filtered distraction analysis for that subject only

---

## Open on iPhone 📱

Click **"📱 Open on iPhone…"** in the menu bar to open a QR code window.

- **QR Code** generated natively — scan with your iPhone camera to open the dashboard instantly
- **URL display** with one-click copy button
- Local HTTP server on port **7788** — works with any device on the same WiFi network
- Add to Home Screen for an app-like experience

---

## Today Window

Daily summary: today's study time · sessions logged · tasks due today · imminent exam countdown.

Also available as the default **first tab** in the Analytics window.

---

## Modes

| Mode | Behaviour |
|------|-----------|
| 🎓 College | Subjects linked to credits, exam dates, semester name |
| 📚 Personal | Free-form subject entry, no credits or semester structure |

---

## Integrations

### Notion
1. [notion.so/my-integrations](https://www.notion.so/my-integrations) → create integration → copy token
2. Share your root Notion page with the integration
3. Paste token in app → **Connect**

Auto-created structure:
```
📚 StudyNotch (root)
├── Math
│   ├── 📋 Sessions  — Date · Duration · Difficulty · Distractions · Notes
│   └── 📝 Notes     — Text · Date · Telegram sent · Has image
└── Physics / ...
```

### Google Calendar
Google Cloud Console → enable Calendar API → OAuth credentials → connect in app (Brain tab → Calendar).

Pushes sessions as events, exams with 4 reminders. Today's events shown in the collapsed pill.

### Telegram
@BotFather → token → group with Topics enabled → bot as Admin → Detect Chat → Create Topics in app.

Quick notes (text + images) are sent to subject-specific topics via `sendPhoto` API.

### AI Coach (Groq — free)
[console.groq.com](https://console.groq.com) — no credit card, 14,400 req/day.
Model: `llama-3.3-70b-versatile`

Features: Smart Schedule · Weekly Report · Study Style Analysis · Course Analysis

### Local Web Dashboard
HTTP server runs on port **7788**. Open `http://[your-mac-ip]:7788` from any device on the same network to view stats in a browser. Use the QR code window for easy phone access.

---

## Quick Notes (from notch)

Hover notch → timer panel bottom:
- Type → **Save** → local + Notion
- **Send** → local + Notion + Telegram
- `⌘V` to paste image → preview → **Save/Send** via `sendPhoto`

---

## Permissions

| Permission | Feature | How to grant |
|-----------|---------|-------------|
| **Accessibility** | Window title reading · auto-detect | System Settings → Privacy & Security → Accessibility → ✅ StudyNotch |
| **Notifications** | Spaced repetition · exam alerts | Approve on first prompt |
| **Network** | AI · Notion · Telegram · Calendar · web dashboard | Automatic (sandboxing disabled) |
| **iCloud** (optional) | iCloud sync stub | Requires Xcode entitlement to activate |

---

## Data Storage

All data in `~/Library/Application Support/StudyNotch/`:

| File | Contents |
|------|----------|
| `sessions.json` | Study sessions (subject, times, duration, distractions, pauses, notes, RTF) |
| `subjects.json` | Known subjects list and suggestion rankings |
| `quick_notes.json` | Quick notes + optional image data |
| `gamification.json` | XP, achievements, weekly challenge |
| `gamification.backup.json` | Backup (loaded if primary is corrupted) |
| `subject_metas.json` | Subject metas (colors, Telegram IDs, exams, goals) |
| `tasks.json` | Study tasks |
| `streaks.json` | Streak data and freeze history |
| `mode.json` | Current mode (College / Personal) + semester info |
| `college.json` | College subjects with exam dates and credits |
| `courses.json` | Personal courses with progress tracking |
| `goals.json` | Daily/weekly goal settings |
| `weekly_plan.json` | Weekly subject plan allocations |
| `exams.json` | Exam schedule metadata |

Notch subject picker preferences are stored in UserDefaults:
- `notch.pinnedSubjects` — pinned items shown in the strip
- `notch.manualSubjects` — manually added custom notch subjects
- `notch.hiddenSubjects` — subjects hidden/deleted from notch picker

---

## File Map

| File | Purpose |
|------|---------|
| `main.swift` | App entry point |
| `AppDelegate.swift` | Menu bar, global shortcuts, launch tasks |
| `StudyTimer.swift` | Timer state machine, Pomodoro targets, session notes, `DistractionEvent`, `PauseInterval` |
| `NotchWindow.swift` | Notch pill UI, subject strip, dice, pin manager, Pomodoro presets, quick notes, LED/stress/momentum glow, calendar badge |
| `PhoneAccessView.swift` | QR code window for iPhone access via local web dashboard |
| `SessionStore.swift` | `StudySession` + `QuickNote` models, persistence, deduplication, subject management |
| `SessionEndView.swift` | Session save dialog, live Focus Score card, subject auto-selection, Notion push |
| `SessionReplayView.swift` | Timeline replay with animated playhead |
| `SessionEditSheet.swift` | Rich-text editor + difficulty for past sessions |
| `RichTextEditor.swift` | `NSTextView` wrapper: bold/italic/underline/color/highlight/image |
| `FocusScore.swift` | Scoring engine (0–100) + `FocusScoreCard` animated SwiftUI view |
| `StudySession+FocusScore.swift` | `focusScore`, `focusGrade`, `focusBreakdown`, `focusScoreCategory` on `StudySession` |
| `AutoSessionDetector.swift` | Activity detector + `AutoSessionSuggestionBanner` view |
| `AnalyticsView.swift` | 4-tab analytics shell (Today · Progress · Plan · Brain) |
| `ProgressTabView.swift` | Overview, sessions, insights, XP/achievements sections |
| `PlanTabView.swift` | Weekly plan, tasks, exams sections |
| `BrainTabView.swift` | AI Coach, Calendar, Notes sections |
| `StatsTabView.swift` | Animated stats dashboard |
| `DistractionAnalysis.swift` | Pattern analysis + tappable animated charts |
| `GamificationStore.swift` | XP, levels, achievements, `deductXP`, `xpForSession` |
| `GamificationView.swift` | XP tab — tappable level card + achievements |
| `XPDetailSheets.swift` | Level Ladder sheet, Achievement Detail sheet |
| `StreakStore.swift` | Streak tracking, freeze mechanic, 12-week grid |
| `SpacedRepetitionService.swift` | SM-2 algorithm, scheduling, macOS notifications |
| `SubjectStore.swift` | Colors, Telegram config, exams, goals, heatmap data |
| `SubjectSettingsView.swift` | Color picker, Telegram wizard, quick note field |
| `SubjectDashboardView.swift` | Per-subject window: Overview, Sessions, Tasks, Review, Distractions |
| `ModeStore.swift` | College / Personal mode, `CollegeSubject` model |
| `StudyPlanView.swift` | Heatmap, weekly goals, exams, tasks, notifications tabs |
| `TaskStore.swift` | `StudyTask` model, smart sort, XP on complete |
| `TodayView.swift` | Daily summary window (also embedded as first Analytics tab) |
| `ShareCardView.swift` | 1080×1080 / 9:16 PNG export card |
| `AIService.swift` | Groq API: Smart Schedule, Weekly Report, Study Style, Course Analysis |
| `AIChatView.swift` + `AIChatStore.swift` | Conversational AI chat |
| `AIPlanEditorView.swift` | AI-generated plan editing UI |
| `MarkdownText.swift` | Lightweight Markdown renderer for AI output |
| `NotionService.swift` | Notion API: auto-create pages, push sessions + notes |
| `NotionSetupView.swift` | 3-step Notion setup UI |
| `GoogleCalendarService.swift` | OAuth2, push sessions/exams, fetch today's events |
| `GoogleCalendarSetupView.swift` | Calendar connection UI |
| `CalendarDebugService.swift` | iCloud calendar access + debug view |
| `StageManagerDetector.swift` | Stage Manager detection for layout adjustments |
| `SoundService.swift` | Session start chime, milestone sounds, break reminders |
| `NotificationService.swift` | Local notification scheduling |
| `NtfyService.swift` | Ntfy push notification integration |
| `CloudSyncService.swift` | iCloud sync stub (needs Xcode entitlement) |
| `WebServer.swift` | Local HTTP dashboard on port 7788 |
| `DailyGoalRing.swift` | Animated daily progress ring component |
| `build.sh` | Build + bundle + sign + launch script |
| `Package.swift` | Swift Package Manager manifest |

---

## Troubleshooting

**`swift: command not found`**
```bash
xcode-select --install
```

**App launches but notch pill is invisible**
The pill anchors to the primary display's notch. On an external monitor it sits at the top-centre of the screen.

**Accessibility permission lost after rebuild**
`build.sh` always installs to `/Applications/StudyNotch.app`. If you moved the project, run `./build.sh` once — it auto-cleans the stale build cache.

**Auto-detect banner never appears**
1. `AutoSessionDetector.shared.isEnabled` is `true`
2. `start()` called from `applicationDidFinishLaunching` (not from `init()`)
3. Frontmost app's bundle ID is in one of the app lists
4. No session currently running
5. 10-minute cooldown has expired since last dismissal for that subject

**Focus Score is always 0**
Sessions under 60 seconds score 0 by design.

---

## What Changed in v12

StudyNotch v12 is a ground-up modernization, moving to the **Observation** framework and introducing immersive, data-driven features.

### 🏗 Architecture
- **@Observable Migration**: The entire app now uses the high-performance Observation framework, replacing `ObservableObject`.
- **macOS 13+**: Optimized for modern system APIs and snappier SwiftUI performance.

### 📊 Data & Insights
- **App Usage Tracking**: Sessions now track which apps you use (PDFs, IDEs, Browsers), visualized in the **Session End** and **Replay** views.
- **Smart Analytics**: Identifies your **Prime Time**, **Power Day**, and **Attention Needed** subjects.
- **Focus Score**: Interactive quality breakdown with live scoring on the finish screen.

### 🧠 Study Systems
- **Background Spaced Repetition**: Integrated **SM-2 algorithm** for automatic review scheduling and memory management.
- **Ambient Sound Player**: Loopable Lo-fi, Rain, Cafe, and Forest sounds in the notch pill.
- **Sound Themes**: 4 curated sound palettes (Classic, Modern, Zen, Muted).
- **Voice Control**: Start and finish sessions completely by voice ("Hey StudyNotch, start study").

### 🎨 Visual Delight
- **Study Forest**: A persistent 30-day "growth" view where your study hours grow a forest.
- **Constellation Map**: Connects your study sessions as stars in a subjects-based constellation.
- **Seasonal Themes**: UI dynamically adapts with icons and tints for Spring, Summer, Autumn, and Winter.

### ⚙️ Centralized Settings
- **Unified Hub**: All configs (Notion, Calendar, Notifications, Sounds, Voice) are now in a single **Settings** window (`⌘,`).

---

Made for Mahmoud — study hard, ship fast. 🚀
