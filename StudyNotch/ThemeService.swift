import SwiftUI
import Observation

enum AppSeason: String, CaseIterable {
    case spring = "Spring"
    case summer = "Summer"
    case autumn = "Autumn"
    case winter = "Winter"
    case none   = "Default"
    
    var tint: Color {
        switch self {
        case .spring: return Color(red: 0.5, green: 0.9, blue: 0.6) // Cherry blossom/Fresh
        case .summer: return Color(red: 1.0, green: 0.8, blue: 0.2) // Sun
        case .autumn: return Color(red: 1.0, green: 0.5, blue: 0.2) // Maple
        case .winter: return Color(red: 0.6, green: 0.8, blue: 1.0) // Ice
        case .none:   return .blue
        }
    }
    
    var emoji: String {
        switch self {
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .autumn: return "🍂"
        case .winter: return "❄️"
        case .none:   return ""
        }
    }
}

@Observable
final class ThemeService {
    static let shared = ThemeService()
    
    var currentSeason: AppSeason = .none
    
    init() {
        updateSeasonAutomatically()
    }
    
    func updateSeasonAutomatically() {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3, 4, 5:    currentSeason = .spring
        case 6, 7, 8:    currentSeason = .summer
        case 9, 10, 11:  currentSeason = .autumn
        default:         currentSeason = .winter
        }
    }
    
    // User override in settings
    var userOverride: AppSeason? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "theme.seasonOverride"),
                  let s = AppSeason(rawValue: raw) else { return nil }
            return s
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: "theme.seasonOverride")
            if let v = newValue { currentSeason = v } else { updateSeasonAutomatically() }
        }
    }
}
