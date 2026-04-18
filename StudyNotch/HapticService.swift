import Foundation
import AppKit

enum HapticIntensity: String, Codable, CaseIterable, Identifiable {
    case light, medium, strong
    var id: String { rawValue }
    
    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .light:  return .alignment
        case .medium: return .levelChange
        case .strong: return .generic
        }
    }
}

final class HapticService {
    static let shared = HapticService()
    
    var hapticEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "hapticEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "hapticEnabled") }
    }
    
    var hapticIntensity: HapticIntensity {
        get {
            if let str = UserDefaults.standard.string(forKey: "hapticIntensity"),
               let intensity = HapticIntensity(rawValue: str) {
                return intensity
            }
            return .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "hapticIntensity")
        }
    }
    
    private init() {
        // Initialize default if needed
        if UserDefaults.standard.object(forKey: "hapticEnabled") == nil {
            hapticEnabled = true
        }
    }
    
    func playTimerStart() {
        play(pattern: .levelChange) // Slightly distinct
    }
    
    func playTimerPause() {
        play(pattern: .alignment) // Very light click
    }
    
    func playTimerComplete() {
        play(pattern: .generic) // Strong completion feeling
    }
    
    func playDistraction() {
        play(pattern: .levelChange)
    }
    
    private func play(pattern: NSHapticFeedbackManager.FeedbackPattern? = nil) {
        guard hapticEnabled else { return }
        let finalPattern = pattern ?? hapticIntensity.pattern
        NSHapticFeedbackManager.defaultPerformer.perform(finalPattern, performanceTime: .default)
    }
}
