# Feature Specification: StudyNotch UX Improvements

**Feature Branch**: `001-ux-improvements`  
**Created**: 2026-04-08  
**Status**: Draft  

## User Scenarios & Testing *(mandatory)*

### User Story 1 - No Repeated Permission Prompts (Priority: P1)

As a user who has already granted Calendar and Accessibility permissions, I should not be asked for them again every time the app launches. The app should remember that I already approved these and proceed silently.

**Why this priority**: This is the most disruptive daily friction point. Being bombarded with system dialogs on every launch degrades trust and makes the app feel broken.

**Independent Test**: Launch the app 3 times in a row after having granted permissions once. No system permission dialog should appear on the 2nd or 3rd launch.

**Acceptance Scenarios**:

1. **Given** Calendar permission was already granted, **When** the app launches, **Then** no Calendar authorization dialog appears.
2. **Given** Accessibility permission was already granted, **When** the app launches, **Then** no Accessibility permission dialog appears.
3. **Given** the app does not use Accessibility APIs at all, **When** the app launches, **Then** it never requests Accessibility permission in the first place.

---

### User Story 2 - Windows Appear in Front and in Stage Manager (Priority: P1)

When I click the Analytics or Session End button from the Notch pill, the window should immediately appear in focus, on top of all other apps, and be visible in macOS Stage Manager so I can switch back to it like any other app.

**Why this priority**: A study tool window appearing hidden behind other apps makes it essentially invisible. Users may think the action failed and click again, causing confusion.

**Independent Test**: While Safari is open and focused, start a study session, end it, and click "Save". The session end window must appear on top of Safari immediately.

**Acceptance Scenarios**:

1. **Given** another app is full-screen, **When** I click Analytics from the notch, **Then** the analytics window appears on top and becomes active.
2. **Given** Stage Manager is enabled, **When** the session end dialog appears, **Then** it is visible as a separate card in Stage Manager.
3. **Given** the analytics window is open, **When** I switch to it from Stage Manager, **Then** it comes to the foreground correctly.

---

### User Story 3 - Simplified Menu Bar and Consolidated Analytics (Priority: P2)

The menu bar should have fewer items, and the Analytics view should consolidate its 5 tabs into a unified scrollable dashboard so the UI feels clean and focused rather than cluttered.

**Why this priority**: Clutter in the interface increases cognitive load and makes the app harder to use during study sessions when focus is critical.

**Independent Test**: Open the menu bar and count items — should be ≤ 6 top-level actions. Open Analytics and see a single scrollable dashboard rather than 5 tab buttons.

**Acceptance Scenarios**:

1. **Given** the menu bar is open, **When** I count the items, **Then** there are 6 or fewer top-level menu items.
2. **Given** Analytics is open, **When** I view the panel, **Then** today's stats, subjects, and streaks are visible in one scrollable view without tab-switching.
3. **Given** Study Plan data exists, **When** I open Analytics, **Then** subject totals and plan info are visible in the same unified view.

---

### User Story 4 - Glassmorphism Visual Polish (Priority: P3)

The expanded notch panel and analytics/session windows should have a frosted glass appearance consistent with macOS design language, making the app feel premium and native.

**Why this priority**: Visual polish increases perceived quality. The app is already feature-rich; a premium look matches the ambition of a study productivity tool.

**Independent Test**: Expand the notch panel over a colorful background. The panel background should show a blurred, frosted version of whatever is behind it rather than a flat black.

**Acceptance Scenarios**:

1. **Given** the notch panel is expanded, **When** placed over a colourful desktop, **Then** the background shows a semi-transparent frosted blur.
2. **Given** the analytics or session window is open, **When** the user moves it over different backgrounds, **Then** it maintains its glass-like frosted appearance.

---

### Edge Cases

- What happens if the user revokes Calendar permission after launch — does the app crash or degrade gracefully?
- What if Stage Manager is disabled — does the window still come to front correctly?
- What if the user has multiple monitors — does glassmorphism render correctly across displays?
- What if the analytics dashboard has no data yet — does it show an appropriate empty state?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST check Calendar authorization status silently on launch and only prompt if status is `.notDetermined` (never if already `.authorized` or `.denied`).
- **FR-002**: The app MUST NOT request Accessibility permissions unless it uses Accessibility APIs; all `AXIsProcessTrusted` checks must be removed if unused.
- **FR-003**: The app MUST call `NSApp.activate(ignoringOtherApps: true)` when presenting the session end window and analytics window to bring them to front.
- **FR-004**: The session end window and analytics window MUST be enrolled with `.regular` activation policy while visible so they appear in Stage Manager and the Dock.
- **FR-005**: The menu bar MUST contain no more than 6 top-level clickable items; secondary options must move to Settings (⌘,) window.
- **FR-006**: The Analytics panel MUST present today's study time, subject breakdown, streak, and upcoming plan items in a single scrollable view without tabbed navigation.
- **FR-007**: The expanded notch panel background MUST use an `NSVisualEffectView` material for frosted glass rendering.
- **FR-008**: If Calendar access is denied by the user, the app MUST show a subtle inline notice rather than a blocking system dialog.

### Key Entities

- **Permission State**: Represents the current authorization status (notDetermined, authorized, denied) for Calendar and Accessibility — checked once at launch and cached for the session.
- **Study Window**: Any NSWindow subclass presenting study-related UI (analytics, session end) that requires foreground activation.
- **Menu Bar Item**: A top-level clickable action or toggle in the app's NSStatusItem menu — must be limited to 6.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After initial permission grant, the app launches without any permission dialog 100% of the time on subsequent launches.
- **SC-002**: Clicking Analytics or Session End while another app is focused brings the StudyNotch window to front within 200ms.
- **SC-003**: The menu bar drop-down contains 6 or fewer top-level actions (verifiable by counting).
- **SC-004**: Analytics view displays all key metrics (time today, subjects, streak) without requiring any tab-switch — reachable by scrolling only.
- **SC-005**: On a notched MacBook, the expanded notch panel has a visually distinct frosted-glass background (verifiable against a colorful wallpaper).

## Assumptions

- The app is distributed as a direct `.app` bundle (not via Mac App Store), so ad-hoc entitlements and local permissions apply.
- Accessibility APIs (like reading window titles of other apps) are not actually used by StudyNotch — only calendar event reading is needed.
- The user's macOS version is 12.0 or later (required for `NSVisualEffectView` materials and Stage Manager compatibility).
- `GoogleCalendarService` handles its own OAuth token refresh independently; the permission improvement only concerns EventKit (native Calendar) prompts.
- Moving settings into a dedicated Settings window (⌘,) is in scope for decluttering the menu bar.
