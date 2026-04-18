import SwiftUI
import AppKit

// ── Gamification Tab ──────────────────────────────────────────────────────────

struct GamificationView: View {
    @Bindable var gStore = GamificationStore.shared
    @State private var selectedAchievement : Achievement? = nil
    @State private var showLevelDetail     = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                levelCard
                challengeCard
                achievementsSection
            }
            .padding(20)
        }
    }

    // ── Level card ────────────────────────────────────────────────────────────

    var levelCard: some View {
        let level  = gStore.currentLevel
        let next   = gStore.nextLevel
        let color  = levelColor(level.color)

        return VStack(spacing: 14) {
            HStack(alignment: .center) {
                // XP orb
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [color, color.opacity(0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    VStack(spacing: 1) {
                        Text("LV").font(.system(size: 10, weight: .black)).foregroundColor(.white.opacity(0.7))
                        Text("\(level.number)").font(.system(size: 22, weight: .black)).foregroundColor(.white)
                            .contentTransition(.numericText(value: Double(level.number)))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: level.number)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(color)
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11)).foregroundColor(.yellow)
                        Text("\(gStore.totalXP) XP")
                            .contentTransition(.numericText(value: Double(gStore.totalXP)))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gStore.totalXP)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        if let next {
                            Text("· \(gStore.xpToNext) to \(next.title)")
                                .contentTransition(.numericText(value: Double(gStore.xpToNext)))
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gStore.xpToNext)
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }

            // Progress bar
            if let next = next {
                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors:[color, color.opacity(0.7)],
                                                     startPoint:.leading, endPoint:.trailing))
                                .frame(width: geo.size.width * gStore.progressToNext, height: 12)
                        }
                    }
                    .frame(height: 12)
                    HStack {
                        Text("\(gStore.currentLevel.title)").font(.system(size: 10)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(next.title)").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            } else {
                Text("🏆 Maximum level reached!").font(.system(size: 13, weight: .semibold)).foregroundColor(.yellow)
            }
        }
        .padding(18)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.25), lineWidth: 1.5))
        .onTapGesture { showLevelDetail = true }
        .help("Tap to see level breakdown")
        .sheet(isPresented: $showLevelDetail) { LevelDetailSheet(gStore: gStore) }
    }

    // ── Weekly challenge ──────────────────────────────────────────────────────

    var challengeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered").foregroundColor(.orange)
                Text("Weekly Challenge").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("🔥 \(xpLabel(gStore.challenge?.xpReward ?? 0)) XP")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
            }

            if let c = gStore.challenge {
                HStack(spacing: 14) {
                    Text(c.icon.isEmpty ? "🎯" : "")
                    Image(systemName: c.icon).font(.system(size: 22)).foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title).font(.system(size: 14, weight: .semibold))
                        Text(c.description).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if c.completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24)).foregroundColor(.green)
                    } else {
                        Text("\(c.progress)/\(c.target)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(c.completed ? Color.green : Color.orange)
                            .frame(width: geo.size.width * min(Double(c.progress)/Double(max(c.target,1)), 1.0), height: 8)
                    }
                }.frame(height: 8)

                if c.completed {
                    Text("✅ Completed! +\(c.xpReward) XP earned").font(.system(size: 11, weight: .medium)).foregroundColor(.green)
                }
            } else {
                Text("No challenge this week yet").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // ── Achievements ──────────────────────────────────────────────────────────

    var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements").font(.system(size: 14, weight: .bold))
                Spacer()
                let unlocked = gStore.achievements.filter(\.isUnlocked).count
                Text("\(unlocked)/\(gStore.achievements.count)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }

            // Unlocked first, then locked
            let sorted = gStore.achievements.sorted {
                if $0.isUnlocked != $1.isUnlocked { return $0.isUnlocked }
                return ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(sorted) { a in
                    achievementCell(a)
                }
            }
        }
    }

    func achievementCell(_ a: Achievement) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(a.isUnlocked ? Color.yellow.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: a.icon)
                    .font(.system(size: 16))
                    .foregroundColor(a.isUnlocked ? .yellow : .secondary.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(a.isUnlocked ? .primary : .secondary)
                    .lineLimit(1)
                Text(a.isUnlocked ? "+\(a.xpReward) XP" : a.description)
                    .font(.system(size: 10))
                    .foregroundColor(a.isUnlocked ? .yellow : .secondary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if a.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.green)
            }
        }
        .padding(10)
        .background(a.isUnlocked
                    ? Color.yellow.opacity(0.06)
                    : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(a.isUnlocked ? Color.yellow.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1))
        .onTapGesture { selectedAchievement = a }
        .help(a.isUnlocked ? "Tap for details" : "Locked — " + a.description)
        .sheet(item: $selectedAchievement) { ach in AchievementDetailSheet(achievement: ach) }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func xpLabel(_ xp: Int) -> String { "+\(xp)" }

    func levelColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "green":  return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red":    return .red
        case "yellow": return .yellow
        case "pink":   return .pink
        default:       return .secondary
        }
    }
}

// ── Achievement unlock popup ──────────────────────────────────────────────────

struct AchievementToast: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.yellow.opacity(0.25)).frame(width: 44, height: 44)
                Image(systemName: achievement.icon)
                    .font(.system(size: 20)).foregroundColor(.yellow)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Achievement Unlocked! 🏆")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Text(achievement.title)
                    .font(.system(size: 14, weight: .bold))
                Text("+\(achievement.xpReward) XP")
                    .font(.system(size: 11)).foregroundColor(.yellow)
            }
            Spacer()
            Button { isShowing = false } label: {
                Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
