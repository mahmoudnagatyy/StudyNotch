import SwiftUI

// ── Achievement Detail Sheet ──────────────────────────────────────────────────

struct AchievementDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 0) {
            // Close handle
            Capsule().fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4).padding(.top, 10)

            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(achievement.isUnlocked
                              ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 80, height: 80)
                    Image(systemName: achievement.icon)
                        .font(.system(size: 34))
                        .foregroundColor(achievement.isUnlocked ? .white : .secondary.opacity(0.5))
                }
                .shadow(color: achievement.isUnlocked ? .yellow.opacity(0.4) : .clear, radius: 16)

                VStack(spacing: 8) {
                    Text(achievement.title)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(achievement.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Status badge
                if achievement.isUnlocked {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                            Text("Unlocked").font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
                        }
                        if let date = achievement.unlockedAt {
                            Text(date.formatted(.dateTime.month(.wide).day().year()))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Text("+\(achievement.xpReward) XP earned")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    .padding(16)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                            .font(.system(size: 20))
                        Text("Not yet unlocked")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                        Text("Reward: +\(achievement.xpReward) XP")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .padding(24)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// ── Level Detail Sheet ────────────────────────────────────────────────────────

struct LevelDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    var gStore: GamificationStore

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4).padding(.top, 10)

            ScrollView {
                VStack(spacing: 20) {
                    // Current level hero
                    let level = gStore.currentLevel
                    let color = levelColor(level.color)

                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [color, color.opacity(0.5)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                        VStack(spacing: 1) {
                            Text("LV").font(.system(size: 11, weight: .black)).foregroundColor(.white.opacity(0.7))
                            Text("\(level.number)").font(.system(size: 26, weight: .black)).foregroundColor(.white)
                        }
                    }
                    .shadow(color: color.opacity(0.5), radius: 20)

                    VStack(spacing: 4) {
                        Text(level.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(color)
                        Text("\(gStore.totalXP) XP total")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // Progress to next
                    if let next = gStore.nextLevel {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Progress to \(next.title)")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(gStore.xpToNext) XP remaining")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.15)).frame(height: 16)
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [color, color.opacity(0.7)],
                                                             startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * gStore.progressToNext, height: 16)
                                    Text("\(Int(gStore.progressToNext * 100))%")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.leading, 6)
                                }
                            }.frame(height: 16)
                        }
                        .padding(14)
                        .background(color.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // All levels ladder
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Level Ladder").font(.system(size: 13, weight: .bold))
                        ForEach(gStore.allLevels, id: \.number) { lv in
                            HStack(spacing: 12) {
                                let lc = levelColor(lv.color)
                                let isCurrent = lv.number == level.number
                                let isPast    = lv.number < level.number

                                ZStack {
                                    Circle()
                                        .fill(isCurrent ? lc : isPast ? lc.opacity(0.3) : Color.secondary.opacity(0.1))
                                        .frame(width: 32, height: 32)
                                    if isPast {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(lc)
                                    } else {
                                        Text("\(lv.number)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(isCurrent ? .white : .secondary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lv.title)
                                        .font(.system(size: 12, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? lc : isPast ? .secondary : .secondary.opacity(0.6))
                                    Text("\(lv.minXP) XP")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }

                                Spacer()

                                if isCurrent {
                                    Text("YOU ARE HERE")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(lc)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(lc.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .padding(24)
            }
        }
        .frame(width: 360, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

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
