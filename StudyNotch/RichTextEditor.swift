import SwiftUI
import AppKit

// ── Rich Text Editor ──────────────────────────────────────────────────────────
//
//  NSViewRepresentable wrapping NSTextView.
//  Supports: bold, italic, underline, text color, highlight, inline images.
//  Data stored as RTF Data (lossless, includes images).
//  Converts to/from plain String for backward compat with existing sessions.

struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data?          // primary storage (RTF)
    @Binding var plainText: String       // kept in sync for Notion/Telegram/search
    var placeholder: String = "Notes…"
    var minHeight: CGFloat  = 120

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll    = NSScrollView()
        let textView  = RichNSTextView()
        textView.delegate             = context.coordinator
        textView.isRichText           = true
        textView.allowsImageEditing   = true
        textView.isEditable           = true
        textView.isSelectable         = true
        textView.allowsUndo           = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset   = NSSize(width: 6, height: 8)
        textView.font                 = .systemFont(ofSize: 12)
        textView.autoresizingMask     = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false

        scroll.documentView           = textView
        scroll.hasVerticalScroller    = true
        scroll.autohidesScrollers     = true
        scroll.borderType             = .noBorder
        scroll.drawsBackground        = false
        textView.drawsBackground      = false
        context.coordinator.textView  = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? RichNSTextView else { return }
        // Only update if data changed externally (not from user typing)
        guard !context.coordinator.isEditing else { return }
        if let data = rtfData {
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                if tv.attributedString() != attr {
                    tv.textStorage?.setAttributedString(attr)
                }
            }
        } else if !plainText.isEmpty {
            // Seed from plain text if no RTF yet
            let attr = NSAttributedString(string: plainText,
                attributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.labelColor])
            tv.textStorage?.setAttributedString(attr)
        } else {
            // Show placeholder
            if tv.string.isEmpty {
                tv.string = ""
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent    : RichTextEditor
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) { isEditing = true }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Sync plain text
            parent.plainText = tv.string
            // Sync RTF data
            let range = NSRange(location: 0, length: tv.textStorage?.length ?? 0)
            parent.rtfData = tv.textStorage?.rtf(from: range, documentAttributes: [:])
        }

        func textDidEndEditing(_ notification: Notification) { isEditing = false }
    }
}

// Subclass to support drag-drop images
class RichNSTextView: NSTextView {
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // Allow image paste
        if pboard.canReadItem(withDataConformingToTypes: NSImage.imageTypes) {
            if let img = NSImage(pasteboard: pboard) {
                let attachment = NSTextAttachment()
                if let tiffData = img.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    let fileWrapper = FileWrapper(regularFileWithContents: pngData)
                    fileWrapper.preferredFilename = "image.png"
                    attachment.fileWrapper = fileWrapper
                }
                let attrStr = NSAttributedString(attachment: attachment)
                textStorage?.insert(attrStr, at: selectedRange().location)
                return true
            }
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let img = NSImage(pasteboard: sender.draggingPasteboard) {
            let attachment = NSTextAttachment()
            if let tiffData = img.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                let fileWrapper = FileWrapper(regularFileWithContents: pngData)
                fileWrapper.preferredFilename = "image.png"
                attachment.fileWrapper = fileWrapper
            }
            let attrStr = NSAttributedString(attachment: attachment)
            textStorage?.insert(attrStr, at: selectedRange().location)
            return true
        }
        return super.performDragOperation(sender)
    }
}

// ── Rich Text Toolbar ─────────────────────────────────────────────────────────
//
//  Shown above the RichTextEditor. Buttons apply formatting to selection.

struct RichTextToolbar: View {
    let textView: () -> NSTextView?

    @State private var showColorPicker = false
    @State private var selectedColor   = Color.white

    var body: some View {
        HStack(spacing: 2) {
            toolBtn("bold",    "Bold",   .boldFontMask)
            toolBtn("italic",  "Italic", .italicFontMask)
            underlineBtn
            Divider().frame(height: 16)
            // Text color
            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 20)
                .onChange(of: selectedColor) { c in applyColor(c) }
                .help("Text color")
            // Highlight
            Button { applyHighlight() } label: {
                Image(systemName: "highlighter")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Highlight")
            Divider().frame(height: 16)
            // Insert image
            Button { insertImage() } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Insert image")
            // Clear formatting
            Button { clearFormatting() } label: {
                Image(systemName: "textformat.slash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Clear formatting")
            Spacer()
            Text("⌘B · ⌘I · ⌘U")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    func toolBtn(_ icon: String, _ tip: String, _ trait: NSFontTraitMask) -> some View {
        Button {
            guard let tv = textView() else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let mgr = NSFontManager.shared
            guard let currentFont = tv.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let newFont = mgr.convert(currentFont, toHaveTrait: trait)
            tv.textStorage?.addAttribute(.font, value: newFont, range: range)
        } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help(tip)
    }

    var underlineBtn: some View {
        Button {
            guard let tv = textView() else { return }
            let range = tv.selectedRange()
            guard range.length > 0 else { return }
            let current = tv.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
            if current == NSUnderlineStyle.single.rawValue {
                tv.textStorage?.removeAttribute(.underlineStyle, range: range)
            } else {
                tv.textStorage?.addAttribute(.underlineStyle,
                    value: NSUnderlineStyle.single.rawValue, range: range)
            }
        } label: {
            Image(systemName: "underline").font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help("Underline")
    }

    func applyColor(_ color: Color) {
        guard let tv = textView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        tv.textStorage?.addAttribute(.foregroundColor, value: NSColor(color), range: range)
    }

    func applyHighlight() {
        guard let tv = textView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        // Cycle through highlight colors
        let colors: [NSColor] = [.systemYellow, .systemGreen, .systemPink, .clear]
        let current = tv.textStorage?.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
        let next = colors.first { $0 != current } ?? .systemYellow
        if next == .clear {
            tv.textStorage?.removeAttribute(.backgroundColor, range: range)
        } else {
            tv.textStorage?.addAttribute(.backgroundColor, value: next, range: range)
        }
    }

    func insertImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url),
           let tv  = textView() {
            let attachment = NSTextAttachment()
            if let tiffData = img.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                let fw = FileWrapper(regularFileWithContents: pngData)
                fw.preferredFilename = url.lastPathComponent
                attachment.fileWrapper = fw
            }
            let attrStr = NSAttributedString(attachment: attachment)
            tv.textStorage?.insert(attrStr, at: tv.selectedRange().location)
        }
    }

    func clearFormatting() {
        guard let tv = textView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0, let storage = tv.textStorage else { return }
        let plain = storage.attributedSubstring(from: range).string
        let clean = NSAttributedString(string: plain,
            attributes: [.font: NSFont.systemFont(ofSize: 12),
                         .foregroundColor: NSColor.labelColor])
        storage.replaceCharacters(in: range, with: clean)
    }
}
