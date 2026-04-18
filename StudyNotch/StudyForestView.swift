import SwiftUI

struct StudyForestView: View {
    var sessions = SessionStore.shared
    var subStore = SubjectStore.shared
    
    @State private var animateGrowth = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Study Forest").font(.system(size: 22, weight: .bold))
                    Text("Each tree represents a day of hard work.").font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
                // Legend
                HStack(spacing: 12) {
                    legendItem("Sprout", "leaf.fill", .green, "< 1h")
                    legendItem("Tree", "tree.fill", .green, "1-3h")
                    legendItem("Old Growth", "tree.fill", .mint, "> 3h")
                }
            }
            .padding(24)
            
            // Forest Landscape
            ZStack(alignment: .bottom) {
                // Ground
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [Color(red:0.1, green:0.25, blue:0.12), Color(red:0.05, green:0.15, blue:0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 100)
                    .offset(y: 40)
                
                // Trees
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(last30Days(), id: \.date) { day in
                            TreeItem(day: day, animate: animateGrowth)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                animateGrowth = true
            }
        }
    }
    
    func legendItem(_ name: String, _ icon: String, _ color: Color, _ sub: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 12))
            Text(name).font(.system(size: 9, weight: .bold))
            Text(sub).font(.system(size: 8)).foregroundColor(.secondary)
        }
    }
    
    struct DayStudy {
        let date: Date
        let hours: Double
        let primarySubject: String?
    }
    
    func last30Days() -> [DayStudy] {
        let cal = Calendar.current
        return (0..<30).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let daySessions = sessions.sessions.filter { cal.isDate($0.startTime, inSameDayAs: date) }
            let totalHours = daySessions.reduce(0) { $0 + $1.duration } / 3600.0
            let topSub = daySessions.max(by: { $0.duration < $1.duration })?.subject
            return DayStudy(date: date, hours: totalHours, primarySubject: topSub)
        }
    }
}

struct TreeItem: View {
    let day: StudyForestView.DayStudy
    let animate: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // The Tree
            if day.hours > 0 {
                ZStack(alignment: .bottom) {
                    // Trunk
                    Rectangle()
                        .fill(Color(red:0.35, green:0.25, blue:0.15))
                        .frame(width: 4, height: trunkHeight)
                    
                    // Foliage
                    Image(systemName: treeIcon)
                        .font(.system(size: treeSize))
                        .foregroundColor(treeColor)
                        .offset(y: -trunkHeight + 8)
                        .shadow(color: treeColor.opacity(0.3), radius: 4)
                }
                .scaleEffect(animate ? 1.0 : 0.01)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(day.date.timeIntervalSinceNow / -86400) * 0.05), value: animate)
            } else {
                // Empty plot
                Circle().fill(Color.white.opacity(0.05)).frame(width: 4, height: 4)
            }
            
            // Date Label
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(day.hours > 0 ? .white.opacity(0.5) : .white.opacity(0.1))
        }
        .frame(width: 30)
    }
    
    var treeIcon: String {
        if day.hours >= 3 { return "tree.fill" }
        if day.hours >= 1 { return "tree.fill" }
        return "leaf.fill"
    }
    
    var treeSize: CGFloat {
        if day.hours >= 3 { return 40 }
        if day.hours >= 1 { return 28 }
        return 14
    }
    
    var trunkHeight: CGFloat {
        if day.hours >= 3 { return 25 }
        if day.hours >= 1 { return 15 }
        return 5
    }
    
    var treeColor: Color {
        if day.hours >= 3 { return .mint }
        if day.hours >= 1 { return .green }
        return Color(red: 0.6, green: 0.9, blue: 0.4)
    }
}
