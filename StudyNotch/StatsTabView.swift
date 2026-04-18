import SwiftUI
import Charts

// ── Stats Tab — fully interactive ────────────────────────────────────────────

struct StatsTabView: View {
    var store    = SessionStore.shared
    @Bindable var subStore = SubjectStore.shared
    @State private var animateCards  = false
    @State private var animateRing   = false
    @State private var animateBars   = false

    // Drill-down state
    @State private var drillCard     : String? = nil   // which stat card is expanded
    @State private var drillSubject  : String? = nil   // which leaderboard row is expanded
    @State private var weeklyGoal    : Double  = 20    // hours — tappable
    @State private var editingGoal   = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                topSubjectHero
                    .offset(y: animateCards ? 0 : 30)
                    .opacity(animateCards ? 1 : 0)

                // 2-col stat grid — every card is tappable
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    interactiveStatCard("Total Time",      totalTimeStr,           "clock.fill",            .blue,   "total_time",  delay: 0.05)
                    interactiveStatCard("Sessions",        "\(store.sessions.count)", "checkmark.circle.fill", .green, "sessions",   delay: 0.10)
                    interactiveStatCard("Current Streak",  "\(streak) days",        "flame.fill",            .red,    "streak",     delay: 0.15)
                    interactiveStatCard("Avg Session",     avgSession,              "timer",                 .orange, "avg",        delay: 0.20)
                    interactiveStatCard("Best Day",        bestDayStr,              "trophy.fill",           Color(red:1,green:0.8,blue:0), "best_day", delay: 0.25)
                    interactiveStatCard("This Week",       thisWeekStr,             "calendar.badge.clock",  .teal,   "this_week",  delay: 0.30)
                    interactiveStatCard("Subjects",        "\(store.subjectTotals.count)", "number.circle.fill", .purple, "subjects", delay: 0.35)
                    interactiveStatCard("Hardest",         hardestSubject,          "brain.head.profile",    .pink,   "hardest",    delay: 0.40)
                }

                // Drill-down panel — shown when a card is tapped
                if let card = drillCard {
                    drillDownPanel(for: card)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                subjectLeaderboard
                    .offset(y: animateCards ? 0 : 20)
                    .opacity(animateCards ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45), value: animateCards)

                weeklyRing
                    .offset(y: animateCards ? 0 : 20)
                    .opacity(animateCards ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: animateCards)

                personalBests
                    .offset(y: animateCards ? 0 : 20)
                    .opacity(animateCards ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.65), value: animateCards)
            }
            .padding(20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { animateCards = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 1.2)) { animateRing = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.9)) { animateBars = true }
            }
            weeklyGoal = UserDefaults.standard.double(forKey: "stats_weekly_goal").nonZero ?? 20
        }
    }

    // ── Top Subject Hero ──────────────────────────────────────────────────────

    var topSubjectHero: some View {
        let top   = store.subjectTotals.first
        let color = top.map { subStore.color(for: $0.subject) } ?? .blue
        return ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.3), lineWidth: 1))
                .shadow(color: color.opacity(animateCards ? 0.4 : 0), radius: animateCards ? 16 : 4)

            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(color.opacity(0.2)).frame(width: 52, height: 52)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22)).foregroundColor(color)
                        .scaleEffect(animateCards ? 1.0 : 0.3)
                        .rotationEffect(.degrees(animateCards ? 0 : -30))
                        .animation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.2), value: animateCards)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP SUBJECT")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(color.opacity(0.7)).tracking(1.5)
                    if let t = top {
                        Text(t.subject)
                            .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Text(fmtDur(t.total) + " total · \(subjectSessionCount(t.subject)) sessions")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                    } else {
                        Text("No sessions yet").font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
                if let t = top {
                    let total = store.sessions.reduce(0.0) { $0 + $1.duration }
                    let pct   = total > 0 ? Int(t.total / total * 100) : 0
                    ZStack {
                        Circle().stroke(color.opacity(0.15), lineWidth: 4).frame(width: 52, height: 52)
                        Circle()
                            .trim(from: 0, to: animateRing ? CGFloat(pct) / 100 : 0)
                            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 52, height: 52).rotationEffect(.degrees(-90))
                        Text("\(pct)%").font(.system(size: 11, weight: .bold)).foregroundColor(color)
                    }
                }
            }
            .padding(18)
        }
    }

    // ── Interactive stat card — tap to expand ─────────────────────────────────

    func interactiveStatCard(_ title: String, _ value: String, _ icon: String,
                              _ color: Color, _ key: String, delay: Double) -> some View {
        let isOpen = drillCard == key
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                drillCard = isOpen ? nil : key
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14)).foregroundColor(color)
                        .scaleEffect(animateCards ? 1.0 : 0.1)
                        .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(delay + 0.1), value: animateCards)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(color.opacity(0.5))
                }
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                    .opacity(animateCards ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(delay + 0.15), value: animateCards)
                Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(14)
            .background(isOpen ? color.opacity(0.16) : color.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isOpen ? color.opacity(0.4) : color.opacity(0.12), lineWidth: isOpen ? 1 : 0.5))
            .offset(y: animateCards ? 0 : 18)
            .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(delay), value: animateCards)
        }
        .buttonStyle(.plain)
        .help("Tap for details")
    }

    // ── Drill-down panel for each card ────────────────────────────────────────

    @ViewBuilder
    func drillDownPanel(for key: String) -> some View {
        switch key {
        case "total_time":
            statDrillCard("Total Study Time", color: .blue) {
                VStack(spacing: 8) {
                    let monthlyData = last30DaysByWeek()
                    ForEach(monthlyData, id: \.label) { entry in
                        HStack(spacing: 10) {
                            Text(entry.label).font(.system(size: 11)).foregroundColor(.secondary).frame(width: 52, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.blue.opacity(0.1)).frame(height: 7)
                                    let w = monthlyData.map(\.hours).max() ?? 1
                                    Capsule().fill(Color.blue).frame(width: g.size.width * CGFloat(entry.hours / w), height: 7)
                                }
                            }
                            .frame(height: 7)
                            Text(String(format: "%.1fh", entry.hours))
                                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }

        case "sessions":
            statDrillCard("Recent Sessions", color: .green) {
                VStack(spacing: 6) {
                    ForEach(store.sessions.prefix(6)) { s in
                        HStack(spacing: 8) {
                            Circle().fill(subStore.color(for: s.subject)).frame(width: 7, height: 7)
                            Text(s.subject).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(fmtDur(s.duration)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            Text(s.date, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }

        case "streak":
            statDrillCard("Streak Details", color: .red) {
                VStack(spacing: 10) {
                    streakCalendar
                    HStack {
                        statMiniRow("Current",  "\(streak) days",          .red)
                        Spacer()
                        statMiniRow("Best Ever", "\(longestEverStreak) days", .orange)
                        Spacer()
                        statMiniRow("This Month", "\(sessionsThisMonth) sessions", .pink)
                    }
                }
            }

        case "avg":
            statDrillCard("Session Breakdown", color: .orange) {
                let data = sessionLengthBuckets()
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(data, id: \.label) { b in
                        VStack(spacing: 4) {
                            Text("\(b.count)").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.6 + Double(b.count) / Double(data.map(\.count).max() ?? 1) * 0.4))
                                .frame(height: max(6, CGFloat(b.count) / CGFloat(data.map(\.count).max() ?? 1) * 50))
                            Text(b.label).font(.system(size: 8)).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 72)
            }

        case "best_day":
            statDrillCard("Top Days", color: Color(red:1,green:0.8,blue:0)) {
                let topDays = topStudyDays(limit: 5)
                VStack(spacing: 6) {
                    ForEach(Array(topDays.enumerated()), id: \.offset) { idx, day in
                        HStack(spacing: 10) {
                            Text(["🥇","🥈","🥉","4th","5th"][idx]).font(.system(size: 12))
                            Text(day.label).font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer()
                            Text(fmtDur(day.total)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text("·  \(day.count) sessions").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
            }

        case "this_week":
            statDrillCard("This Week By Day", color: .teal) {
                let daily = thisWeekDaily()
                let maxH  = daily.map(\.hours).max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(daily, id: \.day) { item in
                        VStack(spacing: 4) {
                            if item.hours > 0 {
                                Text(String(format: "%.1f", item.hours))
                                    .font(.system(size: 8, weight: .bold)).foregroundColor(.teal)
                            }
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.isToday ? Color.teal : Color.teal.opacity(0.45))
                                .frame(height: max(4, CGFloat(item.hours / maxH) * 56))
                            Text(item.day).font(.system(size: 9)).foregroundColor(item.isToday ? .teal : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 76)
            }

        case "subjects":
            statDrillCard("All Subjects", color: .purple) {
                VStack(spacing: 6) {
                    ForEach(store.subjectTotals, id: \.subject) { item in
                        HStack(spacing: 8) {
                            Circle().fill(subStore.color(for: item.subject)).frame(width: 7, height: 7)
                            Text(item.subject).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(fmtDur(item.total)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            Text("·  \(subjectSessionCount(item.subject)) sessions")
                                .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }

        case "hardest":
            statDrillCard("Difficulty Rankings", color: .pink) {
                VStack(spacing: 6) {
                    ForEach(difficultyRanking(), id: \.subject) { item in
                        HStack(spacing: 8) {
                            Circle().fill(subStore.color(for: item.subject)).frame(width: 7, height: 7)
                            Text(item.subject).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { i in
                                    Image(systemName: i < Int(item.avg.rounded()) ? "star.fill" : "star")
                                        .font(.system(size: 8))
                                        .foregroundColor(i < Int(item.avg.rounded()) ? .pink : .secondary.opacity(0.3))
                                }
                            }
                            Text(String(format: "%.1f", item.avg)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        }
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    // Reusable drill-down card wrapper
    func statDrillCard<Content: View>(_ title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drillCard = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            content()
        }
        .padding(14)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // ── Streak mini calendar (last 14 days grid) ──────────────────────────────

    var streakCalendar: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<14).reversed().map { cal.date(byAdding: .day, value: -$0, to: Date())! }
        let fmt = DateFormatter(); fmt.dateFormat = "d"
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let hadSession = store.sessions.contains { cal.isDate($0.date, inSameDayAs: d) }
                let isToday    = cal.isDateInToday(d)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hadSession ? Color.red : Color.white.opacity(0.06))
                        .frame(width: 20, height: 20)
                        .overlay(isToday ? RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.5), lineWidth: 1.5) : nil)
                    Text(fmt.string(from: d)).font(.system(size: 7)).foregroundColor(.secondary)
                }
            }
        }
    }

    // ── Subject Leaderboard — tappable rows ───────────────────────────────────

    var subjectLeaderboard: some View {
        let totals = store.subjectTotals.prefix(8)
        let maxVal = totals.first?.total ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.number").foregroundColor(.purple).font(.system(size: 13))
                Text("Subject Leaderboard").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.subjectTotals.count) subjects").font(.system(size: 10)).foregroundColor(.secondary)
            }
            ForEach(Array(totals.enumerated()), id: \.offset) { idx, item in
                let isExpanded = drillSubject == item.subject
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            drillSubject = isExpanded ? nil : item.subject
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(rankColor(idx).opacity(0.15)).frame(width: 26, height: 26)
                                Text(idx == 0 ? "👑" : "\(idx + 1)")
                                    .font(.system(size: idx == 0 ? 13 : 10, weight: .bold))
                                    .foregroundColor(rankColor(idx))
                            }
                            Circle().fill(subStore.color(for: item.subject)).frame(width: 8, height: 8)
                            Text(item.subject)
                                .font(.system(size: 12, weight: idx == 0 ? .semibold : .regular))
                                .foregroundColor(isExpanded ? .white : .white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(subStore.color(for: item.subject).opacity(0.8))
                                        .frame(width: animateBars ? geo.size.width * CGFloat(item.total / maxVal) : 0, height: 6)
                                        .animation(.easeOut(duration: 0.8).delay(Double(idx) * 0.1), value: animateBars)
                                }
                            }
                            .frame(width: 80, height: 6)
                            Text(fmtDur(item.total))
                                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).frame(width: 44, alignment: .trailing)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8)).foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)

                    // Expanded detail for this subject
                    if isExpanded {
                        let subSessions = store.sessions.filter { $0.subject == item.subject }
                        VStack(alignment: .leading, spacing: 8) {
                            Divider().padding(.top, 8)
                            HStack(spacing: 16) {
                                statMiniRow("Sessions",  "\(subSessions.count)",       subStore.color(for: item.subject))
                                statMiniRow("Avg length", avgLen(subSessions),         .secondary)
                                statMiniRow("Avg diff",   avgDiffStr(subSessions),      .secondary)
                            }
                            let recent = subSessions.prefix(3)
                            if !recent.isEmpty {
                                Text("Recent").font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                                ForEach(recent) { s in
                                    HStack(spacing: 6) {
                                        Text(s.date, format: .dateTime.month(.abbreviated).day())
                                            .font(.system(size: 10)).foregroundColor(.secondary)
                                        Text(fmtDur(s.duration)).font(.system(size: 10, design: .monospaced))
                                        Spacer()
                                        if s.difficulty > 0 {
                                            HStack(spacing: 1) {
                                                ForEach(0..<s.difficulty, id: \.self) { _ in
                                                    Image(systemName: "star.fill").font(.system(size: 7)).foregroundColor(.yellow)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4).padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isExpanded ? subStore.color(for: item.subject).opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color.purple.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.12), lineWidth: 0.5))
    }

    // ── Weekly ring — tap to edit goal ────────────────────────────────────────

    var weeklyRing: some View {
        let goal   = weeklyGoal * 3600
        let actual = thisWeekSeconds
        let pct    = min(actual / goal, 1.0)
        let color: Color = pct >= 1 ? .green : pct >= 0.6 ? .blue : .orange
        return HStack(spacing: 20) {
            ZStack {
                Circle().stroke(color.opacity(0.1), lineWidth: 10).frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: animateRing ? CGFloat(pct) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90).rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(Int(pct * 100))%").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(color)
                    Text("of goal").font(.system(size: 8)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Progress").font(.system(size: 13, weight: .semibold))
                statRow("This week", thisWeekStr, .blue)
                statRow("Remaining", fmtDur(max(0, goal - actual)), .orange)

                // Tappable goal row
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editingGoal.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Goal:").font(.system(size: 11)).foregroundColor(.secondary)
                        Text(fmtDur(goal)).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                        Image(systemName: editingGoal ? "pencil.circle.fill" : "pencil.circle")
                            .font(.system(size: 10)).foregroundColor(color.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                if editingGoal {
                    HStack(spacing: 6) {
                        Button { weeklyGoal = max(1, weeklyGoal - 1); saveGoal() }
                        label: { Image(systemName: "minus.circle").font(.system(size: 14)).foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                        Text("\(Int(weeklyGoal))h / wk")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(color)
                        Button { weeklyGoal = min(80, weeklyGoal + 1); saveGoal() }
                        label: { Image(systemName: "plus.circle").font(.system(size: 14)).foregroundColor(color) }
                        .buttonStyle(.plain)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    func saveGoal() {
        UserDefaults.standard.set(weeklyGoal, forKey: "stats_weekly_goal")
    }

    // ── Personal bests — tappable ─────────────────────────────────────────────

    var personalBests: some View {
        let longest    = store.sessions.max(by: { $0.duration < $1.duration })
        let bestStreak = longestEverStreak
        let mostInDay  = mostSessionsInDay
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "medal.fill").foregroundColor(.yellow).font(.system(size: 13))
                Text("Personal Bests").font(.system(size: 13, weight: .semibold))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                interactiveBestCard(
                    "Longest Session",
                    longest.map { fmtDur($0.duration) } ?? "—",
                    longest?.subject ?? "",
                    longest.map { "\($0.date.formatted(.dateTime.month(.abbreviated).day()))" } ?? "",
                    "stopwatch.fill", .blue
                )
                interactiveBestCard(
                    "Best Streak",
                    "\(bestStreak) days",
                    "",
                    bestStreakDates(),
                    "flame.fill", .red
                )
                interactiveBestCard(
                    "Sessions in a Day",
                    "\(mostInDay)",
                    "",
                    bestDayForSessions(),
                    "bolt.fill", .yellow
                )
            }
        }
        .padding(16)
        .background(Color.yellow.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.1), lineWidth: 0.5))
    }

    func interactiveBestCard(_ title: String, _ value: String, _ sub: String,
                              _ detail: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundColor(color)
                .scaleEffect(animateCards ? 1.0 : 0.2)
                .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.7), value: animateCards)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(title).font(.system(size: 9)).foregroundColor(.secondary).multilineTextAlignment(.center)
            if !sub.isEmpty { Text(sub).font(.system(size: 8)).foregroundColor(color.opacity(0.7)).lineLimit(1) }
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8)).foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 0.5))
    }

    // ── Helper views ──────────────────────────────────────────────────────────

    func statRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundColor(color == .secondary ? .secondary : color)
        }
    }

    func statMiniRow(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(color == .secondary ? .primary : color)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    // ── Computed properties ───────────────────────────────────────────────────

    var totalTimeStr: String { fmtDur(store.sessions.reduce(0) { $0 + $1.duration }) }

    var thisWeekSeconds: Double {
        let cal   = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return store.sessions.filter { $0.startTime >= start }.reduce(0) { $0 + $1.duration }
    }
    var thisWeekStr: String { fmtDur(thisWeekSeconds) }

    var avgSession: String {
        guard !store.sessions.isEmpty else { return "—" }
        return fmtDur(store.sessions.reduce(0){$0+$1.duration} / Double(store.sessions.count))
    }

    var streak: Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while store.sessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var longestEverStreak: Int {
        let cal  = Calendar.current
        let days = Set(store.sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0; var cur = 0; var prev: Date? = nil
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { cur += 1 } else { cur = 1 }
            best = max(best, cur); prev = d
        }
        return best
    }

    var sessionsThisMonth: Int {
        let cal = Calendar.current
        return store.sessions.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
    }

    var bestDayStr: String {
        let cal     = Calendar.current
        let grouped = Dictionary(grouping: store.sessions) { cal.startOfDay(for: $0.date) }
        let best    = grouped.max { a, b in a.value.reduce(0){$0+$1.duration} < b.value.reduce(0){$0+$1.duration} }
        guard let b = best else { return "—" }
        let fmt = DateFormatter(); fmt.dateFormat = "EEE d MMM"
        return fmtDur(b.value.reduce(0){$0+$1.duration}) + " · " + fmt.string(from: b.key)
    }

    var hardestSubject: String {
        let totals = store.subjectTotals
        guard !totals.isEmpty else { return "—" }
        let avgDiffs = totals.map { item -> (String, Double) in
            let subs = store.sessions.filter { $0.subject == item.subject && $0.difficulty > 0 }
            guard !subs.isEmpty else { return (item.subject, 3.0) }
            return (item.subject, Double(subs.map { $0.difficulty }.reduce(0,+)) / Double(subs.count))
        }
        return avgDiffs.min(by: { $0.1 < $1.1 })?.0 ?? "—"
    }

    var mostSessionsInDay: Int {
        let cal     = Calendar.current
        let grouped = Dictionary(grouping: store.sessions) { cal.startOfDay(for: $0.date) }
        return grouped.values.map { $0.count }.max() ?? 0
    }

    func subjectSessionCount(_ subject: String) -> Int { store.sessions.filter { $0.subject == subject }.count }
    func rankColor(_ i: Int) -> Color { [Color(red:1,green:0.8,blue:0), .white.opacity(0.6), Color(red:0.8,green:0.5,blue:0.3)][min(i,2)] }
    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func avgLen(_ sessions: [StudySession]) -> String {
        guard !sessions.isEmpty else { return "—" }
        return fmtDur(sessions.reduce(0){$0+$1.duration} / Double(sessions.count))
    }

    func avgDiffStr(_ sessions: [StudySession]) -> String {
        let rated = sessions.filter { $0.difficulty > 0 }
        guard !rated.isEmpty else { return "—" }
        let avg = Double(rated.map(\.difficulty).reduce(0,+)) / Double(rated.count)
        return String(format: "%.1f★", avg)
    }

    // ── Data helpers ──────────────────────────────────────────────────────────

    func last30DaysByWeek() -> [(label: String, hours: Double)] {
        let cal = Calendar.current
        return (0..<4).reversed().map { week -> (String, Double) in
            let start = cal.date(byAdding: .weekOfYear, value: -week, to: Date())!
            let end   = cal.date(byAdding: .day, value: 7, to: start)!
            let hrs   = store.sessions.filter { $0.date >= start && $0.date < end }.reduce(0.0) { $0 + $1.duration / 3600 }
            let fmt   = DateFormatter(); fmt.dateFormat = "d MMM"
            return ("Wk \(fmt.string(from: start))", hrs)
        }
    }

    func sessionLengthBuckets() -> [(label: String, count: Int)] {
        let buckets: [(String, ClosedRange<Double>)] = [
            ("<15m", 0...900), ("15-30m", 901...1800), ("30-60m", 1801...3600),
            ("1-2h", 3601...7200), (">2h", 7201...86400)
        ]
        return buckets.map { (label, range) in
            (label, store.sessions.filter { range.contains($0.duration) }.count)
        }
    }

    func topStudyDays(limit: Int) -> [(label: String, total: TimeInterval, count: Int)] {
        let cal     = Calendar.current
        let grouped = Dictionary(grouping: store.sessions) { cal.startOfDay(for: $0.date) }
        let fmt     = DateFormatter(); fmt.dateFormat = "EEE d MMM"
        return grouped
            .sorted { a, b in a.value.reduce(0){$0+$1.duration} > b.value.reduce(0){$0+$1.duration} }
            .prefix(limit)
            .map { (fmt.string(from: $0.key), $0.value.reduce(0){$0+$1.duration}, $0.value.count) }
    }

    func thisWeekDaily() -> [(day: String, hours: Double, isToday: Bool)] {
        let cal   = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let fmt   = DateFormatter(); fmt.dateFormat = "EEE"
        return (0..<7).map { offset in
            let day   = cal.date(byAdding: .day, value: offset, to: start)!
            let hrs   = store.sessions.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0.0) { $0 + $1.duration / 3600 }
            return (fmt.string(from: day), hrs, cal.isDateInToday(day))
        }
    }

    func difficultyRanking() -> [(subject: String, avg: Double)] {
        store.subjectTotals.compactMap { item in
            let rated = store.sessions.filter { $0.subject == item.subject && $0.difficulty > 0 }
            guard !rated.isEmpty else { return nil }
            let avg = Double(rated.map(\.difficulty).reduce(0,+)) / Double(rated.count)
            return (item.subject, avg)
        }
        .sorted { $0.avg < $1.avg }
    }

    func bestStreakDates() -> String {
        let cal  = Calendar.current
        let days = Set(store.sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best: (start: Date, len: Int) = (Date(), 0)
        var curStart = Date(); var cur = 0; var prev: Date? = nil
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 {
                cur += 1
            } else { curStart = d; cur = 1 }
            if cur > best.len { best = (curStart, cur) }
            prev = d
        }
        guard best.len > 0 else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "d MMM"
        return "From \(fmt.string(from: best.start))"
    }

    func bestDayForSessions() -> String {
        let cal     = Calendar.current
        let grouped = Dictionary(grouping: store.sessions) { cal.startOfDay(for: $0.date) }
        guard let best = grouped.max(by: { $0.value.count < $1.value.count }) else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "d MMM"
        return fmt.string(from: best.key)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
