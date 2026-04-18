# Implementation Plan: StudyNotch UX Improvements

**Feature**: `001-ux-improvements`  
**Spec**: [spec.md](./spec.md)  
**Created**: 2026-04-08  
**Status**: Ready for Tasks  

## Technical Context

- **Language**: Swift 5.9+
- **Framework**: SwiftUI + AppKit (hybrid menu bar app)
- **Target**: macOS 12.0+
- **Architecture**: Singleton services (AppDelegate, NotchWindowController, GoogleCalendarService, SessionStore)
- **Permissions**: EventKit (Calendar), no Accessibility APIs in use
- **Window Management**: NSPanel (notch), NSWindow (analytics/session end)

## Constitution Check

- ✅ No breaking changes to existing data persistence
- ✅ Changes are additive (new activation calls, removal of unnecessary prompts)
- ✅ Glassmorphism uses native macOS APIs (NSVisualEffectView) — no third-party dependencies

## Phase 0: Research

### research.md

**Decision**: Use `EKEventStore.authorizationStatus(for:)` to guard all Calendar prompt calls.  
**Rationale**: The API returns `.authorized`, `.denied`, `.restricted`, or `.notDetermined`. We only call `requestAccess` when status is `.notDetermined`.  
**Alternatives considered**: Removing EventKit entirely — rejected because native calendar events are displayed in the notch pill.

**Decision**: Remove all `AXIsProcessTrusted()` calls.  
**Rationale**: StudyNotch does not read or control other app windows; Accessibility permission adds no functionality and creates friction.  
**Alternatives considered**: Keeping the check but only showing it once — rejected to eliminate the prompt entirely.

**Decision**: Use `NSApp.activate(ignoringOtherApps: true)` + `.regular` activation policy for modal windows.  
**Rationale**: This is the standard macOS pattern for bringing a background helper app's window to the foreground. The activation policy must be `.regular` while the window is shown and reverted to `.accessory` on close.  
**Alternatives considered**: `window.orderFrontRegardless()` alone — rejected as it doesn't handle Stage Manager enrollment.

**Decision**: Consolidate 5 Analytics tabs into a single `ScrollView` with named sections.  
**Rationale**: Reduces tap count to zero for accessing any stat. Simpler to maintain as a single SwiftUI view.  
**Alternatives considered**: Keeping tabs but reducing from 5 to 2 — rejected as still adds friction.

**Decision**: Use `NSVisualEffectView` with `.hudWindow` or `.underWindowBackground` material wrapped in `NSViewRepresentable`.  
**Rationale**: Native macOS frosted glass that adapts to light/dark mode and renders correctly across displays.  
**Alternatives considered**: Custom blurred `UIImage` compositing — rejected as non-native and fragile.

## Phase 1: Design

### data-model.md

**PermissionState** (in-memory, not persisted)
- `calendarStatus: EKAuthorizationStatus` — reflects current EventKit state
- Checked once at app launch in `AppDelegate.applicationDidFinishLaunching`

**StudyWindow** (protocol)
- Any NSWindow that needs foreground promotion
- Required behavior: activate app, set policy to `.regular`, revert to `.accessory` on `windowWillClose`

**MenuItem** (conceptual)
- Top-level NSMenuItem in the status bar menu
- Constraint: maximum 6 items (enforced by removal of secondary toggles to Settings)

### contracts/

**Calendar Permission Contract**
- Input: App launch
- Output: Either silent continuation (if `.authorized`) or a single one-time system sheet (if `.notDetermined`)
- Never called if `.denied` or `.restricted`

**Window Activation Contract**
- Input: User taps Analytics or ends a session
- Output: Window is key, ordered front, app is active, visible in Stage Manager
- Cleanup: On `windowWillClose` → revert activation policy to `.accessory`

## Implementation Phases

### Phase A — Permission Fixes (P1)

1. Audit `AppDelegate.swift` for all `AXIsProcessTrusted()` calls → remove them
2. Audit `CalendarDebugService.swift` + `GoogleCalendarService.swift` for `requestAccess` calls → guard with `authorizationStatus` check
3. Add a single `checkCalendarPermission()` function called once in `applicationDidFinishLaunching`

### Phase B — Window Management (P1)

1. Create `StudyWindowActivator` helper that encapsulates:
   - `NSApp.setActivationPolicy(.regular)`
   - `NSApp.activate(ignoringOtherApps: true)`
   - `window.makeKeyAndOrderFront(nil)`
2. Call `StudyWindowActivator` from `SessionEndWindowController` and the Analytics button action
3. Ensure `windowWillClose` reverts to `.accessory` in both controllers

### Phase C — Menu Bar Cleanup (P2)

1. Count existing menu items in `AppDelegate.swift` `buildMenu()` or equivalent
2. Move secondary items (theme toggle, debug tools, iCloud sync toggle) into a proper `Settings` window (NSWindow with `⌘,` shortcut)
3. Ensure ≤ 6 top-level items remain

### Phase D — Unified Analytics Dashboard (P2)

1. Replace `TabView` in `AnalyticsView.swift` with a single `ScrollView`
2. Convert each tab's content into a named `Section` / `VStack` block with a header
3. Include: Today summary, Subject breakdown, Streak & gamification, Upcoming plan items
4. Add empty-state placeholder when no data exists

### Phase E — Glassmorphism (P3)

1. Create `GlassBackground: NSViewRepresentable` wrapping `NSVisualEffectView`
2. Apply to the expanded notch panel `NotchView` background
3. Apply to analytics and session end window backgrounds
4. Test on both notched MacBook and external monitor
