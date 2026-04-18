# Tasks: StudyNotch UX Improvements (001-ux-improvements)

**Total tasks**: 20  
**MVP scope**: Phase 3 (US1 + US2) — Permission fixes + Window management  

---

## Phase 1 — Setup

- [ ] T001 Read and verify existing permission request code in `StudyNotch/AppDelegate.swift`
- [ ] T002 Read and verify existing permission request code in `StudyNotch/CalendarDebugService.swift`
- [ ] T003 [P] Read `StudyNotch/SessionEndView.swift` window activation logic
- [ ] T004 [P] Read `StudyNotch/AnalyticsView.swift` tab structure

---

## Phase 2 — Foundational

- [ ] T005 Add `StudyWindowActivator` helper struct in `StudyNotch/AppDelegate.swift` that encapsulates activation policy toggling and `NSApp.activate(ignoringOtherApps: true)`

---

## Phase 3 — User Story 1: No Repeated Permission Prompts (P1)

- [ ] T006 [US1] Remove all `AXIsProcessTrusted()` calls from `StudyNotch/AppDelegate.swift`
- [ ] T007 [US1] Remove all `AXIsProcessTrusted()` calls from any other Swift files that import `ApplicationServices`
- [ ] T008 [US1] In `StudyNotch/AppDelegate.swift` `applicationDidFinishLaunching`, add a `checkCalendarPermission()` function that only calls `requestAccess` when `EKEventStore.authorizationStatus(for: .event) == .notDetermined`
- [ ] T009 [P] [US1] In `StudyNotch/CalendarDebugService.swift`, guard any `requestAccess` calls with an `authorizationStatus` check to avoid redundant prompts

---

## Phase 4 — User Story 2: Windows in Front + Stage Manager (P1)

- [ ] T010 [US2] In `StudyNotch/SessionEndView.swift`, call `StudyWindowActivator.activate(window:)` when the session end window is presented
- [ ] T011 [US2] In `StudyNotch/SessionEndView.swift` `windowWillClose`, revert `NSApp.setActivationPolicy(.accessory)`
- [ ] T012 [US2] Add an Analytics button action in `StudyNotch/NotchWindow.swift` that calls `StudyWindowActivator.activate(window:)` before presenting the analytics view as a standalone window
- [ ] T013 [US2] Verify `applicationShouldTerminateAfterLastWindowClosed` returns `false` in `StudyNotch/AppDelegate.swift`

---

## Phase 5 — User Story 3: Simplified Menu Bar + Unified Analytics (P2)

- [ ] T014 [US3] Audit `StudyNotch/AppDelegate.swift` menu construction — identify items exceeding the 6-item limit
- [ ] T015 [US3] Move secondary menu items (theme toggle, debug tools, iCloud sync) into `StudyNotch/SettingsView.swift` and hook it up as a `⌘,` Settings window
- [ ] T016 [US3] In `StudyNotch/AnalyticsView.swift`, replace `TabView` with a single `ScrollView` containing named `VStack` sections: Today, Subjects, Streak, Plan
- [ ] T017 [US3] Add an empty-state `Text` placeholder in each section when data is absent

---

## Phase 6 — User Story 4: Glassmorphism Polish (P3)

- [ ] T018 [US4] Create `GlassBackground.swift` in `StudyNotch/` — an `NSViewRepresentable` wrapping `NSVisualEffectView` with `.hudWindow` material
- [ ] T019 [US4] Apply `GlassBackground` as the background of the expanded notch panel in `StudyNotch/NotchWindow.swift` (replace flat `Color.black`)
- [ ] T020 [US4] Apply `GlassBackground` to the analytics window and session end window backgrounds

---

## Dependencies

```
T001-T004 (setup reads) → T005 (helper) → T006-T009 (US1) → T010-T013 (US2) → T014-T017 (US3) → T018-T020 (US4)
```

## Parallel Opportunities

- T003 and T004 can run in parallel with T001 and T002
- T006 and T007 can run in parallel
- T008 and T009 can run in parallel after T005
