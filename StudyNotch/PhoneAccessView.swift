import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// ── QR Code Phone Access View ────────────────────────────────────────────────
//
//  Replaces the old NSAlert-based URL display with a modern window
//  featuring a QR code for easy phone scanning.

struct PhoneAccessView: View {
    let url: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header gradient
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.1, blue: 0.15),
                             Color(red: 0.05, green: 0.05, blue: 0.08)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.cyan)
                        Text("Open on iPhone")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Scan the QR code with your iPhone camera")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.vertical, 16)
            }
            .frame(height: 80)

            Divider().overlay(Color.white.opacity(0.08))

            // QR Code
            VStack(spacing: 16) {
                if let qrImage = generateQRCode(from: url) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .cyan.opacity(0.2), radius: 12, y: 4)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 180, height: 180)
                        .overlay(
                            Text("QR unavailable")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                // URL display
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.6))

                    Text(url)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    withAnimation(.spring(response: 0.3)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(copied ? "Copied!" : "Copy URL")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(copied ? .green : .cyan)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(copied ? Color.green.opacity(0.1) : Color.cyan.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(copied ? Color.green.opacity(0.3) : Color.cyan.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                // Instructions
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi").font(.system(size: 9))
                        Text("Same WiFi network required")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.yellow.opacity(0.6))

                    Text("Add to Home Screen for an app-like experience")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.vertical, 20).padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 440)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    func generateQRCode(from string: String) -> NSImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale: CGFloat = 10
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────

class PhoneAccessWindowController: NSWindowController {
    static var shared: PhoneAccessWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        shared = PhoneAccessWindowController()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let url = WebServer.shared.localURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open on iPhone"
        window.center()
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PhoneAccessView(url: url))

        self.init(window: window)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window, queue: .main
        ) { _ in
            PhoneAccessWindowController.shared = nil
        }
    }
}
