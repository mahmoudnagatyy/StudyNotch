// ══════════════════════════════════════════════════════════════════════════════
//  NotchWindow_AutoSuggestion_Patch.swift
//  StudyNotch — Integration Guide
//
//  Paste the marked snippets into NotchWindow.swift (or whichever file
//  contains the pill / notch content view).
//  This file itself does NOT need to be added to your Xcode target.
// ══════════════════════════════════════════════════════════════════════════════

/*
 ─────────────────────────────────────────────────────────────────────────────
 STEP 1 — Observe the detector at the top of your content struct
 ─────────────────────────────────────────────────────────────────────────────

     @ObservedObject private var detector = AutoSessionDetector.shared

 ─────────────────────────────────────────────────────────────────────────────
 STEP 2 — Overlay the banner below the pill
 ─────────────────────────────────────────────────────────────────────────────

     Wrap your pill's root VStack/ZStack in a ZStack, then add at the end:

     .overlay(alignment: .bottom) {
         if let suggestion = detector.suggestion {
             AutoSessionSuggestionBanner(
                 suggestion: suggestion,
                 onAccept : { detector.acceptSuggestion()  },
                 onDismiss: { detector.dismissSuggestion() },
                 onSnooze : { detector.snoozeSuggestion()  }   // NEW
             )
             .padding(.horizontal, 12)
             .offset(y: 80)   // adjust so it clears the pill bottom edge
             .transition(.move(edge: .top).combined(with: .opacity))
             .animation(.spring(response: 0.4, dampingFraction: 0.8),
                        value: detector.suggestion != nil)
             .zIndex(100)
         }
     }

 ─────────────────────────────────────────────────────────────────────────────
 STEP 3 — Start the detector from AppDelegate
 ─────────────────────────────────────────────────────────────────────────────

     In AppDelegate.applicationDidFinishLaunching(_:), add:

         if AutoSessionDetector.shared.isEnabled {
             AutoSessionDetector.shared.start()
         }

     ⚠️  Do NOT start the detector inside AutoSessionDetector.init() — other
         singletons (StudyTimer, SessionStore) may not be ready yet and the
         first poll would receive nil subjects.

 ─────────────────────────────────────────────────────────────────────────────
 STEP 4 — Settings toggle (recommended)
 ─────────────────────────────────────────────────────────────────────────────

     In your preferences / settings view:

     @ObservedObject private var detector = AutoSessionDetector.shared

     Toggle("Auto-detect study sessions", isOn: $detector.isEnabled)
         .toggleStyle(.switch)

     // Optional: let the user add custom folder names
     // (academicFolderPatterns is now a var, not a let)
     //
     // TextField("Add folder name…", text: $newPattern)
     //     .onSubmit {
     //         detector.academicFolderPatterns.append(newPattern.lowercased())
     //     }

 ─────────────────────────────────────────────────────────────────────────────
 STEP 5 — Add custom folder patterns at runtime (NEW)
 ─────────────────────────────────────────────────────────────────────────────

     `academicFolderPatterns` is now a `var` (was `let`), so you can mutate it
     from user settings without subclassing or hacking:

         AutoSessionDetector.shared.academicFolderPatterns.append("csen 401")
         AutoSessionDetector.shared.academicFolderPatterns.append("data structures")

 ─────────────────────────────────────────────────────────────────────────────
 SNOOZE BEHAVIOUR (NEW)
 ─────────────────────────────────────────────────────────────────────────────

     `detector.snoozeSuggestion(minutes: 5)` hides the banner and re-arms the
     cooldown so the same subject can be suggested again after 5 minutes.
     Pass a different value (e.g. `minutes: 10`) to your app's preference.
*/

import SwiftUI

// MARK: - Xcode Previews

struct AutoSessionSuggestionBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AutoSessionSuggestionBanner(
                suggestion: AutoSessionDetector.SessionSuggestion(
                    subject    : "Physics",
                    appName    : "Preview",
                    windowTitle: "Lecture 04 — Thermodynamics.pdf",
                    confidence : 0.90,
                    trigger    : .pdfOpened
                ),
                onAccept : {},
                onDismiss: {},
                onSnooze : {}
            )

            AutoSessionSuggestionBanner(
                suggestion: AutoSessionDetector.SessionSuggestion(
                    subject    : "Math",
                    appName    : "Finder",
                    windowTitle: "Second Term",
                    confidence : 0.92,
                    trigger    : .academicFolder
                ),
                onAccept : {},
                onDismiss: {}
                // onSnooze nil — hides the snooze button
            )
        }
        .padding()
        .frame(width: 380)
    }
}
