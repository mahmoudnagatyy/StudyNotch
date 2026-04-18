import SwiftUI
import AppKit

// ── Session Edit Sheet ────────────────────────────────────────────────────────
//
//  Shown when user taps the ✏️ button on a history row.
//  Editable fields: difficulty (star rating) + notes (rich text with toolbar).
//  RTF data stored in session.notesRTF; plain text in session.notes.

struct SessionEditSheet: View {
    @Environment(\.dismiss) var dismiss
    let session: StudySession

    @State private var difficulty   : Int   = 0
    @State private var plainText    : String = ""
    @State private var rtfData      : Data?  = nil
    @State private var saved        = false

    // Reference to the underlying NSTextView for toolbar
    @State private var textViewRef  : NSTextView? = nil

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Session")
                        .font(.system(size: 16, weight: .bold))
                    Text(session.subject + " · " + fmtDur(session.duration))
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Difficulty ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Difficulty", systemImage: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 0) {
                            ForEach(1...5, id: \.self) { i in
                                Button { difficulty = i } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: i <= difficulty ? "star.fill" : "star")
                                            .font(.system(size: 22))
                                            .foregroundColor(i <= difficulty ? starColor(difficulty) : .secondary.opacity(0.3))
                                        if      i == 1 { Text("Hard").font(.system(size: 8)).foregroundColor(.secondary) }
                                        else if i == 3 { Text("OK")  .font(.system(size: 8)).foregroundColor(.secondary) }
                                        else if i == 5 { Text("Easy").font(.system(size: 8)).foregroundColor(.secondary) }
                                        else           { Text(" ")   .font(.system(size: 8)) }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // ── Rich Notes ────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Notes", systemImage: "note.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        // Formatting toolbar
                        RichTextToolbar { textViewRef }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))

                        // Rich text editor
                        RichTextEditorWrapper(
                            rtfData: $rtfData,
                            plainText: $plainText,
                            onTextViewReady: { tv in textViewRef = tv }
                        )
                        .frame(minHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(16)
            }

            Divider()

            // ── Save button ───────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Save Changes") { saveChanges() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(16)
        }
        .frame(width: 480, height: 540)
        .onAppear {
            difficulty = session.difficulty
            plainText  = session.notes
            rtfData    = session.notesRTF
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    func saveChanges() {
        var updated          = session
        updated.difficulty   = difficulty
        updated.notes        = plainText
        updated.notesRTF     = rtfData
        SessionStore.shared.update(updated)
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saved = false }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func starColor(_ d: Int) -> Color {
        [.red, .orange, .yellow, Color(red:0.6,green:0.9,blue:0.2), .green][max(0, d-1)]
    }
}

// ── Wrapper that exposes the inner NSTextView reference ───────────────────────

struct RichTextEditorWrapper: NSViewRepresentable {
    @Binding var rtfData  : Data?
    @Binding var plainText: String
    var onTextViewReady   : (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll   = NSScrollView()
        let textView = RichNSTextView()
        textView.delegate           = context.coordinator
        textView.isRichText         = true
        textView.allowsImageEditing = true
        textView.isEditable         = true
        textView.isSelectable       = true
        textView.allowsUndo         = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font               = .systemFont(ofSize: 12)
        textView.autoresizingMask   = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        scroll.documentView         = textView
        scroll.hasVerticalScroller  = true
        scroll.autohidesScrollers   = true
        scroll.borderType           = .noBorder
        scroll.drawsBackground      = false
        textView.drawsBackground    = false
        context.coordinator.textView = textView
        // Seed initial content
        if let data = rtfData,
           let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attr)
        } else if !plainText.isEmpty {
            textView.string = plainText
        }
        DispatchQueue.main.async { onTextViewReady(textView) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorWrapper
        weak var textView: NSTextView?
        init(_ p: RichTextEditorWrapper) { self.parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.plainText = tv.string
            let range = NSRange(location: 0, length: tv.textStorage?.length ?? 0)
            parent.rtfData = tv.textStorage?.rtf(from: range, documentAttributes: [:])
        }
    }
}
