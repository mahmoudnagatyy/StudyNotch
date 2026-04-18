// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StudyNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StudyNotch",
            path: "StudyNotch",
            exclude: ["Info.plist", "StudyNotch.entitlements", "AppIcon.icns"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CloudKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Network"),
                .linkedFramework("EventKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SpriteKit"),
            ]
        )
    ]
)
